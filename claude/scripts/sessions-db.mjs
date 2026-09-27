// Writes one hook event into the sessions index. Usage: node sessions-db.mjs start|end
// Stdin, as sent by claude/hooks/session-index.sh: three lines of git facts gathered on the
// session's own OS (branch, origin URL, git common dir), then the hook payload JSON.
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';

const DB_PATH = process.env.CLAUDE_SESSIONS_DB ?? 'C:/work/claude-data/sessions.db';

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
function ticketFromBranch(branch) {
  const match = branch.match(/^[^/]+\/([a-z]+-\d+)(?:-|$)/i);
  return match ? match[1].toUpperCase() : null;
}

// {org}/{repo} from origin; without origin, the main checkout's directory name, which the common
// dir (<checkout>/.git) gives for a checkout and all its worktrees alike.
function repoFrom(origin, commonDir) {
  if (origin) return origin.replace(/\.git$/, '').split(/[/:]/).filter(Boolean).slice(-2).join('/');
  if (commonDir) return commonDir.split(/[\\/]/).filter(Boolean).at(-2) ?? null;
  return null;
}

const event = process.argv[2];
const [branch, origin, commonDir, ...rest] = readFileSync(0, 'utf8').split('\n');
const payload = JSON.parse(rest.join('\n'));
const now = new Date().toISOString();

mkdirSync(dirname(DB_PATH), { recursive: true });
const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA busy_timeout = 5000');
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
} else if (event === 'end') {
  db.prepare(`
    UPDATE sessions SET ended_at = ?, end_reason = ?, last_active_at = ?
    WHERE session_id = ?`).run(now, payload.reason ?? null, now, payload.session_id);
} else {
  throw new Error(`unknown event: ${event}`);
}
db.close();
