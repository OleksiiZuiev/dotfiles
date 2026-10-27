// The plan registry: owns the plans table and the reads behind `plan` (plan.sh). Usage is `plan --help`.
//
//   node plan.mjs register <slug> <note|document URL> [--title <title>]
//   node plan.mjs list [--json]
//   node plan.mjs status <slug> [--json]
//   node plan.mjs close <slug> closed|cancelled [--reason <reason>]
//
// A vault plan is a note whose `## Tasks` section lists its tasks as [[ID]] links. That list is the
// membership; each task's `plan:` link points back, and `status` reports where the two disagree. A
// Linear document plan has the same shape in Linear (linear-doc.mjs).
import { existsSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { createDb, DB_PATH, openDb } from '../lib/db.mjs';
import { projectForId, readTasks } from '../tasks/task.mjs';
import { documentTitle, linearDocStatus } from './linear-doc.mjs';

const VAULT = process.env.CLAUDE_VAULT_DIR ?? 'C:/work/github/OleksiiZuiev/projects-obsidian';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS plans (
  slug TEXT PRIMARY KEY,
  home TEXT NOT NULL,
  locator TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  closed_at TEXT,
  close_reason TEXT
) STRICT`;

function fail(message) {
  console.error(`plan: ${message}`);
  process.exit(1);
}

async function register(args) {
  const [slug, locator, ...rest] = args;
  if (!slug || !locator || slug.startsWith('--')) fail('usage: plan register <slug> <note|document URL> [--title <title>]');
  let title = null;
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] !== '--title' || rest[i + 1] === undefined) fail(`unknown option ${rest[i]}`);
    title = rest[++i];
  }
  const home = locator.startsWith('https://linear.app/') ? 'linear-doc' : 'vault';
  if (home === 'linear-doc') {
    title ??= await documentTitle(locator);
  } else {
    const file = join(VAULT, locator);
    if (!existsSync(file)) fail(`no note ${file}`);
    title ??= readFileSync(file, 'utf8').match(/^# (.+?)\s*$/m)?.[1] ?? basename(locator, '.md');
  }

  const db = createDb();
  db.exec(SCHEMA);
  try {
    db.prepare(`
      INSERT INTO plans (slug, home, locator, title, status, created_at)
      VALUES (?, ?, ?, ?, 'active', ?)`).run(slug, home, locator, title, new Date().toISOString());
  } catch (error) {
    if (db.prepare('SELECT 1 FROM plans WHERE slug = ?').get(slug)) fail(`${slug} is already registered`);
    throw error;
  }
  db.close();
}

// A database without a plans table holds no plans; neither is created by a read.
function readPlans() {
  if (!existsSync(DB_PATH)) return [];
  const db = openDb();
  try {
    return db.prepare('SELECT * FROM plans ORDER BY created_at').all();
  } catch {
    return [];
  } finally {
    db.close();
  }
}

function printTable(rows) {
  const widths = rows[0].map((_, i) => Math.max(...rows.map((row) => row[i].length)));
  for (const row of rows) console.log(row.map((cell, i) => cell.padEnd(widths[i])).join('  ').trimEnd());
}

function list(args) {
  const plans = readPlans();
  if (args.includes('--json')) return console.log(JSON.stringify(plans, null, 2));
  if (plans.length === 0) return console.log('No plans registered.');
  printTable(plans.map((p) => [p.slug, p.status, p.home, p.title]));
}

const TASK_LINK = /\[\[([A-Z]+-\d+)(?:[|#][^\]]*)?\]\]/g;

function memberIds(note) {
  const section = note.match(/^## Tasks[^\n]*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)?.[1] ?? '';
  return [...new Set([...section.matchAll(TASK_LINK)].map((match) => match[1]))];
}

// The note a `plan:` value links to, by its name: a link may carry a folder, a heading or an alias.
function linkedNote(planValue) {
  return planValue?.match(/\[\[([^\]|#]+)/)?.[1].split('/').at(-1) ?? null;
}

function vaultStatus(plan) {
  const noteName = basename(plan.locator, '.md');
  const ids = memberIds(readFileSync(join(VAULT, plan.locator), 'utf8'));

  const project = plan.locator.match(/^projects\/([^/]+)\//)?.[1];
  const tasksByProject = new Map();
  const tasksOf = (name) => {
    if (!tasksByProject.has(name)) tasksByProject.set(name, readTasks(name));
    return tasksByProject.get(name);
  };
  const find = (id) => {
    const owner = projectForId(id);
    return owner ? tasksOf(owner).find((task) => task.id === id) : undefined;
  };

  const members = ids.map((id) => {
    const task = find(id);
    return task
      ? { id, status: task.status, title: task.title, blockers: task.blockers, workspace: task.workspace, plan: task.plan }
      : { id, status: 'missing', title: '', blockers: [], workspace: null, plan: null };
  });
  const drift = [];
  for (const member of members) {
    if (member.status === 'missing') drift.push(`${member.id} is listed under ## Tasks but has no task`);
    else if (linkedNote(member.plan) !== noteName) drift.push(`${member.id} is listed under ## Tasks but does not link back with plan:`);
  }
  if (project) {
    for (const task of tasksOf(project)) {
      if (linkedNote(task.plan) === noteName && !ids.includes(task.id)) {
        drift.push(`${task.id} links to the plan but is not listed under ## Tasks`);
      }
    }
  }
  return { members: members.map(({ plan: _plan, ...member }) => member), drift };
}

// A task can start early when every open blocker is under way in another workspace: it builds
// against the blocker's agreed contract and only its merge waits. A blocker in the same workspace
// would need the dependent branch stacked on the blocker's, so it keeps the task waiting.
function earlyStart(members) {
  const byId = new Map(members.map((m) => [m.id, m]));
  return members.filter((m) => m.status === 'todo' && m.workspace && m.blockers.length > 0 && m.blockers.every((b) => {
    const blocker = byId.get(b.id);
    return ['in-progress', 'in-review'].includes(b.status) && blocker?.workspace && blocker.workspace !== m.workspace;
  })).map((m) => m.id);
}

async function statusOf(plan) {
  const { members, drift } = plan.home === 'linear-doc' ? await linearDocStatus(plan) : vaultStatus(plan);
  return {
    slug: plan.slug,
    title: plan.title,
    status: plan.status,
    done: members.filter((m) => m.status === 'done').length,
    inReview: members.filter((m) => m.status === 'in-review').length,
    remaining: members.filter((m) => ['todo', 'in-progress', 'missing'].includes(m.status)).length,
    members,
    frontier: members.filter((m) => m.status === 'todo' && m.blockers.length === 0).map((m) => m.id),
    earlyStart: earlyStart(members),
    drift,
  };
}

async function status(args) {
  const [slug, ...rest] = args;
  if (!slug || slug.startsWith('--')) fail('usage: plan status <slug> [--json]');
  const plan = readPlans().find((p) => p.slug === slug);
  if (!plan) fail(`no plan ${slug}`);
  const result = await statusOf(plan);

  if (rest.includes('--json')) return console.log(JSON.stringify(result, null, 2));
  console.log(`${result.slug} — ${result.title} (${result.status})`);
  console.log(`done ${result.done}, in review ${result.inReview}, remaining ${result.remaining}`);
  printTable(result.members.map((m) => [m.id, m.status, m.title,
    m.blockers.map((b) => `blocked by ${b.id} (${b.status})`).join(', ')]));
  console.log(`frontier: ${result.frontier.join(', ') || 'none'}`);
  console.log(`early start: ${result.earlyStart.join(', ') || 'none'}`);
  if (result.drift.length) console.log(['drift:', ...result.drift.map((line) => `  ${line}`)].join('\n'));
}

// `closed` says the plan's work is finished, so it waits for every member; `cancelled` does not.
async function close(args) {
  const [slug, status, ...rest] = args;
  if (!slug || !['closed', 'cancelled'].includes(status)) fail('usage: plan close <slug> closed|cancelled [--reason <reason>]');
  let reason = null;
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] !== '--reason' || rest[i + 1] === undefined) fail(`unknown option ${rest[i]}`);
    reason = rest[++i];
  }
  const plan = readPlans().find((p) => p.slug === slug);
  if (!plan) fail(`no plan ${slug}`);
  if (plan.status !== 'active') fail(`${slug} is already ${plan.status}`);
  if (status === 'closed') {
    const open = (await statusOf(plan)).members.filter((m) => ['todo', 'in-progress', 'in-review', 'missing'].includes(m.status));
    if (open.length) {
      fail(`${slug} has open tasks: ${open.map((m) => `${m.id} (${m.status})`).join(', ')}; cancel or detach them, or close it as cancelled`);
    }
  }

  const db = createDb();
  db.prepare('UPDATE plans SET status = ?, closed_at = ?, close_reason = ? WHERE slug = ?')
    .run(status, new Date().toISOString(), reason, slug);
  db.close();
}

const commands = { register, list, status, close };
const [command, ...args] = process.argv.slice(2);
if (!commands[command]) fail('usage: plan register|list|status|close ... (see plan --help)');
try {
  await commands[command](args);
} catch (error) {
  fail(error.message);
}
