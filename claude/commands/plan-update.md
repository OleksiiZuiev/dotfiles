---
argument-hint: "<slug> [what changed]"
---

# plan-update

Proposes the changes a plan's note and tasks need, shows them as one diff, and applies only what the user confirms.

Vault paths here (`projects/…`, the plan note, task files) are relative to the vault root, so the command works from any directory: resolve the root once with `echo "${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}"` and read and write under it.

## Usage

```
/plan-update <slug> [what changed]
```

## Behavior

1. **Resolve the plan**:
   - If a slug is given, use it
   - Otherwise run `plan list`; with one active plan use it, with several show a numbered menu
   - With no plans, say so and stop
2. **Read it**: run `plan status <slug> --json`, then read the plan note at its `locator` (from `plan list --json`). The `plan` CLI is the reader for membership and statuses; the note is read for the prose edits. A plan with `home: linear-doc` is a Linear document: read it with `get_document` and its tickets with `get_issue`, and follow `~/.claude/skills/plan-homes/linear-doc.md` for every write below
3. **Propose**: from the text after the slug, or from what this session just did, work out what the plan needs:
   - structure: tasks to add, cancel or change, `blocked-by` changes, and the matching lines of the note's `## Tasks` list
   - prose: the "as built" paragraph, open questions, and any section the work made untrue
4. **Show one diff** covering everything, and write nothing yet:
   - note edits in full, as the before and after text; never a summary of an edit
   - task changes as the exact calls: `task new <project> <slug> --title ... --plan <note name> [--blocked-by ...]`, `task set <ID> status <status>`, `task set <ID> blocked-by [<ID>...]` (a blocker may be a Linear ticket outside the plan, by its ID)
   - for a Linear document plan, the document edits as `save_document` patches and the ticket changes as `save_issue` calls, each with its arguments; a new ticket's body in full, ending with its `Workspace:` and `Plan:` lines
   - when there is nothing to change, say so and stop
5. **Confirm**: one `AskUserQuestion` offering apply all, apply some (then ask which), or apply none. Nothing is written before the answer; for a Linear document plan this is not skippable, since every write is visible to the org
6. **Apply exactly what was confirmed**:
   - task frontmatter only through `task new` and `task set`; never hand-write it
   - the note through Edit; a task created here is added to the `## Tasks` list
   - for a Linear document plan, the calls as shown, a ticket created here added to the document's `## Tasks`
7. **Check**: run `plan status <slug>`; report any drift it prints and stop

## Examples

```
/plan-update plans-and-tasks VE-5 added a blocked-by writer; VE-10 now waits on VE-9
```
