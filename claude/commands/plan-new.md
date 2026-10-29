---
argument-hint: "[project-name] [work-note]"
---

# plan-new

Turns an agreed design into a plan: the plan document, its tasks with their blockers, and a registry row. The plan lives in the vault (a note and vault tasks) or in Linear (a Linear document and tickets). Shows everything as one diff and writes only what the user confirms.

Vault paths here (`projects/…`, the plan note, task files) are relative to the vault root, so the command works from any directory: resolve the root once with `echo "${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}"` and read and write under it.

## Usage

```
/plan-new [project-name] [work-note]
```

The planning conversation stays human: this command starts once a design is agreed, either earlier in this conversation or in a named work-note. It does not run the design discussion.

## Behavior

1. **Resolve the project**: the first argument, normalized to lowercase-with-dashes; otherwise list the directories under `projects/` that contain a `tasks.md` and ask for a number
2. **Find the design**:
   - a work-note given as the second argument (a path, or a note name under `projects/{project-name}/work-notes/`): read it, follow its wiki-links
   - otherwise the design agreed in this conversation
   - with neither, say so and stop
3. **Choose the home**, with one `AskUserQuestion`, recommending from the design:
   - **vault** — the tasks are vault tasks of the project; for personal work
   - **Linear document** — the tasks are Linear tickets and the plan is a Linear document; for org work. Follow `~/.claude/skills/plan-homes/linear-doc.md` for its shape and its calls. In the same question, ask for the team the tickets go in and the document's parent (that team, or a Linear project)
4. **Check the prefix** (vault only): `projects/{project-name}/{project-name}.md` must have `id-prefix:` in its frontmatter. If it does not, propose one as `/create-task` does and add it on confirmation
5. **Propose**, writing nothing yet:
   - a **slug** for the plan (lowercase-with-dashes)
   - **vault**: the **plan note**. A named work-note becomes the plan note in place — add the sections it is missing, do not copy it. Otherwise a new `projects/{project-name}/work-notes/{YYYY-MM-DD}-{slug}-plan.md` with frontmatter `created` and `type: plan`, a `# Title`, and the sections `## Context`, `## Design`, `## Tasks` and `## Open questions`. `## Tasks` lists the tasks as `- [[ID]]` lines, IDs only — never statuses
   - **Linear document**: the **document**, with a title and the same four sections, written to stand alone by the `linear-tickets` skill; a named work-note is the source and stays in the vault, citing the document once it exists
   - the **tasks**: each a step that can be built and checked on its own, with a title, a slug (vault), the body (Description, Context, Open Questions, Acceptance Criteria — for a ticket, written by the `linear-tickets` skill, ending with its `Workspace:` and `Plan:` lines) and which other tasks it waits on
6. **Show one diff**:
   - the plan note or document in full, or for a work-note in place, each edit as before and after text
   - the exact calls, in dependency order — a blocker before the tasks that wait on it. A value not known until an earlier call returns is written as a placeholder (`<A>` for a task's ID, `<document URL>`):
     - vault: `task new {project-name} {slug} --title "{title}" --plan {note name} [--blocked-by <A>...]`. A `--blocked-by` may also name a Linear ticket outside the plan (`INT-955`) that the design depends on: `/plan-next` reads it live and lets the task start early once the ticket is under way
     - Linear document: `save_document` creating the document, a `save_issue` per ticket with `blockedBy: [<A>...]`, then the `save_document` patch that lists the real IDs under `## Tasks`
   - each task's body text
   - `plan register {slug} {note path relative to the vault | <document URL>}`
7. **Confirm**: one `AskUserQuestion` offering apply, adjust (then ask what, and show the diff again), or apply none. Nothing is written before the answer. A Linear document's writes are visible to the whole org once made
8. **Apply exactly what was confirmed**, in this order, replacing each placeholder with the value its call returned:
   - vault: the `task new` calls; fill each body in the printed path with Edit, never its frontmatter, which only `task` writes. Then the note, with the real IDs in `## Tasks`
   - Linear document: create the document, then the tickets, then patch the real IDs into `## Tasks`
   - `plan register`
9. **Check**: run `plan status {slug}` and report the counts, the frontier and any drift

## Examples

```
/plan-new vibe-engineering 2026-10-20-durable-store-design
/plan-new vibe-engineering
```

The second form plans the design just agreed in this conversation.
