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
2. **Read it**: run `plan status <slug> --json`. The `plan` CLI is the reader: it parses the plan note's `## Tasks` list and each task's frontmatter, so do not read those files yourself.
3. **Report**, in this order:
   - the plan's title, and its done and remaining counts
   - the frontier: each task ID and title that can be started now, or "nothing is startable" with the blockers of the earliest remaining task
   - the remaining tasks, each with its status and its open blockers
   - drift, if any: each line as the CLI prints it, then which side to fix (the note's `## Tasks` list, or the task's `plan:` link)
4. **Stop there.** This command reads only: do not change a task, a note or the registry, and do not start a task. Starting the frontier is `/work-on`.

## Examples

```
/plan-status plans-and-tasks
```
