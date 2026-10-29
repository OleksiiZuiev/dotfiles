# plan-status

Shows where a plan stands: what is done, what remains, and which tasks can be started now.

## Usage

```
/plan-status [slug]
```

## Behavior

1. **Resolve the plan**:
   - If a slug is given, use it
   - Otherwise run `plan list`; with one active plan use it, with several show a numbered menu
   - With no plans, say so and stop
2. **Read it**: run `plan status <slug> --json`. The `plan` CLI is the reader: it parses the plan's `## Tasks` list and each member's status — a vault task's frontmatter, or a Linear ticket read live — so do not read those yourself.
3. **Report**, in this order:
   - the plan's title, and its done, in-review and remaining counts
   - the frontier: each task ID and title that can be started now, or "nothing is startable" with the blockers of the earliest remaining task
   - the early start (`earlyStart`), when not empty: each task ID and title with the blockers it must merge after
   - the in-review tasks, delivered and waiting for their pull request to merge; a task that still has an open blocker is flagged `merge after {blocker ID} ({status})`
   - the remaining tasks, each with its status and its open blockers; a blocker with `external: true` is a Linear ticket outside the plan, named `{ID} (Linear, {status})`
   - drift, if any: each line as the CLI prints it, then which side to fix: for a vault plan the note's `## Tasks` list or the task's `plan:` link; for a Linear document plan (`home: linear-doc` in `plan list --json`) the document's `## Tasks` list or the ticket's `Plan:` line
4. **Stop there.** This command reads only: do not change a task, a note or the registry, and do not start a task. Starting the frontier is `/work-on`.

## Examples

```
/plan-status plans-and-tasks
```
