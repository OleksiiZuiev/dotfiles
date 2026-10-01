// Ticket title and project from Linear, cached in a table of the sessions database. Only the list
// fetches: a title fetched when a session starts would go stale on a rename.
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

async function query(key, identifiers) {
  const aliases = identifiers.map((identifier, i) => `i${i}: issue(id: ${JSON.stringify(identifier)}) { title project { name } }`);
  const response = await fetch(API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: key },
    body: JSON.stringify({ query: `query { ${aliases.join(' ')} }` }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Linear answered ${response.status}`);
  return response.json();
}

// Fetches the identifiers missing from the cache or older than a day — every one with `force`. One
// unknown identifier nulls the whole response, with its alias in `errors`, so those are cached as
// unknown and the rest asked for again. Throws when Linear cannot be reached; nothing is cached then.
export async function refreshIssues(db, identifiers, { force = false } = {}) {
  db.exec(SCHEMA);
  const cached = cachedIssues(db, identifiers);
  const staleBefore = new Date(Date.now() - MAX_AGE_MS).toISOString();
  const wanted = identifiers.filter((id) => force || !cached.has(id) || cached.get(id).fetched_at < staleBefore);
  if (wanted.length === 0) return;
  const key = readKey();
  if (!key) return;

  const upsert = db.prepare(`
    INSERT INTO linear_issues (identifier, title, project, fetched_at) VALUES (?, ?, ?, ?)
    ON CONFLICT (identifier) DO UPDATE SET title = excluded.title, project = excluded.project, fetched_at = excluded.fetched_at`);
  for (let start = 0; start < wanted.length; start += BATCH) {
    let batch = wanted.slice(start, start + BATCH);
    while (batch.length > 0) {
      const { data, errors = [] } = await query(key, batch);
      const now = new Date().toISOString();
      if (data) {
        batch.forEach((id, i) => upsert.run(id, data[`i${i}`]?.title ?? null, data[`i${i}`]?.project?.name ?? null, now));
        break;
      }
      const unknown = new Set(errors.map((e) => e.path?.[0]).filter(Boolean));
      if (unknown.size === 0) throw new Error(errors[0]?.message ?? 'Linear returned no data');
      batch.forEach((id, i) => unknown.has(`i${i}`) && upsert.run(id, null, null, now));
      batch = batch.filter((_, i) => !unknown.has(`i${i}`));
    }
  }
}
