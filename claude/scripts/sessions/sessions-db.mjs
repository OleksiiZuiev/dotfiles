// The sessions index: owns its schema, every write, and the reads behind `sessions` (sessions.sh).
//
//   node sessions-db.mjs start|end|fill
//     Writes one hook event. Stdin, as sent by session-index.sh: three lines of git
//     facts gathered on the session's own OS (branch, origin URL, git common dir; empty for end and
//     fill), then the hook payload JSON.
//   node sessions-db.mjs list [ticket] [--json] [--refresh] [--width <columns>] [--ticket-contexts <dir>] [--wsl-distro <name>]
//   node sessions-db.mjs show <session-id-prefix | ticket> [--ticket-contexts <dir>] [--wsl-distro <name>]
//   node sessions-db.mjs locate <session-id-prefix | ticket> [--worktree]
//     The session `sessions resume` reopens — a ticket's latest — as four lines: session id, cwd,
//     transcript path, ticket. With --worktree, the session whose directory `sessions new` opens.
import { DatabaseSync } from 'node:sqlite';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { cachedIssues, refreshIssues } from './linear.mjs';

const DB_PATH = process.env.CLAUDE_SESSIONS_DB ?? 'C:/work/claude-data/sessions.db';
const NO_TICKET = '—';

// Timestamps are ISO-8601 text written only from here, via toISOString(), so they sort as text.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  ticket TEXT,
  repo TEXT,
  branch TEXT,
  cwd TEXT,
  transcript_path TEXT,
  started_at TEXT NOT NULL,
  last_active_at TEXT NOT NULL,
  ended_at TEXT,
  end_reason TEXT
) STRICT`;

// Same rule as /ds:work-on: {type}/{prefix-number}-{slug}.
const BRANCH_PATTERN = /^[^/]+\/([a-z]+-\d+)(?:-(.*))?$/i;

// /ds:refine runs before a branch exists, so its ticket comes from the prompt. Only /ds:refine: other
// /ds: commands take a ticket-shaped first argument that means something else (/ds:quick's parent
// task, /ds:distill's PR number).
const REFINE_TICKET_PATTERN = /^\/ds:refine\s+([a-z]+-\d+)\b/i;

function ticketFromBranch(branch) {
  const match = branch.match(BRANCH_PATTERN);
  return match ? match[1].toUpperCase() : null;
}

// {org}/{repo} from origin; without origin, the main checkout's directory name, which the common
// dir (<checkout>/.git) gives for a checkout and all its worktrees alike.
function repoFrom(origin, commonDir) {
  if (origin) return origin.replace(/\.git$/, '').split(/[/:]/).filter(Boolean).slice(-2).join('/');
  if (commonDir) return commonDir.split(/[\\/]/).filter(Boolean).at(-2) ?? null;
  return null;
}

function openDb() {
  const db = new DatabaseSync(DB_PATH);
  db.exec('PRAGMA busy_timeout = 5000');
  return db;
}

function write(event) {
  const [branch, origin, commonDir, ...rest] = readFileSync(0, 'utf8').split('\n');
  const payload = JSON.parse(rest.join('\n'));
  const now = new Date().toISOString();
  const refineTicket = event === 'fill' ? payload.prompt?.match(REFINE_TICKET_PATTERN)?.[1] : null;
  if (event === 'fill' && !refineTicket) return;

  mkdirSync(dirname(DB_PATH), { recursive: true });
  const db = openDb();
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCHEMA);

  // Session boundaries: startup and clear begin a new id; resume reopens an id (inserting it when the
  // session predates the index); compact keeps the id and changes nothing.
  if (event === 'start') {
    if (payload.source !== 'compact') {
      const { changes } = db.prepare(`
        INSERT INTO sessions (session_id, ticket, repo, branch, cwd, transcript_path, started_at, last_active_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (session_id) DO NOTHING`).run(
        payload.session_id, ticketFromBranch(branch), repoFrom(origin, commonDir), branch || null,
        payload.cwd ?? null, payload.transcript_path ?? null, now, now);
      if (payload.source === 'resume' && changes === 0) {
        db.prepare(`
          UPDATE sessions SET ended_at = NULL, end_reason = NULL, last_active_at = ?
          WHERE session_id = ?`).run(now, payload.session_id);
      }
    }
  } else if (event === 'fill') {
    // First ticket wins: a branch ticket, or an earlier /ds:refine in the same session, is kept.
    db.prepare(`
      UPDATE sessions SET ticket = ?, last_active_at = ?
      WHERE session_id = ? AND ticket IS NULL`).run(refineTicket.toUpperCase(), now, payload.session_id);
  } else {
    db.prepare(`
      UPDATE sessions SET ended_at = ?, end_reason = ?, last_active_at = ?
      WHERE session_id = ?`).run(now, payload.reason ?? null, now, payload.session_id);
  }
  db.close();
}

function parseArgs(args) {
  const options = { positional: [], json: false, refresh: false, ticketContexts: null, wslDistro: null, width: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--json') options.json = true;
    else if (args[i] === '--refresh') options.refresh = true;
    else if (args[i] === '--width') options.width = Number(args[++i]) || null;
    else if (args[i] === '--ticket-contexts') options.ticketContexts = args[++i];
    else if (args[i] === '--wsl-distro') options.wslDistro = args[++i];
    else options.positional.push(args[i]);
  }
  return options;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readSessions() {
  if (!existsSync(DB_PATH)) fail(`No sessions recorded yet (${DB_PATH}).`);
  const db = openDb();
  const rows = db.prepare('SELECT * FROM sessions ORDER BY last_active_at DESC').all();
  db.close();
  return rows;
}

// The Linear title, else the first line of the ticket context (`# INT-868: {title}`), else the slug
// of the latest branch.
function titleOf(ticket, latestBranch, ticketContexts, linearTitle) {
  if (linearTitle) return linearTitle;
  if (ticketContexts) {
    try {
      const firstLine = readFileSync(join(ticketContexts, `${ticket}.md`), 'utf8').split(/\r?\n/, 1)[0];
      const title = firstLine.replace(/^#\s*/, '').replace(new RegExp(`^${ticket}:\\s*`, 'i'), '').trim();
      if (title) return title;
    } catch {}
  }
  return latestBranch?.match(BRANCH_PATTERN)?.[2]?.replaceAll('-', ' ') ?? '';
}

// A POSIX path is a WSL session's: reachable only through the distro's share, and only read when the
// list runs from WSL, because touching \\wsl.localhost from Windows can start the WSL VM. Null when
// the path cannot be reached from here.
function reachablePath(path, wslDistro) {
  if (!path?.startsWith('/')) return path ?? null;
  return wslDistro ? `\\\\wsl.localhost\\${wslDistro}${path.replaceAll('/', '\\')}` : null;
}

function directoryExists(cwd, wslDistro) {
  const path = reachablePath(cwd, wslDistro);
  return path === null ? null : existsSync(path);
}

// What the transcript says the session is about. Its line format is Claude Code's, undocumented, so
// every field is best effort and missing when the format moves: kind is the first message's command
// (`/ds:work-on`), title is the `/rename` title, else Claude Code's own latest title, else the first
// message itself. Titles are searched from the end without parsing every line — transcripts run to
// megabytes.
function transcriptFacts(transcriptPath, wslDistro) {
  const facts = { kind: '', title: '', last_prompt: '' };
  const path = reachablePath(transcriptPath, wslDistro);
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return facts;
  }
  // The latest entry of `type` that carries `key` — not every entry does (a `last-prompt` can hold
  // only a message id).
  const lastEntry = (type, key) => {
    for (let at = text.lastIndexOf(`"${key}":`); at >= 0; at = text.lastIndexOf(`"${key}":`, at - 1)) {
      const end = text.indexOf('\n', at);
      try {
        const entry = JSON.parse(text.slice(text.lastIndexOf('\n', at) + 1, end < 0 ? undefined : end));
        if (entry.type === type && entry[key]) return entry[key];
      } catch {}
      if (at === 0) break;
    }
    return '';
  };

  let firstMessage = '';
  for (const line of text.split('\n', 200)) {
    if (!line.includes('"type":"user"')) continue;
    try {
      const entry = JSON.parse(line);
      if (entry.type !== 'user' || entry.isMeta) continue;
      const content = entry.message?.content;
      firstMessage = typeof content === 'string' ? content
        : Array.isArray(content) ? content.map((part) => part.text ?? '').join(' ') : '';
      if (firstMessage) break;
    } catch {}
  }
  const command = firstMessage.match(/<command-name>([^<]*)<\/command-name>/)?.[1];
  facts.kind = command ?? '';
  facts.title = lastEntry('custom-title', 'customTitle') || lastEntry('ai-title', 'aiTitle')
    || (command ? '' : firstMessage.replace(/\s+/g, ' ').trim());
  facts.last_prompt = lastEntry('last-prompt', 'lastPrompt');
  return facts;
}

function ago(iso) {
  const minutes = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

const repoName = (repo) => repo?.split('/').at(-1) ?? '';
const directoryName = (cwd) => cwd?.split(/[\\/]/).filter(Boolean).at(-1) ?? '';
const truncate = (text, max) => (text.length > max ? `${text.slice(0, max - 1)}…` : text);
const truncateFront = (text, max) => (text.length > max ? `…${text.slice(text.length - max + 1)}` : text);

const GAP = 2;
const MIN_FLEXIBLE_WIDTH = 4;

// Fits the table to `width` (no limit when null) by narrowing the widest of the `flexible` columns
// one character at a time. A cut cell ends in an ellipsis, or starts with one in a `cutFront`
// column, where the end is the part worth keeping (a worktree directory's name).
function printTable(header, rows, { flexible, cutFront = [] }, width) {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => r[i].length)));
  const total = () => widths.reduce((sum, w) => sum + w, 0) + GAP * (widths.length - 1);
  while (width && total() > width) {
    const widest = flexible.reduce((a, b) => (widths[b] > widths[a] ? b : a));
    if (widths[widest] <= MIN_FLEXIBLE_WIDTH) break;
    widths[widest]--;
  }
  for (const row of [header, ...rows]) {
    const fit = (cell, i) => (cutFront.includes(i) ? truncateFront : truncate)(cell, widths[i]);
    console.log(row.map((cell, i) => fit(cell, i).padEnd(widths[i])).join(' '.repeat(GAP)).trimEnd());
  }
}

// One row per ticket, from sessions ordered newest first; the no-ticket group last.
function ticketsOf(sessions, ticketContexts) {
  const groups = new Map();
  for (const s of sessions) {
    if (!groups.has(s.ticket)) groups.set(s.ticket, []);
    groups.get(s.ticket).push(s);
  }
  const db = openDb();
  const issues = cachedIssues(db, [...groups.keys()].filter(Boolean));
  db.close();
  return [...groups.entries()]
    .sort(([a], [b]) => (a === null) - (b === null))
    .map(([ticket, rows]) => ({
      ticket,
      title: ticket === null ? '' : titleOf(ticket, rows[0].branch, ticketContexts, issues.get(ticket)?.title),
      project: issues.get(ticket)?.project ?? null,
      repos: [...new Set(rows.map((r) => r.repo).filter(Boolean))].sort(),
      sessions: rows.length,
      last_active_at: rows[0].last_active_at,
      open: rows.some((r) => r.ended_at === null),
    }));
}

// Linear failing leaves the cached and fallback titles; it is reported only when a refetch was asked for.
async function refreshTickets(sessions, force) {
  const identifiers = [...new Set(sessions.map((s) => s.ticket).filter(Boolean))];
  const db = openDb();
  try {
    await refreshIssues(db, identifiers, { force });
  } catch (error) {
    if (force) console.error(`sessions: could not reach Linear (${error.message})`);
  } finally {
    db.close();
  }
}

async function listTickets(sessions, options) {
  await refreshTickets(sessions, options.refresh);
  const tickets = ticketsOf(sessions, options.ticketContexts);

  if (options.json) return console.log(JSON.stringify(tickets, null, 2));
  printTable(['TICKET', 'TITLE', 'REPO', 'SESSIONS', 'LAST ACTIVE', ''], tickets.map((t) => [
    t.ticket ?? NO_TICKET, truncate(t.title, 50), t.repos.map(repoName).join(', '), String(t.sessions),
    ago(t.last_active_at), t.open ? 'open' : '',
  ]), { flexible: [1, 2] }, options.width);
}

function listTicketSessions(sessions, ticket, options) {
  const rows = sessions
    .filter((s) => (ticket === NO_TICKET ? s.ticket === null : s.ticket === ticket.toUpperCase()))
    .map((s) => ({ ...s, ...derivedFacts(s, options.wslDistro) }));
  if (rows.length === 0) fail(`No sessions for ${ticket}.`);

  if (options.json) return console.log(JSON.stringify(rows, null, 2));
  const marker = { true: '', false: ' (gone)', null: ' (?)' };
  printTable(['SESSION', 'LAST ACTIVE', 'KIND', 'TITLE', 'DIRECTORY', ''], rows.map((s) => [
    s.session_id.slice(0, 8), ago(s.last_active_at), s.kind, s.title,
    directoryName(s.cwd) + marker[s.directory_exists], s.ended_at ? '' : 'open',
  ]), { flexible: [2, 3, 4], cutFront: [4] }, options.width);
}

function derivedFacts(session, wslDistro) {
  return { directory_exists: directoryExists(session.cwd, wslDistro), ...transcriptFacts(session.transcript_path, wslDistro) };
}

function printFields(record) {
  const width = Math.max(...Object.keys(record).map((k) => k.length));
  for (const [key, value] of Object.entries(record)) console.log(`${key.padEnd(width)}  ${value ?? ''}`);
}

// A session id starts with eight hex digits before its first `-`, so no ticket identifier is a prefix of one.
const sessionByPrefix = (sessions, prefix) => sessions.find((s) => s.session_id.startsWith(prefix));

function show(prefix, options) {
  if (!prefix) fail('Usage: sessions-db.mjs show <session-id-prefix | ticket>');
  const sessions = readSessions();
  const found = sessionByPrefix(sessions, prefix);
  if (!found) {
    const ticket = ticketsOf(sessions, options.ticketContexts).find((t) => t.ticket === prefix.toUpperCase());
    if (!ticket) fail(`No session or ticket ${prefix}.`);
    return printFields({ ...ticket, repos: ticket.repos.join(', '), open: ticket.open ? 'open' : '' });
  }
  // What the session is about first: the preview pane shows only the top lines.
  const facts = derivedFacts(found, options.wslDistro);
  printFields({ session_id: found.session_id, title: facts.title, kind: facts.kind,
    last_prompt: facts.last_prompt, ...found, ...facts });
}

// Sessions are read newest first, so a ticket's first match is its latest. With `worktree`, the
// latest session whose branch names the ticket: a /ds:refine session in the repo checkout is not
// in the ticket's worktree.
function locate(prefix, worktree) {
  if (!prefix) fail('Usage: sessions-db.mjs locate <session-id-prefix | ticket> [--worktree]');
  const sessions = readSessions();
  const ticket = prefix.toUpperCase();
  const found = worktree
    ? sessions.find((s) => s.branch && ticketFromBranch(s.branch) === ticket)
    : sessionByPrefix(sessions, prefix) ?? sessions.find((s) => s.ticket === ticket);
  if (!found) fail(worktree ? `sessions: no worktree for ${ticket}` : `No session or ticket ${prefix}.`);
  console.log([found.session_id, found.cwd, found.transcript_path, found.ticket].map((v) => v ?? '').join('\n'));
}

const [command, ...args] = process.argv.slice(2);
if (command === 'start' || command === 'end' || command === 'fill') {
  write(command);
} else if (command === 'list') {
  const options = parseArgs(args);
  const [ticket] = options.positional;
  if (ticket) listTicketSessions(readSessions(), ticket, options);
  else await listTickets(readSessions(), options);
} else if (command === 'show') {
  const options = parseArgs(args);
  show(options.positional[0], options);
} else if (command === 'locate') {
  locate(args.find((a) => a !== '--worktree'), args.includes('--worktree'));
} else {
  throw new Error(`unknown command: ${command}`);
}
