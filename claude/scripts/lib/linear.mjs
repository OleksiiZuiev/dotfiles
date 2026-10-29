// Linear's GraphQL API, and a cache of ticket title and project in a table of the shared database
// (db.mjs). Callers fetch on demand: a title fetched when a session starts would go stale on a rename.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const API = process.env.CLAUDE_LINEAR_API ?? 'https://api.linear.app/graphql';
const KEY_FILE = process.env.CLAUDE_LINEAR_KEY_FILE ?? join(homedir(), '.config', 'linear', 'api-key');
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
const TIMEOUT_MS = 3000;
const BATCH = 50;

// A null title marks an identifier Linear does not know, so it is not asked for again until it is stale.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS linear_issues (
  identifier TEXT PRIMARY KEY,
  title TEXT,
  project TEXT,
  fetched_at TEXT NOT NULL
) STRICT`;

export function cachedIssues(db, identifiers) {
  const issues = new Map();
  let select;
  try {
    select = db.prepare('SELECT * FROM linear_issues WHERE identifier = ?');
  } catch {
    return issues;
  }
  for (const identifier of identifiers) {
    const row = select.get(identifier);
    if (row) issues.set(identifier, row);
  }
  return issues;
}

function readKey() {
  try {
    return readFileSync(KEY_FILE, 'utf8').trim() || null;
  } catch {
    return null;
  }
}

function requireKey() {
  const key = readKey();
  if (!key) throw new Error(`no Linear API key in ${KEY_FILE}`);
  return key;
}

async function post(key, query, variables = {}, timeoutMs = TIMEOUT_MS) {
  const response = await fetch(API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: key },
    body: JSON.stringify({ query, variables }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`Linear answered ${response.status}`);
  return response.json();
}

// A ticket's workflow state as a vault task status: the statuses `task --help` lists.
export function ticketStatus(state) {
  if (state.type === 'started') return state.name.toLowerCase() === 'in review' ? 'in-review' : 'in-progress';
  if (state.type === 'completed') return 'done';
  if (state.type === 'canceled' || state.type === 'duplicate') return 'cancelled';
  return 'todo';
}

// The `data` of one query. Throws without a key, when Linear cannot be reached, or on any error.
export async function linearRequest(query, variables, { timeoutMs } = {}) {
  const { data, errors } = await post(requireKey(), query, variables, timeoutMs);
  if (errors?.length) throw new Error(errors[0].message);
  return data;
}

// Each identifier's `fields` (a GraphQL selection), null for an identifier Linear does not know. One
// unknown identifier nulls the whole response, with its alias in `errors`, so those are set aside and
// the rest asked for again. Throws without a key or when Linear cannot be reached.
export async function fetchIssues(identifiers, fields, { key = requireKey(), timeoutMs } = {}) {
  const issues = new Map();
  for (let start = 0; start < identifiers.length; start += BATCH) {
    let batch = identifiers.slice(start, start + BATCH);
    while (batch.length > 0) {
      const aliases = batch.map((identifier, i) => `i${i}: issue(id: ${JSON.stringify(identifier)}) { ${fields} }`);
      const { data, errors = [] } = await post(key, `query { ${aliases.join(' ')} }`, {}, timeoutMs);
      if (data) {
        batch.forEach((id, i) => issues.set(id, data[`i${i}`] ?? null));
        break;
      }
      const unknown = new Set(errors.map((e) => e.path?.[0]).filter(Boolean));
      if (unknown.size === 0) throw new Error(errors[0]?.message ?? 'Linear returned no data');
      batch.forEach((id, i) => unknown.has(`i${i}`) && issues.set(id, null));
      batch = batch.filter((_, i) => !unknown.has(`i${i}`));
    }
  }
  return issues;
}

// Fetches the identifiers missing from the cache or older than a day — every one with `force`.
// Without a key it does nothing; when Linear cannot be reached it throws and nothing is cached.
export async function refreshIssues(db, identifiers, { force = false } = {}) {
  db.exec(SCHEMA);
  const cached = cachedIssues(db, identifiers);
  const staleBefore = new Date(Date.now() - MAX_AGE_MS).toISOString();
  const wanted = identifiers.filter((id) => force || !cached.has(id) || cached.get(id).fetched_at < staleBefore);
  if (wanted.length === 0) return;
  const key = readKey();
  if (!key) return;

  const issues = await fetchIssues(wanted, 'title project { name }', { key });
  const upsert = db.prepare(`
    INSERT INTO linear_issues (identifier, title, project, fetched_at) VALUES (?, ?, ?, ?)
    ON CONFLICT (identifier) DO UPDATE SET title = excluded.title, project = excluded.project, fetched_at = excluded.fetched_at`);
  const now = new Date().toISOString();
  for (const [id, issue] of issues) upsert.run(id, issue?.title ?? null, issue?.project?.name ?? null, now);
}
