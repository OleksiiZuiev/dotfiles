// Vault task files: the one writer of their frontmatter. Usage is `task --help` (task.sh).
//
//   node task.mjs new <project> <slug> [--title <title>] [--blocked-by <ID>...] [--plan <note>] [--status <status>]
//   node task.mjs set <ID> status <status>
//   node task.mjs set <ID> blocked-by [<ID>...]
//   node task.mjs list <project> [--json]
//
// An ID is claimed by exclusively creating the empty marker tasks/.ids/<ID>: two writers can both
// create differently named task files, but only one can create the marker. Markers are never
// removed, so a deleted task's ID is never handed out again.
import { closeSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const VAULT = process.env.CLAUDE_VAULT_DIR ?? 'C:/work/github/OleksiiZuiev/projects-obsidian';
const STATUSES = ['todo', 'in-progress', 'done', 'cancelled'];

function fail(message) {
  console.error(`task: ${message}`);
  process.exit(1);
}

export function frontmatterValue(text, key) {
  const block = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const line = block?.[1].match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'));
  return line?.[1];
}

function projectPrefix(project) {
  const file = join(VAULT, 'projects', project, `${project}.md`);
  if (!existsSync(file)) fail(`no project file ${file}`);
  return frontmatterValue(readFileSync(file, 'utf8'), 'id-prefix');
}

export function projectForId(id) {
  const prefix = id.replace(/-\d+$/, '');
  const projects = join(VAULT, 'projects');
  return readdirSync(projects, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .find((name) => {
      const file = join(projects, name, `${name}.md`);
      return existsSync(file) && frontmatterValue(readFileSync(file, 'utf8'), 'id-prefix') === prefix;
    });
}

export function nextNumber(idsDir, prefix) {
  const taken = new RegExp(`^${prefix}-(\\d+)$`);
  return Math.max(0, ...readdirSync(idsDir).map((name) => Number(name.match(taken)?.[1] ?? 0))) + 1;
}

// `from` is the number this writer read as next; another writer may have claimed it since.
export function claimId(idsDir, prefix, from = nextNumber(idsDir, prefix)) {
  for (let n = from; ; n++) {
    try {
      closeSync(openSync(join(idsDir, `${prefix}-${n}`), 'wx'));
      return `${prefix}-${n}`;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
    }
  }
}

function checkStatus(status) {
  if (!STATUSES.includes(status)) fail(`status must be one of ${STATUSES.join(', ')}; got ${status}`);
}

function newTask(args) {
  const [project, slug, ...rest] = args;
  if (!project || !slug || slug.startsWith('--')) fail('usage: task new <project> <slug> [options]');
  const options = { title: slug, blockedBy: [], plan: null, status: 'todo' };
  for (let i = 0; i < rest.length; i++) {
    const flag = rest[i];
    if (flag === '--blocked-by') {
      while (rest[i + 1] && !rest[i + 1].startsWith('--')) options.blockedBy.push(rest[++i]);
    } else if (flag === '--title' || flag === '--plan' || flag === '--status') {
      if (rest[i + 1] === undefined) fail(`${flag} needs a value`);
      options[flag.slice(2)] = rest[++i];
    } else {
      fail(`unknown option ${flag}`);
    }
  }
  checkStatus(options.status);

  const prefix = projectPrefix(project);
  if (!prefix) fail(`projects/${project}/${project}.md has no id-prefix in its frontmatter`);
  const tasksDir = join(VAULT, 'projects', project, 'tasks');
  const idsDir = join(tasksDir, '.ids');
  for (const blocker of options.blockedBy) {
    if (!taskExists(project, blocker)) fail(`--blocked-by ${blocker}: no such task in ${project}`);
  }
  const template = readFileSync(join(VAULT, 'templates', 'task.md'), 'utf8').replace(/\r\n/g, '\n');

  mkdirSync(idsDir, { recursive: true });
  const id = claimId(idsDir, prefix);
  const lines = ['---', `id: ${id}`, `aliases: [${id}]`, `status: ${options.status}`];
  if (options.blockedBy.length) {
    lines.push(`blocked-by: [${options.blockedBy.map((blocker) => `"[[${blocker}]]"`).join(', ')}]`);
  }
  if (options.plan) lines.push(`plan: "[[${options.plan}]]"`);
  lines.push(`created: ${new Date().toLocaleDateString('sv')}`, '---', '');
  const path = join(tasksDir, `${id} ${slug}.md`);
  writeFileSync(path, `${lines.join('\n')}\n${template.replaceAll('{{title}}', options.title)}`, { flag: 'wx' });
  console.log(id);
  console.log(path);
}

function taskPath(id) {
  const project = projectForId(id);
  const tasksDir = project && join(VAULT, 'projects', project, 'tasks');
  const name = tasksDir && existsSync(tasksDir) && readdirSync(tasksDir).find((file) => file.startsWith(`${id} `) && file.endsWith('.md'));
  return name ? join(tasksDir, name) : null;
}

function blockedByIds(text) {
  return [...(frontmatterValue(text, 'blocked-by') ?? '').matchAll(/\[\[([^\]|]+)/g)].map((match) => match[1]);
}

function taskExists(project, id) {
  return existsSync(join(VAULT, 'projects', project, 'tasks', '.ids', id));
}

// Whether `from` is blocked, directly or through other tasks, by `target`.
function blockedThrough(from, target, seen = new Set()) {
  if (from === target) return true;
  if (seen.has(from)) return false;
  seen.add(from);
  const path = taskPath(from);
  return path !== null && blockedByIds(readFileSync(path, 'utf8')).some((next) => blockedThrough(next, target, seen));
}

function checkBlockers(id, project, blockers) {
  for (const blocker of blockers) {
    if (blocker === id) fail(`${id} cannot be blocked by itself`);
    if (!taskExists(project, blocker)) fail(`blocked-by ${blocker}: no such task in ${project}`);
    if (blockedThrough(blocker, id)) fail(`blocked-by ${blocker}: ${blocker} is already blocked by ${id}, which would make a cycle`);
  }
}

function setField(args) {
  const [id, field, ...values] = args;
  if (!id || !field) fail('usage: task set <ID> status <status> | task set <ID> blocked-by [<ID>...]');
  if (field !== 'status' && field !== 'blocked-by') fail(`only status and blocked-by can be set; got ${field}`);
  if (field === 'status') {
    if (values.length !== 1) fail('usage: task set <ID> status <status>');
    checkStatus(values[0]);
  }
  const path = taskPath(id);
  if (!path) fail(`no task ${id}`);

  const text = readFileSync(path, 'utf8');
  const block = text.match(/^---\r?\n[\s\S]*?\r?\n---/);
  if (!block || !/^status:.*$/m.test(block[0])) fail(`${path} has no status in its frontmatter`);

  let frontmatter;
  if (field === 'status') {
    frontmatter = block[0].replace(/^status:.*$/m, `status: ${values[0]}`);
  } else {
    checkBlockers(id, projectForId(id), values);
    const line = values.length ? `blocked-by: [${values.map((blocker) => `"[[${blocker}]]"`).join(', ')}]` : null;
    const withoutOld = block[0].replace(/^blocked-by:.*\r?\n/m, '');
    frontmatter = line ? withoutOld.replace(/^status:.*$/m, (status) => `${status}\n${line}`) : withoutOld;
  }
  writeFileSync(path, frontmatter + text.slice(block[0].length));
}

// Every task of the project, whatever its status, by ID. A blocker stays open until it is done: a
// cancelled one is listed so the dependent gets a look. `plan` is the raw frontmatter value.
export function readTasks(project) {
  const tasksDir = join(VAULT, 'projects', project, 'tasks');
  if (!existsSync(tasksDir)) fail(`no tasks folder ${tasksDir} (projects/${project})`);

  return readdirSync(tasksDir)
    .filter((name) => /^[A-Z]+-\d+ .*\.md$/.test(name))
    .map((name) => {
      const path = join(tasksDir, name);
      const text = readFileSync(path, 'utf8');
      const blockers = blockedByIds(text)
        .map((id) => {
          const blockerPath = taskPath(id);
          return { id, status: blockerPath ? frontmatterValue(readFileSync(blockerPath, 'utf8'), 'status') : 'missing' };
        })
        .filter((blocker) => blocker.status !== 'done');
      return {
        id: frontmatterValue(text, 'id'),
        status: frontmatterValue(text, 'status'),
        title: text.match(/^# (.+?)\s*$/m)?.[1] ?? name,
        path,
        blockers,
        plan: frontmatterValue(text, 'plan') ?? null,
      };
    })
    .sort((a, b) => Number(a.id.match(/\d+$/)[0]) - Number(b.id.match(/\d+$/)[0]));
}

function listTasks(args) {
  const [project, ...rest] = args;
  if (!project || project.startsWith('--')) fail('usage: task list <project> [--json]');
  const tasks = readTasks(project)
    .filter((task) => task.status === 'todo' || task.status === 'in-progress')
    .map(({ plan, ...task }) => task);

  if (rest.includes('--json')) {
    console.log(JSON.stringify(tasks));
    return;
  }
  for (const task of tasks) {
    const blockers = task.blockers.map((blocker) => `${blocker.id} (${blocker.status})`).join(', ');
    console.log([task.id, task.status, task.title, blockers].join('\t'));
  }
}

if (import.meta.main) {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'new') newTask(args);
  else if (command === 'set') setField(args);
  else if (command === 'list') listTasks(args);
  else fail('usage: task new|set|list ... (see task --help)');
}
