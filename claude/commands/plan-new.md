---
argument-hint: "[project-name] [work-note]"
---

# plan-new

Turns an agreed design into a plan: the plan note, its tasks with their `blocked-by`, and a registry row. Shows everything as one diff and writes only what the user confirms.

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
3. **Check the prefix**: `projects/{project-name}/{project-name}.md` must have `id-prefix:` in its frontmatter. If it does not, propose one as `/create-task` does and add it on confirmation
4. **Propose**, writing nothing yet:
   - a **slug** for the plan (lowercase-with-dashes)
   - the **plan note**: a named work-note becomes the plan note in place — add the sections it is missing, do not copy it. Otherwise a new `projects/{project-name}/work-notes/{YYYY-MM-DD}-{slug}-plan.md` with frontmatter `created` and `type: plan`, a `# Title`, and the sections `## Context`, `## Design`, `## Tasks` and `## Open questions`. `## Tasks` lists the tasks as `- [[ID]]` lines, IDs only — never statuses
   - the **tasks**: each a step that can be built and checked on its own, with a title, a slug, the body (Description, Context, Open Questions, Acceptance Criteria) and which other tasks it waits on
5. **Show one diff**:
   - the note in full, or for a work-note in place, each edit as before and after text
   - the exact calls, in dependency order — a blocker before the tasks that wait on it. A blocker created in the same diff is written as a placeholder (`<A>`) until `task new` prints its ID:
     `task new {project-name} {slug} --title "{title}" --plan {note name} [--blocked-by <A>...]`
   - each task's body text
   - `plan register {slug} {note path relative to the vault}`
6. **Confirm**: one `AskUserQuestion` offering apply, adjust (then ask what, and show the diff again), or apply none. Nothing is written before the answer
7. **Apply exactly what was confirmed**, in this order:
   - the `task new` calls, replacing each placeholder with the ID printed for it; fill each body in the printed path with Edit, never its frontmatter, which only `task` writes
   - the note, with the real IDs in `## Tasks`
   - `plan register`
8. **Check**: run `plan status {slug}` and report the counts, the frontier and any drift

## Examples

```
/plan-new vibe-engineering 2026-10-20-durable-store-design
/plan-new vibe-engineering
```

The second form plans the design just agreed in this conversation.
