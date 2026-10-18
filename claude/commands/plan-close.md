---
argument-hint: "[slug]"
---

# plan-close

Ends a plan: settles each task still open — cancel it, or detach it to the backlog — then marks the plan closed or cancelled in the registry. Shows everything as one diff and writes only what the user confirms.

Vault paths here (`projects/…`, the plan note, task files) are relative to the vault root, so the command works from any directory: resolve the root once with `echo "${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}"` and read and write under it.

## Usage

```
/plan-close [slug]
```

## Behavior

1. **Resolve the plan**:
   - If a slug is given, use it
   - Otherwise run `plan list`; with one active plan use it, with several show a numbered menu of the active ones
   - With no active plans, say so and stop. A plan that is already `closed` or `cancelled` cannot be closed again
2. **Read it**: run `plan status <slug> --json`, then read the plan note at its `locator` (from `plan list --json`). The `plan` CLI is the reader for membership and statuses
3. **Ask how it ends**, with one `AskUserQuestion`:
   - **closed** — the plan's work is finished
   - **cancelled** — the plan is abandoned
   - and an optional reason, recorded as the registry's `close_reason`
4. **Propose, per open task** (`todo` or `in-progress`), one of:
   - **cancel**: `task set <ID> status cancelled`; it stays listed under `## Tasks`
   - **detach**: `task set <ID> plan`, which clears its `plan:` link, and its `- [[ID]]` line removed from the note's `## Tasks`; it stays a detail task in its project's backlog

   Tasks already `done` or `cancelled` stay as they are. A `missing` member (listed under `## Tasks` with no task) is removed from the list. Recommend per task from the plan and the task: detach work that still matters without the plan, cancel work that only made sense inside it
5. **Show one diff** covering everything, and write nothing yet:
   - the task calls, exactly as they will run
   - the note edit in full, as before and after text
   - `plan close <slug> closed|cancelled [--reason "..."]`
6. **Confirm**: one `AskUserQuestion` offering apply all, change some tasks (then ask which, and show the diff again), or apply none. Nothing is written before the answer
7. **Apply in the diff's order**: the task calls, the note through Edit, then `plan close`. Task frontmatter is written only through `task set`. `plan close <slug> closed` refuses while a member is still open; if it does, report its message and stop
8. **Check**: run `plan status <slug>`; report the plan's status and any drift it prints

## Examples

```
/plan-close plans-and-tasks
```
