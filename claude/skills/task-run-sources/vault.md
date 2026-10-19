# task-run source: vault

Read by `/task-run` for a task of a vault project. The vault root is `${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}`. Never parse task frontmatter by hand; the `task` and `plan` commands read and write it.

## Load

1. The project is the one whose `{project}.md` frontmatter has an `id-prefix` equal to the ID's prefix. Read `projects/{project}/CLAUDE.md` when it has content beyond template comments, and keep its instructions for the run.
2. `task list {project} --json` gives `{id, status, title, path, blockers, workspace}`. Not in the output: the task is done, cancelled or unknown; tell the user and stop. A non-empty `blockers`: name them and ask whether to run anyway. Status `in-review`: its pull request is still open; say so and ask whether to run anyway.
3. Run `task set {ID} status in-progress`, then read the file at `path`. Use its Description, Context, Open Questions, Decisions and Acceptance Criteria; a section still holding template placeholder text is asked about like any open question.
4. `workspace` is the repo key (`null`: ask).
5. A `plan:` link in the frontmatter: read that plan note for the bigger picture. The plan's slug is the entry of `plan list --json` whose `locator` ends in `{note name}.md`; with no match the plan is unregistered, so say so and treat the task as having no plan.

## Finish

`task set {ID} status in-review` with `delivery: pr` (the task is done when its pull request merges), `task set {ID} status done` with `delivery: direct`, or `cancelled` when the work showed the task should not be done.

## Record

Launch a subagent that follows the `record-run` skill of the vault (`{vault}/.claude/skills/record-run/SKILL.md`, read by path because the session is not in the vault). Give it the project, the task ID, what was done, the decisions with rationale, the files, the branch, the commit and the pull request. It writes the vault's `change-log.md` and `## Current State`; it does not commit and does not set the status. Report the files it names.
