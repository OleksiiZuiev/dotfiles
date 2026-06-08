---
description: Generate a reviewer-onboarding document for a PR — the problem, a high-level story, a component walkthrough in reading order, decisions with confidence, and obvious smells. Writes the document to a file.
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
- `/ds:explain-pr` (this command) — onboards a reviewer to a PR: coherent story + reading-order walkthrough + decisions/confidence + obvious smells.

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
> ## How This Area Works Today
> <OPTIONAL — include only when the change lands in non-trivial pre-existing structure a reviewer who doesn't know the codebase would need oriented to. Briefly describe the baseline: what the touched modules/area already do and the conventions the change follows, so the walkthrough's delta makes sense against it. Omit this section entirely for small or self-evident PRs.>
>
> ## Component Walkthrough
> <Ordered for comprehension, not compilation. Across components: introduce a prerequisite concept (a new type, or a primitive several others depend on) before its consumers. Within a single component: go top-down — lead with the entry point / orchestrator and its end-to-end flow, then its private helpers explained by the role they serve. Number in reading order.>
>
> ### 1. <shared prerequisite concept> — `path/or/area`
> <A type or primitive that several later components depend on — it earns its early slot only because multiple consumers need it. Keep it short. Short code excerpts (≤10 lines, fenced) only where they illuminate. Reference files as path:line-range.>
>
> ### 2. <orchestrator / entry point> — `path`
> <Lead with what it's for and its flow at a glance (one or two sentences: step → step → step). THEN its private helpers, each tagged with the role the orchestrator gives it:>
> - **`_helper_a`** — (used by this component to …) what it does, plus the one or two non-obvious details that matter.
> - **`_helper_b`** — (used by this component to …) …
>
> ## Decisions & Confidence
> <Notable design/implementation decisions the diff embodies. Calibrate confidence honestly.>
>
> - **<decision>** — Confidence: **high | medium | low**. <why it was likely chosen / what it implies>.
> - ⚠️ **<high-stakes AND uncertain decision>** — Confidence: low. **Confirm with the author** — <why the rest of the change relies on it and what could be wrong if the guess is off>.
>
> ## Obvious Smells
> <Only obviously suspicious things — the cheap catches. NOT a thorough audit. If nothing obvious: "Nothing obvious — defer to `/ds:review` for a thorough pass.">
>
> - `path:line` — <what looks off and why>.
>
> ## Suggested Review Path
> <Short: the order to read the changed files and where to spend attention, by risk/complexity. Follow the same purpose-before-mechanism order as the walkthrough rather than re-deriving a bottom-up one.>
> ```

#### Rules of engagement (append to the prompt)

> - **Orient in the existing code before explaining the delta.** The diff is only the change; a reviewer who doesn't know the codebase needs the baseline it lands in. Before writing the walkthrough, use `git show`, `Grep`, and `Read` to learn what the touched modules already do and the conventions of the area. When that baseline is substantial and a reviewer would need it to follow the change, capture it in the optional "How This Area Works Today" section; otherwise fold it into the narrative. Ground every claim in code you actually read — not in the diff alone.
> - **Order for comprehension, not compilation.** A compiler needs dependencies first; a reviewer needs purpose first. Distinguish two kinds of dependency: a **prerequisite concept** (a new type, or a primitive used by *several* consumers) is worth understanding on its own, so introduce it before its consumers; an **implementation helper** (a private function serving *one* caller) is meaningless in isolation, so introduce it top-down — *after* its caller's purpose and flow are on the table, never before. Applying dependency-first ordering to one orchestrator's private helpers strands the reader in mechanism with no purpose; don't.
> - **Lead any multi-helper component with a "flow at a glance"** — one or two sentences tracing the orchestrator's end-to-end pipeline (step → step → step) — then describe the parts.
> - **Cross-reference every helper to its caller** (e.g. "used by `manage_x` to …") so that even an imperfect order never leaves the reader without an anchor.
> - When the reviewer likely lacks the tech-stack context, briefly expand an essential concept in plain language — just enough to follow the change.
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
- **Single opus agent → coherent narrative.** One generator sees the whole diff, so the story and the ordering stay unified. The sub-agent is read-only; the main agent performs the only file write.
- **Walkthrough is ordered for comprehension, not build order** — purpose before mechanism: a prerequisite concept before its consumers, but an orchestrator before its private helpers (a single-caller helper is meaningless until its caller's intent is on the table).
- **Worktree-friendly.** Uses `gh pr diff`, so you can run it from any branch. To explain a teammate's PR, `gh pr checkout <N>` first — the PR is auto-detected from the current branch.
- **Output path is flexible.** One optional argument: a directory (file generated inside it), a file path (written there), or omitted (default name in CWD).
- **Read-before-overwrite** when the output file already exists — the harness requires it, and regenerating is the intended behavior.
- **Render results as text.** The main agent writes the file and prints the gist; sub-agent return values are invisible to the user.
- **No commits / pushes / ticket-context writes.** Explaining is not ticket work (mirrors `/ds:analyze-pr`). The only file written is the onboarding document.
