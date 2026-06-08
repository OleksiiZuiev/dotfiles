---
description: Generate a reviewer-onboarding document for a PR — the problem, a high-level story, a topological component walkthrough, decisions with confidence, and obvious smells. Writes the document to a file.
allowed-tools: Bash(git *), Bash(gh *), Bash(test *), Bash(mkdir *), Read, Write, Grep, Glob, Task, TodoWrite, mcp__linear-server__get_issue
argument-hint: [<output-file-or-dir>]
---

You are producing a **reviewer-onboarding document** for a pull request — your own or a teammate's. The posture is the helpful author who knows the change is sizeable and offers a personal walkthrough so the reviewer can get up to speed fast, *especially* when the reviewer doesn't have a strong grasp of the codebase or tech stack. The deliverable is a written document, saved to a file, that someone reads before (and while) reviewing.

This is **not** a review. It explains; it does not audit. Obvious smells get a quick flag, but the thorough pass belongs to `/ds:review`.

**Distinction from siblings:**
- `/ds:create-pr` — creates the PR.
- `/ds:pre-review` — cosmetic style/naming/convention pass on the local diff.
- `/ds:review` — opinionated six-dimension substantive audit (fixed output shape).
- `/ds:analyze-pr` — answers *the user's* specific questions about a PR.
- `/ds:polish-pr` — addresses human reviewer comments already posted on the PR.
- `/ds:explain-pr` (this command) — onboards a reviewer to a PR: coherent story + topological walkthrough + decisions/confidence + obvious smells.

## Your Task

### Step 0: Resolve PR, ticket, output path, and diff

1. **PR detection** (auto from current branch):
   ```bash
   gh pr view --json number --jq '.number'
   ```
   If this fails (no PR for the current branch), stop:
   > No PR found for branch `<branch>`. This command explains an existing PR — create one first (`/ds:create-pr` or `gh pr create`), or check out the PR you want explained (`gh pr checkout <number>`), then re-run.

2. **Ticket ID extraction** (same pattern as `/ds:review`, `/ds:analyze-pr`):
   - Run `git branch --show-current`.
   - Strip everything before the first `/`, take the first two `-`-separated segments, uppercase (e.g. `feat/int-419-foo` → `INT-419`).
   - If the branch does not match, set `TICKET_ID=null` and continue without Linear / ticket-context lookups. NOT fatal.

3. **PR metadata:**
   ```bash
   gh pr view <N> --json title,body,url,author,baseRefName
   ```
   Capture `PR_TITLE`, `PR_BODY`, `PR_URL`, `PR_AUTHOR`, `BASE=.baseRefName`.

4. **Diff** — always via `gh pr diff` so the command works from any worktree (including a teammate's PR you've checked out):
   ```bash
   gh pr diff <N> --name-only
   gh pr diff <N>
   ```
   If the diff is empty, stop:
   > No changes on this PR. Nothing to explain.

5. **Resolve the output path** from `$ARGUMENTS`. Default filename: `explain-pr-<N>.md`, or `explain-pr-<N>-<TICKET_ID>.md` when a ticket was detected.
   - `$ARGUMENTS` empty → `OUTPUT="./<default-filename>"` (current working directory).
   - `$ARGUMENTS` is an existing directory (`test -d "$ARGUMENTS"`) → `OUTPUT="$ARGUMENTS/<default-filename>"`.
   - Otherwise → treat `$ARGUMENTS` as a file path → `OUTPUT="$ARGUMENTS"`. If its parent directory doesn't exist, create it: `mkdir -p "$(dirname "$OUTPUT")"`.

6. **Print a banner** as a text message:
   ```
   > /ds:explain-pr — PR #<N> "<title>" — ticket=<ID or "none"> — output=<OUTPUT>
   ```

### Step 0.5: Seed Todo Items

Use TodoWrite to seed the flow so it survives a long session:

1. `📥 Load shared context (CLAUDE.md, ticket, ticket-context)`
2. `🔬 Generate onboarding document (opus agent)`
3. `📝 Write document to <OUTPUT>`
4. `📋 Print summary`

### Step 1: Load Shared Brief

Mark `📥 Load shared context` as `in_progress`. Read into context — this becomes the **shared brief** for the generator:

1. **Repo `CLAUDE.md`** at the repo root (conventions, tech-stack hints).
2. **Linear ticket** (only if `TICKET_ID` is set):
   ```
   mcp__linear-server__get_issue with id=TICKET_ID, includeRelations=true
   ```
   Capture title, description, acceptance criteria, status.
3. **Ticket context file:** `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/<TICKET_ID>.md` — read if it exists. Summarise prior-session decisions so the generator doesn't re-litigate settled questions.
4. **PR title/body** (already fetched in Step 0).
5. **Full diff** (already fetched in Step 0).

Print a brief "context loaded" line:
```
Explaining PR #<N>: <PR title>
Ticket: <TICKET_ID> — <ticket title>  (or "no ticket detected")
Base: <base> · Diff: <files-changed> files
Context file: loaded / not found / no ticket
```
Mark `completed`.

### Step 2: Generate the Onboarding Document (single opus agent)

Mark `🔬 Generate onboarding document` as `in_progress`.

Launch **one** `Task` sub-agent, `subagent_type: "general-purpose"`, **model inherited (opus)** — omit the `model` field. The sub-agent does the analysis and **returns the full markdown document** as its final message (it does not write files).

**Sub-agent allowed tools:** `Bash(git diff*), Bash(git log*), Bash(git show*), Read, Grep, Glob`. No `Edit`/`Write` — analysis only; the main agent writes the file.

Prompt = the **shared brief** below, then the **document spec**, then the **rules**.

#### Shared brief — prepend to the sub-agent prompt

> You are writing a reviewer-onboarding document for PR #<N> in the current repo. Below is the shared context. Absorb it, then produce the document described after the brief.
>
> **PR title:** <title>
> **PR body:**
> <body>
>
> **Linear ticket:** <TICKET_ID> — <title>
> **Linear description / acceptance criteria:**
> <description-and-acceptance-criteria, or "no ticket detected">
>
> **Prior decisions from ticket-context file** (respect these — do NOT re-litigate):
> <bulleted summary of decisions from previous sessions, or "no prior context">
>
> **Repo conventions:** see `CLAUDE.md` at the repo root.
>
> **Diff to explain:**
> ```diff
> <full diff from gh pr diff>
> ```

#### Document spec — the sub-agent must return exactly this shape

> Produce ONE markdown document with these sections, in order:
>
> ```
> # PR Onboarding — PR #<N>: <title>
>
> > Branch `<branch>` → `<base>` · Ticket: <ID or none> · Generated <YYYY-MM-DD>
> > Reviewer-onboarding doc (not a review). For a substantive audit run `/ds:review`; for targeted questions, `/ds:analyze-pr`.
>
> ## The Problem
> <2–5 sentences: the problem this PR solves, grounded in the ticket + PR body. If no ticket, infer from the diff and say you inferred it.>
>
> ## High-Level Overview
> <The coherent story of what's inside — the shape and intent of the change as a whole, the strategy taken. A few short paragraphs. The "if you read nothing else" section.>
>
> ## Component Walkthrough
> <Topologically ordered: a component that others depend on is described BEFORE its dependents. Number in dependency order.>
>
> ### 1. <component / layer> — `path/or/area`
> <What it is, what it does, how it works, how it fits. Short code excerpts (≤10 lines, fenced) only where they illuminate. Reference files as path:line-range.>
>
> ### 2. <component that builds on #1> — `path`
> <…described in terms of what it consumes from earlier components>
>
> ## Decisions & Confidence
> <Notable design/implementation decisions the diff embodies. Calibrate confidence honestly.>
>
> - **<decision>** — Confidence: **high | medium | low**. <why it was likely chosen / what it implies>.
> - ⚠️ **<high-stakes AND uncertain decision>** — Confidence: low. **Confirm with the author** — <why it's load-bearing and what could be wrong if the guess is off>.
>
> ## Obvious Smells
> <Only obviously suspicious things — the cheap catches. NOT a thorough audit. If nothing obvious: "Nothing obvious — defer to `/ds:review` for a thorough pass.">
>
> - `path:line` — <what looks off and why>.
>
> ## Suggested Review Path
> <Short: the order to read the changed files and where to spend attention, by risk/complexity.>
> ```

#### Rules of engagement (append to the prompt)

> - Ground every claim in the diff. The diff alone often doesn't show how a changed symbol is used — use `git show`, `Grep`, and `Read` to inspect surrounding code before asserting how something fits.
> - **Topological ordering is the point of the walkthrough:** work out the dependencies between changed components and describe a dependency before its dependents. If A calls/derives-from B, B comes first.
> - When the reviewer likely lacks the tech-stack context, briefly expand a load-bearing concept in plain language — just enough to follow the change.
> - **Confidence must be honest.** Reserve the ⚠️ "confirm with the author" flag for decisions that are BOTH high-impact AND genuinely uncertain (the "nuclear" ones). Don't flag everything.
> - **Obvious smells only.** Do not enumerate style nits (that's `/ds:pre-review`) and do not run a six-dimension categorized audit (that's `/ds:review`). A handful of cheap, clearly-suspicious catches at most.
> - Respect the prior decisions listed above — don't re-open settled questions.
> - Length proportional to PR size. Don't pad. A small PR gets a short document.
> - Return ONLY the markdown document — no preamble, no "here is the document" wrapper.

Mark `🔬 Generate onboarding document` as `completed` after the sub-agent returns.

### Step 3: Write the Document

Mark `📝 Write document to <OUTPUT>` as `in_progress`.

Write the returned markdown verbatim to `OUTPUT`. If `OUTPUT` already exists, `Read` it first (regenerating is the intent — overwrite is expected). Mark `completed`.

### Step 4: Print Summary

Mark `📋 Print summary` as `in_progress`. Print as a regular text message (users cannot see the sub-agent's return value — only your text):

```
> /ds:explain-pr — wrote the PR onboarding doc to <OUTPUT>.
> PR #<N> "<title>" · <files-changed> files · ticket <ID or none>
```

Then inline the **The Problem** and **High-Level Overview** sections from the document so the gist is visible without opening the file.

Suggest next steps:
- Open `<OUTPUT>` for the full component walkthrough.
- Run `/ds:review` for a substantive audit, or `/ds:analyze-pr <question>` for targeted questions.

Mark `completed`. Done.

## Important Notes

- **Reviewer onboarding, not a review.** Obvious smells only; the thorough audit is `/ds:review`. Do not categorize findings or draft PR comments.
- **Single opus agent → coherent narrative.** One generator sees the whole diff, so the story and the topological ordering stay unified. The sub-agent is read-only; the main agent performs the only file write.
- **Worktree-friendly.** Uses `gh pr diff`, so you can run it from any branch. To explain a teammate's PR, `gh pr checkout <N>` first — the PR is auto-detected from the current branch.
- **Output path is flexible.** One optional argument: a directory (file generated inside it), a file path (written there), or omitted (default name in CWD).
- **Read-before-overwrite** when the output file already exists — the harness requires it, and regenerating is the intended behavior.
- **Render results as text.** The main agent writes the file and prints the gist; sub-agent return values are invisible to the user.
- **No commits / pushes / ticket-context writes.** Explaining is not ticket work (mirrors `/ds:analyze-pr`). The only file written is the onboarding document.
