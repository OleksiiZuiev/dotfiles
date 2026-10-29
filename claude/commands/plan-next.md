---
argument-hint: "[slug]"
---

# plan-next

Picks the next tasks of a plan, checks they are ready, and dispatches a tab per task.

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
   - A plan with `home: linear-doc` in `plan list --json` is a Linear document whose members are tickets: where a step below reads a task file or `task list`, read the ticket with `get_issue` instead, and write to Linear only as `~/.claude/skills/plan-homes/linear-doc.md` says
2. **Close merged tasks**, before the frontier is read so the tasks a merged one blocks reach it. Skip this step for a Linear document plan: Linear closes a ticket itself when its pull request merges. For each member of `plan status <slug> --json` with status `in-review`:
   - No `branch`: leave it as it is and name it in the output
   - The main checkout is the `Path` of the member's `workspace` in `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}`. Look the pull request up through `repo-gh -C`, which takes the account and the repo from that checkout rather than from the vault:
     ```bash
     repo-gh -C "{main checkout}" pr list --head "{branch}" --state merged --json number,url --limit 1
     ```
     An empty list leaves the task `in-review`
   - A merged pull request:
     1. `task set {ID} status done`
     2. Fast-forward the main checkout: `git -C "{main checkout}" fetch origin`, then `git -C "{main checkout}" merge --ff-only origin/main` only when `git -C "{main checkout}" branch --show-current` is `main` and `git -C "{main checkout}" status --porcelain --untracked-files=no` prints nothing. When it is not on `main`, is dirty, or the fast-forward fails (local commits), leave it and name the reason. Never rebase main: its local commits are not rewritten
     3. Remove the worktree and its branch: once the last merged member of a main checkout is done, run `bash ~/.claude/scripts/prune-worktrees.sh "{main checkout}"` once for that checkout. Its line naming `{branch}` says whether the worktree was removed or left and why; the removal rule is the script's (`--help`)
   - Report one line per `in-review` member: done (with the main checkout fast-forwarded or left and why, and the worktree removed or left and why), still waiting for the merge, or no branch
3. **Read it**: run `plan status <slug> --json`. The `plan` CLI is the reader, so do not parse the plan note or task frontmatter yourself.
   - The **frontier** and the **early start** (`earlyStart`) are the candidates. `plan status` counts only `todo` tasks as either, so list the members with status `in-progress` separately as "already running", and those with status `in-review` as "in review, waiting for the merge": they are neither offered nor hidden. Flag an in-review member that still has an open blocker as `merge after {blocker ID} ({status})`: you merge by hand, and this is where the merge order shows
   - An early start task has open blockers that are under way in another workspace: it builds against the contract the plan fixes, and its pull request merges only after theirs
   - An **external blocker** (`external: true` on a blocker) is a Linear ticket outside the plan: someone else's work the plan depends on. It is not a member, so it is never offered, refined or dispatched here. Started, it makes its dependent an early start, built against the contract the ticket fixes; not started, it keeps its dependent waiting. Name it as `{ID} (Linear, {status})` wherever blockers are listed. Status `unknown` means Linear could not be reached: say so rather than treat the blocker as not started
   - With an empty frontier and an empty early start, say so, give the blockers of the earliest remaining task, and stop
4. **Select first**: say in prose which candidates you recommend running and why, then offer them in one `AskUserQuestion` call of multi-select questions, each holding at most four tasks, the frontier first in frontier order, then the early start in its own questions. Each option is `{id}: {title}`; an early start option's description names the blockers it merges after. Four questions hold 16 tasks; past 16, offer the first 16 and name the rest. With no task selected, stop. Picking one task runs the steps below for that task alone
   - **Settle the workspace** of each selected task: the repo key is `workspace` in `task list {project} --json`, or for a ticket the `Workspace:` line of its body. Ask for the tasks whose `workspace` is `null` or whose body has no such line together, up to four questions per `AskUserQuestion` call, with the repo names of the repo map plus `vault` as options; use the answer for this run only, without writing it back
   - **Shared checkout**: a selected task whose workspace is `vault`, or whose overlay `~/.claude/overlays/{repo-key}.md` says `worktree: no` under `## Workflow`, runs in that checkout itself. Of the selected tasks sharing one checkout, only the first in frontier order goes on; the others are held back: their status stays as it is, so they stay on the frontier for the next run, and step 9 names them with the checkout. Two sessions in one checkout sweep each other's files into their commits, and both rewrite the project's `change-log.md` and `## Current State` when recording the run
5. **Catch up**, once for the run: the plan's change-log entries and the recently done members (read them through `task list`), plus `git log` on the project since the plan note last changed. Keep it as context; do not dump it
6. **Check readiness**, in this session, for each selected task: read its file (its `path` in `task list --json`) and the plan note. Give a verdict with reasons:
   - *ready*: the sections are filled and the catch-up leaves the premise intact
   - *stale*: something the catch-up found changes the task's premise
   - *open questions*: a section is still a template placeholder, or a question blocks the work

   For each external blocker of the task, read the ticket with `get_issue`: its scope, its "Done when" and any contract section are what the task builds against. The verdict is *stale* when the ticket contradicts the task file or the plan note (a renamed header, a changed entity type, a narrowed scope), or when it was updated after the task file was last changed and the change touches what the task uses; name the ticket and the difference. A ticket still in backlog with no contract yet makes the verdict *open questions*.

   Add a **suggested model** line: a model alias, an effort level and the cue behind them, labelled a heuristic. The cues are read from the task file and the plan note; no measured data backs them:
   - design work (a spike or an architectural decision), a task naming several repos or many files, or a task that still had open sections before refinement: `opus`, effort `high`
   - mechanical work in one repo with every section filled: `sonnet`, effort `medium`
   - anything else: `sonnet`, effort `high`
7. **Refine** each task whose verdict is not *ready*, one after another: resolve it with the user in this session and fill the task file's sections, then recompute the suggested model from the filled file. Never hand-write task frontmatter; a status or `blocked-by` change goes through `task set`. A ticket's body is rewritten by the `linear-tickets` skill and saved with `save_issue` only after the new body is shown and confirmed
8. **Dispatch** each selected task into its workspace, running `/task-run`, in frontier order. Use the suggested model and effort of step 6 for every selected task, without asking, and state them in one line before dispatching it: model, effort and the cue behind them. They become `--model {model} --effort {effort}`. When the catch-up (step 5) or the readiness check (step 6) found something the tab needs that the task does not say (a test already failing on `main`, a setup step, a refinement decision not yet in the task, the contract points of an external blocker the task file does not already carry, with the ticket ID), pass it as `--context "{note}"` and state it in that same line; leave it out otherwise. A wrong pick is fixed with `/model` in the dispatched tab. The pick is not written back to the task. A dispatch that fails is named with its reason in step 9, and the next task is dispatched.

   A task whose workspace is a shared checkout (step 4) needs no branch. For any other, pick the branch prefix without asking: choose `feat`, `fix` or `chore` from the task file and state the choice and the reason in one line. The branch is `{prefix}/{id in lower case}-{slug}` (the slug is the task file name after the ID, or for a ticket its title in lowercase-with-dashes cut to a few words, so `/task-run` recovers the ID from the branch). `--record-branch` records it on a vault task so closing merged tasks (step 2) finds its pull request; a ticket needs no record, because Linear links its pull request by the ID in the branch:
   ```bash
   bash ~/.claude/scripts/dispatch-task.sh "{ID}" "{workspace}" --branch "{prefix}/{id}-{slug}" --record-branch [--context "{note}"] --model {model} --effort {effort}
   ```
   Leave out `--branch` for a shared checkout and `--record-branch` for a ticket.
   `dispatch-task.sh` (its header comment is the contract) makes the worktree or picks the shared checkout, opens the tab and prints the directory it opened in. A non-zero exit is a failed dispatch, reported with its message; `make-worktree.sh` refuses a repo with uncommitted changes, and that is reported to the user rather than worked around. It refuses from WSL: from WSL, say so and print the lines of every task for the user to run from a Windows shell
9. **Stop there.** Report one line per dispatched task: its ID, the branch, the worktree path (or the checkout), the model and effort the tab started with, and the note, if one was passed. Then name the held-back tasks with the checkout they share, and the failed dispatches with the reason. The dispatched `/task-run` sets each task `in-progress`; do not set it here

## Examples

```
/plan-next plans-and-tasks
```
