---
argument-hint: "[slug]"
---

# plan-next

Picks the next task of a plan, checks it is ready, and dispatches a tab that works on it.

Vault paths here (`projects/…`, the plan note, task files) are relative to the vault root, so the command works from any directory: resolve the root once with `echo "${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}"` and read and write under it.

## Usage

```
/plan-next [slug]
```

## Behavior

1. **Resolve the plan**:
   - If a slug is given, use it
   - Otherwise run `plan list`; with one active plan use it, with several show a numbered menu
   - With no plans, say so and stop
2. **Read it**: run `plan status <slug> --json`. The `plan` CLI is the reader, so do not parse the plan note or task frontmatter yourself.
   - The **frontier** is the candidates. `plan status` counts only `todo` tasks as the frontier, so list the members with status `in-progress` separately as "already running": they are neither offered nor hidden
   - With an empty frontier, say so, give the blockers of the earliest remaining task, and stop
3. **Select first**: say in prose which frontier task you recommend and why, then offer one single-select `AskUserQuestion` over the frontier, each option `{id}: {title}`. One task per run: dispatching several tabs into one checkout makes the sessions re-orient on each other's changes
4. **Catch up**, for the chosen task only: the plan's change-log entries and the recently done members (read them through `task list`), plus `git log` on the project since the plan note last changed. Keep it as context; do not dump it
5. **Check readiness**, in this session: read the chosen task's file (its `path` in `task list --json`) and the plan note. Give a verdict with reasons:
   - *ready*: the sections are filled and the catch-up leaves the premise intact
   - *stale*: something the catch-up found changes the task's premise
   - *open questions*: a section is still a template placeholder, or a question blocks the work
6. **Refine** when the verdict is not *ready*: resolve it with the user in this session and fill the task file's sections. Never hand-write task frontmatter; a status or `blocked-by` change goes through `task set`
7. **Dispatch**: as one Bash call, with the slash command kept inside one quoted argument so it reaches claude as one argument:
   ```bash
   bash ~/.claude/scripts/claude-tab.sh "{ID}" "{vault root}" "/work-on {project} {ID}"
   ```
   `claude-tab.sh` opens a Git Bash tab and refuses from WSL. From WSL, say so and print the line for the user to run from a Windows shell
8. **Stop there.** The dispatched `/work-on` sets the task `in-progress`; do not set it here

## Examples

```
/plan-next plans-and-tasks
```
