// The sessions index: owns its schema, every write, and the reads behind `sessions` (bash.d/sessions.sh).
//
//   node sessions-db.mjs start|end
//     Writes one hook event. Stdin, as sent by claude/hooks/session-index.sh: three lines of git
//     facts gathered on the session's own OS (branch, origin URL, git common dir), then the hook
//     payload JSON.
//   node sessions-db.mjs list [ticket] [--json] [--ticket-contexts <dir>] [--wsl-distro <name>]
//   node sessions-db.mjs show <session-id-prefix>
import { DatabaseSync } from 'node:sqlite';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

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
  } else {
    db.prepare(`
      UPDATE sessions SET ended_at = ?, end_reason = ?, last_active_at = ?
      WHERE session_id = ?`).run(now, payload.reason ?? null, now, payload.session_id);
  }
  db.close();
}

function parseArgs(args) {
  const options = { positional: [], json: false, ticketContexts: null, wslDistro: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--json') options.json = true;
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

// The first line of the ticket context (`# INT-868: {title}`), else the slug of the latest branch.
function titleOf(ticket, latestBranch, ticketContexts) {
  if (ticketContexts) {
    try {
      const firstLine = readFileSync(join(ticketContexts, `${ticket}.md`), 'utf8').split(/\r?\n/, 1)[0];
      const title = firstLine.replace(/^#\s*/, '').replace(new RegExp(`^${ticket}:\\s*`, 'i'), '').trim();
      if (title) return title;
    } catch {}
  }
  return latestBranch?.match(BRANCH_PATTERN)?.[2]?.replaceAll('-', ' ') ?? '';
}

// A POSIX cwd is a WSL session's: reachable only through the distro's share, and only checked when
// the list runs from WSL, because touching \\wsl.localhost from Windows can start the WSL VM.
function directoryExists(cwd, wslDistro) {
  if (!cwd) return null;
  if (!cwd.startsWith('/')) return existsSync(cwd);
  if (!wslDistro) return null;
  return existsSync(`\\\\wsl.localhost\\${wslDistro}${cwd.replaceAll('/', '\\')}`);
}

function ago(iso) {
  const minutes = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function localTime(iso) {
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

const repoName = (repo) => repo?.split('/').at(-1) ?? '';
const truncate = (text, max) => (text.length > max ? `${text.slice(0, max - 1)}…` : text);

function printTable(header, rows) {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => r[i].length)));
  for (const row of [header, ...rows]) {
    console.log(row.map((cell, i) => cell.padEnd(widths[i])).join('  ').trimEnd());
  }
}

function listTickets(sessions, options) {
  const groups = new Map();
  for (const s of sessions) {
    if (!groups.has(s.ticket)) groups.set(s.ticket, []);
    groups.get(s.ticket).push(s);
  }
  const tickets = [...groups.entries()]
    .sort(([a], [b]) => (a === null) - (b === null))
    .map(([ticket, rows]) => ({
      ticket,
      title: ticket === null ? '' : titleOf(ticket, rows[0].branch, options.ticketContexts),
      repos: [...new Set(rows.map((r) => r.repo).filter(Boolean))].sort(),
      sessions: rows.length,
      last_active_at: rows[0].last_active_at,
      open: rows.some((r) => r.ended_at === null),
    }));

  if (options.json) return console.log(JSON.stringify(tickets, null, 2));
  printTable(['TICKET', 'TITLE', 'REPO', 'SESSIONS', 'LAST ACTIVE', ''], tickets.map((t) => [
    t.ticket ?? NO_TICKET, truncate(t.title, 50), t.repos.map(repoName).join(', '), String(t.sessions),
    ago(t.last_active_at), t.open ? 'open' : '',
  ]));
}

function listTicketSessions(sessions, ticket, options) {
  const rows = sessions
    .filter((s) => (ticket === NO_TICKET ? s.ticket === null : s.ticket === ticket.toUpperCase()))
    .map((s) => ({ ...s, directory_exists: directoryExists(s.cwd, options.wslDistro) }));
  if (rows.length === 0) fail(`No sessions for ${ticket}.`);

  if (options.json) return console.log(JSON.stringify(rows, null, 2));
  const marker = { true: '', false: ' (gone)', null: ' (?)' };
  printTable(['SESSION', 'REPO', 'BRANCH', 'DIRECTORY', 'STARTED', 'ENDED'], rows.map((s) => [
    s.session_id.slice(0, 8), repoName(s.repo), s.branch ?? '', (s.cwd ?? '') + marker[s.directory_exists],
    localTime(s.started_at), s.ended_at ? localTime(s.ended_at) : 'open',
  ]));
}

function show(prefix) {
  if (!prefix) fail('Usage: sessions-db.mjs show <session-id-prefix>');
  const session = readSessions().find((s) => s.session_id.startsWith(prefix));
  if (!session) fail(`No session ${prefix}.`);
  const width = Math.max(...Object.keys(session).map((k) => k.length));
  for (const [key, value] of Object.entries(session)) console.log(`${key.padEnd(width)}  ${value ?? ''}`);
}

const [command, ...args] = process.argv.slice(2);
if (command === 'start' || command === 'end') {
  write(command);
} else if (command === 'list') {
  const options = parseArgs(args);
  const [ticket] = options.positional;
  if (ticket) listTicketSessions(readSessions(), ticket, options);
  else listTickets(readSessions(), options);
} else if (command === 'show') {
  show(args[0]);
} else {
  throw new Error(`unknown command: ${command}`);
}
