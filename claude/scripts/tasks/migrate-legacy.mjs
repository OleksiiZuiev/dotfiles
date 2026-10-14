// One-shot: turns each open legacy detail task — a tasks/*.md whose first non-empty line is an open
// `- [ ] ` checkbox — into the task shape task.mjs writes: an ID claimed the same way, the status in
// frontmatter, the file renamed to `<ID> <slug>.md`, and the vault's wiki-links to it rewritten
// (`git mv` rewrites none). Done and checkbox-less legacy files are left as they are. Archived
// projects are skipped.
//
//   source claude/scripts/tasks/task.sh && _sessions_node claude/scripts/tasks/migrate-legacy.mjs [--dry-run]
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { claimId, frontmatterValue, nextNumber } from './task.mjs';

const VAULT = process.env.CLAUDE_VAULT_DIR ?? 'C:/work/github/OleksiiZuiev/projects-obsidian';
const dryRun = process.argv.includes('--dry-run');

function legacyTasks() {
  const projectsDir = join(VAULT, 'projects');
  return readdirSync(projectsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== 'archived')
    .flatMap(({ name: project }) => {
      const tasksDir = join(projectsDir, project, 'tasks');
      if (!existsSync(tasksDir)) return [];
      return readdirSync(tasksDir)
        .filter((file) => file.endsWith('.md'))
        .map((file) => ({ project, tasksDir, file, text: readFileSync(join(tasksDir, file), 'utf8').replace(/\r\n/g, '\n') }))
        .filter(({ text }) => /^\s*- \[ \] /.test(text));
    });
}

function markdownFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name.startsWith('.')) return [];
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return markdownFiles(path);
    return entry.name.endsWith('.md') ? [path] : [];
  });
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const tasks = legacyTasks();
const predicted = new Map();
const renames = [];
for (const task of tasks) {
  const prefix = frontmatterValue(readFileSync(join(VAULT, 'projects', task.project, `${task.project}.md`), 'utf8'), 'id-prefix');
  if (!prefix) {
    console.error(`migrate: projects/${task.project} has open legacy tasks but no id-prefix`);
    process.exit(1);
  }
  const idsDir = join(task.tasksDir, '.ids');
  let id;
  if (dryRun) {
    const n = predicted.get(idsDir) ?? nextNumber(idsDir, prefix);
    predicted.set(idsDir, n + 1);
    id = `${prefix}-${n}`;
  } else {
    mkdirSync(idsDir, { recursive: true });
    id = claimId(idsDir, prefix);
  }

  const stem = task.file.replace(/\.md$/, '');
  const dated = stem.match(/^(\d{4}-\d{2}-\d{2})-(.+)$/);
  const newStem = `${id} ${dated ? dated[2] : stem}`;
  const [checkbox, ...rest] = task.text.replace(/^\s*/, '').split('\n');
  const title = checkbox.replace(/^- \[ \] /, '').trim();
  let body = rest.join('\n').replace(/^\n+/, '');
  if (!body.startsWith('# ')) body = `# ${title}\n\n${body}`;
  const created = dated ? dated[1] : new Date().toLocaleDateString('sv');
  const content = ['---', `id: ${id}`, `aliases: [${id}]`, 'status: todo', `created: ${created}`, '---', '', body].join('\n');

  console.log(`${relative(VAULT, join(task.tasksDir, task.file))} -> ${newStem}.md`);
  renames.push({ stem, newStem });
  if (!dryRun) {
    const moved = spawnSync('git', ['-C', VAULT, 'mv', join(task.tasksDir, task.file), join(task.tasksDir, `${newStem}.md`)], { stdio: 'inherit' });
    if (moved.status !== 0) process.exit(1);
    writeFileSync(join(task.tasksDir, `${newStem}.md`), content);
  }
}

// A link names the file by its stem, with or without a folder path in front: [[tasks/<stem>|…]].
for (const path of markdownFiles(VAULT)) {
  const text = readFileSync(path, 'utf8');
  let rewritten = text;
  for (const { stem, newStem } of renames) {
    rewritten = rewritten.replace(new RegExp(`(\\[\\[(?:[^\\]|#]*/)?)${escapeRegExp(stem)}(?=[|#\\]])`, 'g'), `$1${newStem}`);
  }
  if (rewritten === text) continue;
  console.log(`  links rewritten in ${relative(VAULT, path)}`);
  if (!dryRun) writeFileSync(path, rewritten);
}
