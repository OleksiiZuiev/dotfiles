// The shared SQLite database: its path and how every subsystem opens it. Each subsystem owns its own
// tables and creates them itself.
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export const DB_PATH = process.env.CLAUDE_DATA_DB ?? 'C:/work/claude-data/claude-data.db';

export function openDb() {
  const db = new DatabaseSync(DB_PATH);
  db.exec('PRAGMA busy_timeout = 5000');
  return db;
}

// For writers: also makes the directory and the database file, which `openDb` alone would leave to
// the first write, and puts the file in write-ahead logging.
export function createDb() {
  mkdirSync(dirname(DB_PATH), { recursive: true });
  const db = openDb();
  db.exec('PRAGMA journal_mode = WAL');
  return db;
}
