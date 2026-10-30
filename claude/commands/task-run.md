---
description: Run one task from the vault or from Linear in its workspace — plan, implement, review, deliver, record. Flag: +auto-plan
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill, AskUserQuestion, EnterPlanMode
argument-hint: "[task-ID] [+auto-plan] [extra context]"
---

# task-run

Runs a task from either source — a vault task or a Linear ticket — in the checkout the session was started in. Shaped like `/ds:work-on`. A source adapter owns every read and write of the tracker; this file holds the flow both sources share.

## Contract with the dispatcher

The session starts inside the task's workspace repo, on a branch that carries the task ID, with the vault reachable by absolute path (an added directory when the session was dispatched). Creating the worktree and opening the session is the dispatcher's job, never this command's. The vault path is `${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}`.

## Usage

```
/task-run [task-ID] [+auto-plan] [extra context]
```

`+auto-plan`: write the plan as a `## Plan` section in the reply and skip `EnterPlanMode` and `ExitPlanMode` (the exit tool always asks for approval, so calling it would defeat the flag). Strip it from the arguments before reading the rest as extra context.

## Behavior

1. **Task ID**: the first word of the arguments when it matches `^[A-Za-z]+-\d+$`, else the first two hyphen-separated segments of the branch name after its first `/` (`feature/ve-21-foo` → `VE-21`), upper-cased. With neither, say so and stop.
2. **Source**: run `task list --json` for the project whose `id-prefix` matches the ID's prefix (read the vault's `projects/*/*.md` frontmatter). A match among the open tasks means **vault**, anything else means **Linear**. Read only that source's adapter and follow it from here on:
   - vault: `~/.claude/skills/task-run-sources/vault.md`
   - Linear: `~/.claude/skills/task-run-sources/linear.md`
3. **Load the task** through the adapter. It returns the title, description, context, acceptance criteria, the workspace repo key, the plan link, if any, and the open blockers the user chose to run ahead of.
4. **Check the workspace**: look the repo key up in `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` and compare its path with `git rev-parse --path-format=absolute --git-common-dir` of the current directory (its parent is the main checkout). The key `vault` means the vault checkout. A task with no workspace: ask. On a mismatch stop and name the workspace; say that `/task-dispatch {ID}` or `/plan-next` dispatches into it. Do not edit, branch or create a worktree from the wrong directory.
5. **Read the overlay** `~/.claude/overlays/{repo-key}.md`, the key being the workspace's. `## Workflow` `delivery: pr | direct` decides step 10 (no section: draft pull request); the `worktree:` line belongs to the dispatcher and `github-account:` to `repo-gh`. Its `## Plan directives` feed step 6. The format is defined in `~/.claude/commands/ds/distill.md`.
6. **Plan**: the extra context, when given, is the dispatcher's note for this run (a test already failing on `main`, a setup step): read it with the task, and where the two conflict the note wins. Explore the code, ask clarifying questions with `AskUserQuestion` (grouped, at most 4 per call) where the task leaves a choice open, then draft the plan. Before presenting it, make it name how it complies with the design-level conventions of the files it touches: the global `~/.claude/CLAUDE.md`, every `CLAUDE.md` and `AGENTS.md` from each touched directory to the repo root, and the overlay's plan directives. Name the functions to add and where new code lands; mechanical rules (comment style, naming) are not this step's concern. Without `+auto-plan`, call `EnterPlanMode`, write the plan, and wait for approval. Never change code without an approved plan.
7. **Implement** in the current checkout. In the vault, `task`, `plan` and the run-recording write through its absolute path.
8. **Commit**: exactly one implementation commit in the workspace repo, staging only the files this run changed (never `git add -A`); a dirty tree beforehand is fine. Use the `Co-Authored-By` trailer the session specifies. Skip this step when the workspace is the vault: its auto-backup commits. The review (step 9) adds one commit per applied finding.
9. **Review**, skipped when the workspace is the vault. The findings file is `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{ID}.findings.md`; its format belongs to the `polish-findings` skill. A **round** is one `general-purpose` subagent, waited on, that invokes through the `Skill` tool `/ds:review --bar low --to {file}`, then `/polish-findings +auto {file}`. It returns the counts of applied (a `modified` finding counts as applied), dismissed and escalated findings, one line per finding it decided (finding-id, status with commit, one-line resolution), the full text of each escalated finding, and the head commit. The session edits nothing while a round runs; afterwards a head commit that differs from `git rev-parse HEAD`, or a `git status --porcelain` that differs from its output before the round, fails the review.
    - **Round 1** always runs. When `stack-parent` (a `bash.d` helper that leaves the working tree untouched) prints `{parent} {pr-number|-}`, round 1 adds `--since {git rev-parse origin/{parent}}` with the first word as `{parent}`, so the parent's commits are read-only context and every finding is about this branch's own commits. Without a parent it takes the default range.
    - **Round 2** runs only when round 1 applied or modified a finding, and adds `--since {the implementation commit}`, so it reviews only the commits round 1 added, and its `/polish-findings` run decides only the findings that review added. There is no third round.
    - A review that shows nothing writes no file, so `/polish-findings` runs only when the file exists; that round, and a round whose file has nothing left to decide, succeed with zero counts. A round that errors, omits the counts, or reports that either command stopped on an error fails the review. Stop as for a failed delivery: the task stays `in-progress`, steps 10 to 13 are skipped, and the summary gives the reason, the round that failed, the number of commits after the implementation commit and whether the working tree is clean.
    - With any finding escalated, run `/polish-findings {file}` in the session once the rounds end: the user decides each one. Its commits are not reviewed again. The `Review` counts and the finding lines of the summary are read from the findings file after this pass, each finding once; `escalated` counts every finding sent to the user, whatever the pass decided.
10. **Deliver** per the overlay. When a delivery step fails, stop there: the task stays `in-progress`, steps 11 to 13 are skipped, and the summary gives the reason.
    - `pr`: fetch and rebase on `origin/{branch}` when it diverged, push with `git push -u origin {branch}` (never `--force`), then have a subagent (`model: sonnet`) run `/ds:create-pr` with no arguments and return the URL and number. When a pull request already exists, say so and give its URL. When the task has open blockers, its pull request must not merge before theirs: make `⚠ Merge after {blocker ID} ({blocker title}) is merged.` the first line of its description, one line per blocker, by reading the body with `repo-gh pr view {number} --json body` and writing it back with `repo-gh pr edit {number} --body`, unless the body already starts with those lines.
    - `direct` from a worktree (`git rev-parse --path-format=absolute --git-dir` differs from its `--git-common-dir`):
      1. `git fetch origin`, then `git rebase origin/main`. On a conflict, `git rebase --abort` and stop.
      2. `git push origin HEAD:main` (never `--force`). A rejected push fetches, rebases and pushes once more, then stops.
      3. Fast-forward the main checkout (the parent of `--git-common-dir`) under the fast-forward rule of `~/.claude/commands/plan-next.md` (step 2, Close merged tasks). A main checkout it leaves is not a failed delivery; the summary names the reason.

      The commits reported and recorded are the rebased ones: right after the rebase, the first commit of `origin/main..HEAD` is the implementation commit, and each applied finding's sha is found there by the finding id in its commit message.
    - `direct` in the main checkout (the vault included): the change is already where it belongs.
11. **Finish the task** through the adapter, once step 10 succeeded: with `delivery: pr` it waits for its merge (vault: `task set {ID} status in-review`), with `delivery: direct` it is done (`task set {ID} status done`); `cancelled` if the work showed it should not be done.
12. **Plan**, only for a task with a registered plan link (the adapter says whether it has one): run the `/plan-update {slug}` flow only when this run added or cancelled a task, changed a `blocked-by`, or proved a premise wrong; it proposes and applies nothing before the user confirms its diff. Otherwise end with one line: `Plan {slug} unchanged`. Never write an "as built" paragraph; a decision goes in the run record first.
13. **Record the run** through the adapter: hand it what was done, the decisions with their rationale (only those the session made), the files, the branch, the commit, the pull request and the findings file.
14. **Summary**:
    ```
    Task: {ID} — {title}   Source: vault | Linear
    Workspace: {repo-key}   Delivery: pr | direct
    Change: {one line}   Files: {count}
    Commit: {sha}   PR: {url} (draft) | pushed to origin/main | none
    Review: {applied} applied · {dismissed} dismissed · {escalated} escalated · {rounds} round(s)
    {one line per finding: {finding-id} applied|modified ({sha}, round 1 | round 2 | interactive) — {resolution} | dismissed — {reason} | escalated → applied | dismissed | skipped | undecided}
    Findings file: {file}
    Review failed: round {1 | 2 | interactive} — {reason}; {n} fix commits on the branch; working tree clean | dirty
    Main checkout: fast-forwarded | left: {reason}
    Delivery failed: {reason}
    Plan: {slug} unchanged | updated | none | skipped
    Run recorded: {where} | skipped
    ```
    `Commit` is the implementation commit. A fix tagged `round 2` or `interactive` is delivered without a further review. The `Review` lines are absent for the vault, `Findings file` also when no round wrote a file, `Review failed` appears only when step 9 stopped, `Main checkout` only for `direct` from a worktree, `Delivery failed` only when step 10 stopped.

## Examples

```
/task-run VE-21          # a vault task, from a worktree of its workspace
/task-run                # the ID comes from the branch name
/task-run ENG-123 +auto-plan
```
