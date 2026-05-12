---
description: Multi-dimensional code review of the current PR — simplicity, performance, consistency, readability, extraction. Pick findings to apply, then push.
allowed-tools: Bash(git *), Bash(gh *), Read, Write, Edit, Grep, Glob, Task, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue
argument-hint: [<pr-number>]
---

You are performing a substantive review of a pull request. The goal is to absorb the mechanical reviewer effort on bigger PRs by surfacing the issues a thoughtful human reviewer would actually raise across five dimensions: **simplicity, performance, codebase consistency, readability, and extraction/duplication**. You then ask the user which findings to apply, apply them, commit, push, and keep PR description + ticket context in sync.

**Distinction from siblings:**
- `/ds:pre-review` — style/naming/conventions on the local diff, before push. Cosmetic.
- `/ds:polish-pr` — addresses *human* reviewer comments already posted on the PR.
- `/ds:review` (this command) — substantive code-quality review of the PR, before/between human review rounds.

## Your Task

### Step 0: Detect PR & Gather Inputs

1. **Resolve the PR number.**
   - {{#if $1}}
   Use PR **#{{$1}}**.
   {{else}}
   Auto-detect from the current branch:
   ```bash
   gh pr view --json number --jq '.number'
   ```
   - **If failed** (no PR for current branch): inform the user and stop:
     > No PR found for branch `<branch-name>`. Create one first with `/ds:create-pr` (or `gh pr create`), or pass the number directly: `/ds:review <pr-number>`.
   {{/if}}

2. **Extract ticket ID from branch name** (same pattern as `/ds:work-on`):
   - Run `git branch --show-current`
   - Strip everything before the first `/`, take the first two hyphen-separated segments, uppercase them (e.g., `feature/eng-123-foo` → `ENG-123`)
   - If the branch does not match the pattern, set `TICKET_ID=null` and continue without Linear / ticket-context lookups. This is NOT a fatal error.

3. **Base branch & diff:**
   ```bash
   gh pr view <pr-number> --json baseRefName --jq '.baseRefName'
   git diff origin/<base>...HEAD --stat
   git diff origin/<base>...HEAD
   ```
   If the diff is empty, stop:
   > No changes on this branch versus `origin/<base>`. Nothing to review.

4. **PR metadata:**
   ```bash
   gh pr view <pr-number> --json title,body,url
   ```

### Step 0.5: Pre-Seed Post-Implementation Todo Items

Before doing anything else, use TodoWrite to create these fixed items. They make the multi-step flow survive a long session — same pattern as `/ds:work-on` Step 0.5.

1. `🔬 Analysis: launch review sub-agents`
2. `📋 Findings report & user selection`
3. `🛠️ Implement selected findings`
4. `💾 Commit selected fixes`
5. `🚀 Push to PR`
6. `📝 Update PR description (if scope changed)`
7. `📝 Update ticket context`
8. `✅ Final summary`

### Step 1: Load Shared Context

Read the following into your context. These become the **shared brief** that every analysis sub-agent receives, so they all start with the same picture.

1. **Repo `CLAUDE.md`** at the repo root (conventions).
2. **Linear ticket** (only if `TICKET_ID` is set):
   ```
   mcp__linear-server__get_issue with id=TICKET_ID, includeRelations=true
   ```
   Capture title, description, acceptance criteria, status.
3. **Ticket context file**: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` — read if it exists. Summarize previous-session decisions so the reviewers don't re-litigate settled questions.
4. **PR description** (already fetched in Step 0).
5. **The full diff** (already fetched in Step 0).

Print a brief "Review context loaded" summary so the user sees what the reviewers will see:

```
Reviewing PR #<N>: <PR title>
Ticket: <TICKET_ID> — <ticket title>  (or "no ticket detected")
Base: origin/<base>
Diff: <files-changed> files, +<additions>/-<deletions>
Context file: loaded / not found / no ticket
```

### Step 2: Launch Multi-Agent Analysis (parallel)

Mark `🔬 Analysis: launch review sub-agents` as `in_progress`.

Launch the five reviewers below **in a single message with five parallel `Task` tool calls**. Each call uses `subagent_type: "general-purpose"`. Apply the model tiering shown.

**Sub-agent allowed tools (all five):** `Bash(git diff*), Bash(git log*), Bash(git show*), Read, Grep, Glob`. NO Edit — sub-agents find, the main agent applies.

#### Shared brief — prepend to every sub-agent prompt

> You are reviewing PR #<N> in the current repo. Below is the shared context. After absorbing it, focus only on your dimension (described after this brief).
>
> **PR title:** <title>
> **PR body:**
> <body>
>
> **Linear ticket:** <TICKET_ID> — <title>
> **Linear description / A-C:**
> <description-and-acceptance-criteria>
>
> **Prior decisions from ticket-context file** (do NOT re-litigate these — respect them):
> <bulleted summary of decisions from previous sessions, or "no prior context">
>
> **Repo conventions:** see `CLAUDE.md` at the repo root.
>
> **Diff to review:**
> ```diff
> <full diff against origin/base>
> ```
>
> **Output contract — end your response with this exact block:**
>
> ```
> ## Findings — <Your Dimension>
>
> 1. `path/to/file:line-range` — <one-line summary>
>    **Severity:** high | medium | low
>    **Why:** <1–2 sentence reasoning>
>    **Proposed change:** <concrete, actionable description>
>
> 2. ...
> ```
>
> If clean, return exactly: `## Findings — <Your Dimension>\n\nNo issues found.`
>
> **Rules of engagement:**
> - Return ONLY findings a thoughtful human reviewer would actually raise. If you have to reach for a finding, skip it. Fewer high-signal findings > many low-signal findings.
> - Do NOT propose changes that violate the ticket A/C or any prior decision listed above.
> - You may use `git show`, `Grep`, and `Glob` to look at the surrounding code for context — but stay within your dimension's lane.

#### Per-dimension prompt addendum

After the shared brief, append the dimension-specific instruction:

| Reviewer | Model | Addendum |
|---|---|---|
| **Simplicity** | opus (inherit — omit `model` field) | "Your dimension is **simplicity**. Could the same requirement be met with materially less code, fewer abstractions, or fewer moving parts? Flag: premature abstraction, over-parameterization, speculative generality, layers added for hypothetical futures, indirection that doesn't pay for itself. You may NOT propose changes that violate the ticket A/C." |
| **Performance** | opus (inherit) | "Your dimension is **performance and data-flow correctness**. Look for: wrong data structures (lists where dicts/sets fit, repeated linear scans), N+1 query patterns / inefficient DB access, missing `Include`/eager loading where it matters, unnecessary allocations on hot paths, repeated work that could be hoisted. Skip micro-optimizations a reviewer wouldn't raise." |
| **Consistency** | sonnet | "Your dimension is **codebase consistency**. Compare patterns introduced by the diff against existing patterns for similar problems (use Grep/Glob to find neighbours). Flag: new patterns where an established one exists, inconsistent naming/structure compared with siblings, deviations from repo CLAUDE.md not caught by /ds:pre-review." |
| **Readability** | sonnet | "Your dimension is **readability**. Is the intent of each non-trivial change obvious from the code alone? Flag: unclear names, missing-but-needed early returns, deeply nested conditionals, long functions doing multiple things, magic literals lacking a named constant. Do NOT suggest adding comments — prefer expressive code per repo conventions." |
| **Extraction/Duplication** | sonnet | "Your dimension is **extraction and duplication**. Use Grep to verify duplication is real (not just superficially similar). Flag: duplicated logic within the diff or between the diff and existing code, copy-paste blocks differing only in literals, extract-method candidates. Each finding must reference both/all duplicated sites." |

Mark `🔬 Analysis: launch review sub-agents` as `completed` after all five sub-agents return.

### Step 3: Aggregate & Present Findings

Mark `📋 Findings report & user selection` as `in_progress`.

1. Parse each sub-agent's structured findings block.

2. **Print the full aggregated report as a regular text message** before calling any other tool. The user can ONLY see your text output and the `AskUserQuestion` UI — they cannot see sub-agent return values. Do NOT bundle findings into an `AskUserQuestion` description, do NOT just summarize, do NOT just say "N findings".

   Use this format, with a flat 1..N numbering across the entire report so the multi-select can reference findings unambiguously:

   ```
   ## /ds:review findings — PR #<N> (<title>)

   ### Simplicity (M findings)
   1. `path/to/file:line-range` — <summary> (severity)
      Why: ...
      Proposed: ...

   ### Performance (M findings)
   2. ...

   ### Consistency (M findings)
   ...

   ### Readability (M findings)
   ...

   ### Extraction/Duplication (M findings)
   ...

   **Summary:** <T> findings — H high, M medium, L low.
   ```

3. **Zero-findings short-circuit:** if total findings == 0, print:
   > **Review passed — no substantive findings.**

   Skip Steps 4–6. Still proceed to Step 7 (ticket context update gets a "Review passed" session entry).

4. **User selection** via `AskUserQuestion` with `multiSelect: true`:
   - One option per finding. **Label:** `#N — <dimension> — <short summary>` (truncate to fit). **Description:** `<file:line> (<severity>)`.
   - **If total findings > 12**: skip `AskUserQuestion` entirely (the UI grows unwieldy). Print: *"Reply with comma-separated finding numbers to apply, or `all`, or `none`."* — then wait for a regular text reply and parse it.
   - For the ≤12 path, after the per-finding options, the user can additionally select "Other" and type `all` or `none` to apply everything or skip everything.

5. Record selected finding IDs. If the user selected `none` or nothing, skip Steps 4–6 (still update ticket context).

Mark `📋 Findings report & user selection` as `completed`.

### Step 4: Implement Selected Findings

Mark `🛠️ Implement selected findings` as `in_progress`.

The **main agent** applies the changes directly — no sub-agent. Applying needs the diff context and judgment, and the `/ds:work-on` Step 3 precedent is "main agent implements."

For each selected finding:
1. Read the target file(s) with `Read`.
2. Apply the proposed change with `Edit`. If editing reveals the proposed-change sentence was too coarse, exercise judgment and adjust — note the divergence for the final summary.
3. If multiple findings touch the same file, apply them sequentially.

If applying a finding turns out to be infeasible (would break a test, contradicts a constraint discovered while editing, etc.), record it as **deferred** with the reason and continue with the rest. Surface deferrals in the final summary.

Mark `🛠️ Implement selected findings` as `completed`.

### Step 5: Commit Sub-Agent

Mark `💾 Commit selected fixes` as `in_progress`.

Launch a `general-purpose` sub-agent (`model: "sonnet"`) to commit the applied fixes. Same pattern as `/ds:work-on` Step 7.

**Sub-agent prompt:**
> Commit the current uncommitted changes in the repo.
>
> IMPORTANT: Ignore any gitStatus snapshot from the conversation context — it is stale. You MUST run fresh git commands to see the actual current state.
>
> 1. Run `git status` to see all changes
> 2. Run `git diff` and `git diff --cached` to understand what changed
> 3. Run `git log --oneline -5` to see recent commit message style
> 4. Stage relevant files with `git add <specific files>` (avoid .env, credentials, etc.)
> 5. Generate a commit message. Use the title format: `Review fixes (ds:review): <one-line summary>`. Body: one bullet per applied finding (file:line — short description).
> 6. Commit using HEREDOC format:
>    ```bash
>    git commit -m "$(cat <<'EOF'
>    <message>
>
>    Co-Authored-By: Claude <noreply@anthropic.com>
>    EOF
>    )"
>    ```
> 7. Run `git status` to verify the commit succeeded
> 8. Do NOT push.

**Sub-agent allowed tools:** `Bash(git *)`

Mark `💾 Commit selected fixes` as `completed`.

### Step 6: Push

Mark `🚀 Push to PR` as `in_progress`.

Run `git push`. If the branch has no upstream yet:
```bash
git push -u origin <branch-name>
```

Mark `🚀 Push to PR` as `completed`.

### Step 7: Update PR Description (if scope changed)

Mark `📝 Update PR description (if scope changed)` as `in_progress`.

If Steps 4–6 were skipped (no findings, or user picked `none`), skip this step too — there is nothing to refresh.

Otherwise, mirror `/ds:polish-pr` Step 8:

1. Fetch current PR description:
   ```bash
   gh pr view <pr-number> --json body --jq '.body'
   ```
2. Compare against the post-fix diff stat:
   ```bash
   git diff origin/<base>...HEAD --stat
   ```
3. Detect scope shift — any "yes" means an update is needed:
   - New files in the diff not mentioned in the description?
   - Files removed or significantly changed that the description doesn't reflect?
   - Tests added or removed (Verification / Test plan section stale)?
   - Documentation (README, CLAUDE.md, etc.) added or updated?
   - Did the approach or design change from what the Summary describes?
   - New dependencies, helpers, or utilities introduced?

4. If no scope shift, skip silently.

5. If scope shift detected, present findings and ask via `AskUserQuestion`:
   - **"Update description"** — Revise the PR description to match current state.
   - **"Skip"** — Keep the existing description as-is.

6. If approved, update via `gh pr edit`, preserving existing structure (Goal / Summary / Key Decisions / Linear link per the 2026-03-22 PR-body convention):
   ```bash
   gh pr edit <pr-number> --body "$(cat <<'EOF'
   <updated PR body>
   EOF
   )"
   ```

Mark `📝 Update PR description (if scope changed)` as `completed`.

### Step 8: Update Ticket Context

Mark `📝 Update ticket context` as `in_progress`.

If `TICKET_ID` is `null`, mark this step `completed` with note "No ticket ID — ticket context not updated" and continue.

Otherwise, launch a `general-purpose` sub-agent (`model: "haiku"`) to append a new session entry to `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md`. Pass it:

- **Session title:** `Review fixes via /ds:review` (or `Review passed (no findings)` if zero-findings path)
- **Branch name** (from `git branch --show-current`)
- **Repository name** (from `git remote get-url origin` or `gh repo view --json name`)
- **Accomplished:** bullet list of applied findings (file:line — summary). Empty if zero-findings path.
- **Key decisions:** any divergence from the original proposed change, plus user-selected dismissals where the reasoning is non-trivial.
- **Files changed:** from `git diff HEAD~1 --name-only` (skip if zero-findings path — no commit was made).

The sub-agent should append a new section under `## Sessions` following the existing document template (see `~/dotfiles/claude/CLAUDE.md` "Ticket Context Documents" → Document Template). If the file does not exist, create it.

**Sub-agent allowed tools:** `Bash(git *), Read, Write, Edit`

Mark `📝 Update ticket context` as `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress`.

Print:

```
/ds:review — PR #<N> (<title>)
Findings: <T> total — H high, M medium, L low — across 5 dimensions
Applied: <count>
  - `file:line` — <summary>
  - ...
Deferred (selected but couldn't apply): <count>
  - `file:line` — <summary>: <reason>
Skipped (not selected by user): <count>
Commit: <sha> or n/a
Pushed: yes / no
PR description updated: yes / no / not needed
Ticket context updated: yes / no — <reason if no>
```

Suggest next steps:
- Re-run `/ds:review` after addressing major findings if more rounds needed.
- Proceed to human review (mark PR ready with `gh pr ready` if it's a draft).

Mark `✅ Final summary` as `completed`.

## Important Notes

- **Render findings as text first**: never bundle the report into the `AskUserQuestion` description. The user only sees text messages and the `AskUserQuestion` UI. This is a hard rule, identical to `/ds:work-on` Step 6.
- **Sub-agents are read-only during analysis**: only the main agent applies fixes. Analysis sub-agents have no `Edit` in their allowed tools.
- **Fewer high-signal findings**: every sub-agent prompt instructs to skip borderline issues. We want signal, not coverage.
- **Respect prior decisions**: the ticket-context summary in the shared brief is authoritative — sub-agents must not re-litigate.
- **Scope-shift gating**: PR description update is only offered when the post-fix diff materially differs from what the description claims. Pure readability/style fixes don't trigger it.
- **Always update ticket context** (when a ticket is detected) — including on the zero-findings path. The audit trail matters.
- **`/ds:review` is not `/ultrareview`**: this command is local-only, free, and agent-driven. Do not invoke or reference the cloud `/ultrareview`.
- **Parallel sub-agents**: launch all five reviewers in a single tool-use turn so they run concurrently. Do not chain them.
