---
argument-hint: "<task-ID>"
---

# task-dispatch

Dispatches one vault task by its ID, in a plan or not: checks it is ready, then opens a tab running `/task-run {ID}` in its workspace, as `/plan-next` does for a frontier task.

The vault root is `${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}`; resolve it once and read under it.

## Usage

```
/task-dispatch <task-ID>
```

## Behavior

1. **Find the task**: the project is the one whose `projects/*/*.md` frontmatter has an `id-prefix` equal to the ID's prefix. Find the ID in `task list {project} --json`:
   - Not listed: the task is done, cancelled or unknown; say so and stop
   - Status `in-progress` (already running) or `in-review` (its pull request is open), or a non-empty `blockers`: name it and ask whether to dispatch anyway
   - `workspace` is `null`: ask for it, with the repo names of `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` plus `vault` as options; use the answer for this dispatch only
2. **Check readiness and refine** as `/plan-next` steps 6 (Check readiness) and 7 (Refine) say, for this one task: the catch-up is the task's own project rather than a plan, plus its plan note when the task has a `plan:` link. The suggested model comes from the same rules in step 6.
3. **Dispatch** as `/plan-next` step 8 (Dispatch) says, for this one task: the model and effort (the suggested ones, without asking), the branch prefix and name, and the `dispatch-task.sh` call with `--record-branch`.
4. **Stop there.** Report one line: the ID, the branch (or "shared checkout"), the directory the tab opened in, and the model and effort. A failed dispatch is reported with its message. The dispatched `/task-run` sets the task `in-progress`; do not set it here.

## Examples

```
/task-dispatch VE-41
```
