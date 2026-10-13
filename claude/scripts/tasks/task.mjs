// Vault task files: the one writer of their frontmatter. Usage is `task --help` (task.sh).
//
//   node task.mjs new <project> <slug> [--title <title>] [--blocked-by <ID>...] [--plan <note>] [--status <status>]
//   node task.mjs set <ID> status <status>
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

function frontmatterValue(text, key) {
  const block = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const line = block?.[1].match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'));
  return line?.[1];
}

function projectPrefix(project) {
  const file = join(VAULT, 'projects', project, `${project}.md`);
  if (!existsSync(file)) fail(`no project file ${file}`);
  return frontmatterValue(readFileSync(file, 'utf8'), 'id-prefix');
}

function projectForId(id) {
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

function nextNumber(idsDir, prefix) {
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
    if (!existsSync(join(idsDir, blocker))) fail(`--blocked-by ${blocker}: no such task in ${project}`);
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

function setField(args) {
  const [id, field, value] = args;
  if (!id || !field || value === undefined) fail('usage: task set <ID> status <status>');
  if (field !== 'status') fail(`only status can be set; got ${field}`);
  checkStatus(value);
  const project = projectForId(id);
  const tasksDir = project && join(VAULT, 'projects', project, 'tasks');
  const name = tasksDir && existsSync(tasksDir) && readdirSync(tasksDir).find((file) => file.startsWith(`${id} `) && file.endsWith('.md'));
  if (!name) fail(`no task ${id}`);

  const path = join(tasksDir, name);
  const text = readFileSync(path, 'utf8');
  const block = text.match(/^---\r?\n[\s\S]*?\r?\n---/);
  if (!block || !/^status:.*$/m.test(block[0])) fail(`${path} has no status in its frontmatter`);
  writeFileSync(path, block[0].replace(/^status:.*$/m, `status: ${value}`) + text.slice(block[0].length));
}

if (import.meta.main) {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'new') newTask(args);
  else if (command === 'set') setField(args);
  else fail('usage: task new|set ... (see task --help)');
}
