---
description: Multi-dimensional review of the current PR — surfaces confident findings and smells across simplicity, performance, consistency, readability, extraction, test coverage.
allowed-tools: Bash(git *), Bash(gh *), Read, Grep, Glob, Task, TodoWrite, mcp__linear-server__get_issue
argument-hint: [<pr-number>]
---

You are performing a substantive review of a pull request. The goal is to absorb the mechanical reviewer effort on bigger PRs by surfacing the issues a thoughtful human reviewer would actually raise across six dimensions: **simplicity, performance, codebase consistency, readability, extraction/duplication, and test coverage**.

Every finding is categorized at capture time as either **confident** (concrete proposed change with a trivial/empty counter-argument) or **smell** (real trade-off surfaced by the counter-argument, or no concrete fix). Smells are first-class output — they don't need to come with a fix, and they are not posted as draft PR comments.

The command does not apply changes, commit, or push. It surfaces findings in chat for the user to read and act on selectively in follow-up prompts. The mode-aware behavior:

- **`MODE=own`** (PR author == you): print the full categorized report and write an audit entry to ticket context.
- **`MODE=draft-comments`** (PR author ≠ you): print the full categorized report and additionally render copy-paste-ready `Draft comment:` blocks for **confident findings only**, grouped by `file:line`. Smells appear in the report for your private read but are not drafted as PR comments. No ticket-context writes.

**Distinction from siblings:**
- `/ds:pre-review` — style/naming/conventions on the local diff, before push. Cosmetic.
- `/ds:polish-pr` — addresses *human* reviewer comments already posted on the PR.
- `/ds:review` (this command) — substantive code-quality review of the PR, before/between human review rounds (own or someone else's).

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

3. **PR metadata** (now fetched up front — author is needed for mode detection, base ref for the diff fetch):
   ```bash
   gh pr view <pr-number> --json title,body,url,author,baseRefName
   ```
   Capture: `PR_TITLE`, `PR_BODY`, `PR_URL`, `PR_AUTHOR=.author.login`, `BASE=.baseRefName`.

4. **Mode detection** — auto-decides whether this is your own PR or someone else's:
   ```bash
   gh api user --jq '.login'   # ME
   ```
   - If `PR_AUTHOR == ME` → `MODE=own` (analysis → report → ticket-context audit).
   - Else → `MODE=draft-comments` (analysis → report → draft PR comments for confident findings; no ticket-context write).

   Print a one-liner so the mode is visible up front:
   - `MODE=own`: `> Mode: own (PR authored by <ME>) — report will be printed and ticket context updated.`
   - `MODE=draft-comments`: `> Mode: draft-comments (PR authored by <PR_AUTHOR>, you are <ME>) — report plus draft PR comments for confident findings will be printed; nothing else is written.`

5. **Diff** (mode-aware — `MODE=own` reads the local working tree, `MODE=draft-comments` pulls directly from GitHub so you can be on any branch):
   - **If `MODE=own`:**
     ```bash
     git diff origin/<BASE>...HEAD --stat
     git diff origin/<BASE>...HEAD
     ```
   - **If `MODE=draft-comments`:**
     ```bash
     gh pr diff <pr-number> --name-only   # files-changed list for the context banner
     gh pr diff <pr-number>               # the full unified diff body
     ```

   If the diff is empty, stop:
   > No changes on this PR. Nothing to review.

### Step 0.5: Pre-Seed Post-Implementation Todo Items

Before doing anything else, use TodoWrite to create the per-mode checklist. The seed list mirrors what will actually run so the multi-step flow survives a long session — same pattern as `/ds:work-on` Step 0.5.

**If `MODE=own`:**

1. `🔬 Analysis: launch review sub-agents`
2. `📋 Findings report`
3. `📝 Update ticket context`
4. `✅ Final summary`

**If `MODE=draft-comments`:**

1. `🔬 Analysis: launch review sub-agents`
2. `📋 Findings report`
3. `🗒️ Print draft PR comments (confident only)`
4. `✅ Final summary`

### Step 1: Load Shared Context

Read the following into your context. These become the **shared brief** that every analysis sub-agent receives, so they all start with the same picture.

1. **Conventions files** — the documented rules the diff must comply with. Discover *every* `CLAUDE.md` and `AGENTS.md` that governs a changed file, not just the repo root: a monorepo keeps subsystem rules in nested files, and `CLAUDE.md` is sometimes just a thin pointer to a sibling `AGENTS.md`.
   - Get the changed-file list — `MODE=own`: `git diff origin/<BASE>...HEAD --name-only`; `MODE=draft-comments`: `gh pr diff <pr-number> --name-only`.
   - For each changed file, collect every `CLAUDE.md` and `AGENTS.md` in its directory and all ancestor directories up to the repo root. Take the union and dedupe. Discovery one-liner (own mode — in draft-comments mode swap the first command for the `gh pr diff` form above):
     ```bash
     git diff origin/<BASE>...HEAD --name-only | while read -r f; do
       d=$(dirname "$f")
       while :; do
         for n in CLAUDE.md AGENTS.md; do [ -f "$d/$n" ] && printf '%s\n' "$d/$n"; done
         [ "$d" = "." ] && break
         d=$(dirname "$d")
       done
     done | sort -u
     ```
   - Read each one and keep them ordered **most-specific (deepest path) → least-specific (repo root)** — a nested file refines or overrides the root's rules for files beneath it.
   - If none are found, note "no conventions files" and continue; the Consistency reviewer falls back to inferring conventions from neighbouring code (today's behaviour).
   - In `MODE=draft-comments` the files are read from your current checkout — a fine proxy, since conventions rarely differ from the PR head. If the PR itself adds or edits a conventions file, account for that from the diff.
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
Conventions: <N> files — <paths, most→least specific>  (or "none found")
```

### Step 2: Launch Multi-Agent Analysis (parallel)

Mark `🔬 Analysis: launch review sub-agents` as `in_progress`.

Launch the six reviewers below **in a single message with six parallel `Task` tool calls**. Each call uses `subagent_type: "general-purpose"`. Apply the model tiering shown.

**Sub-agent allowed tools (all six):** `Bash(git diff*), Bash(git log*), Bash(git show*), Read, Grep, Glob`. NO Edit — sub-agents surface findings only; nothing in this command modifies the working tree.

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
> **Repo conventions files** (most-specific → least-specific — read any that bear on your dimension):
> <bulleted list of the discovered `CLAUDE.md` / `AGENTS.md` paths, or "none found">
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
>    **Category:** confident | smell
>    **Why:** <1–2 sentence reasoning>
>    **Counter-argument:** <strongest case against this finding; "none" if no real case exists>
>    **Proposed change:** <concrete description, OR "(needs unpacking)" for smells with no obvious fix>
>    **Code context:**
>    ```diff
>    <~5–10 lines of surrounding code with the proposed change rendered as a unified diff>
>    ```
>
> 2. ...
> ```
>
> If clean, return exactly: `## Findings — <Your Dimension>\n\nNo issues found.`
>
> **Categorization criteria — set `Category` per finding:**
> - **confident** = the proposed change is concrete AND the counter-argument is empty or trivial. Genuine no-brainers (e.g., O(n²) where O(n) is straightforward) land here — their counter-argument is honestly "none".
> - **smell** = the counter-argument exposes a real trade-off a human would need to weigh, OR you cannot articulate a concrete fix. `Proposed change:` may be `(needs unpacking)` for smells; the human will decide what (if anything) to do.
> - **drop entirely** = if writing the counter-argument talks you out of the finding, do not include it. The exercise of writing the counter-argument is part of the bar; weak findings self-prune here.
>
> **Rules of engagement:**
> - Return ONLY findings a thoughtful human reviewer would actually raise. If you have to reach for a finding, skip it. Fewer high-signal findings > many low-signal findings.
> - Every finding MUST have a non-empty `Counter-argument:` field. "none" is acceptable when the finding really has no real case against it (genuine no-brainer) — but the field must be present.
> - Every finding MUST have a `Code context:` block — a unified-diff fenced block showing ~5–10 lines of surrounding code with the change applied as `-`/`+` lines. For smells where `Proposed change:` is `(needs unpacking)`, include the unmodified code excerpt (no diff markers needed) so the reader sees the area in question.
> - Do NOT propose changes that violate the ticket A/C or any prior decision listed above.
> - You may use `git show`, `Grep`, and `Glob` to look at the surrounding code for context — but stay within your dimension's lane.

#### Draft-comments addendum (`MODE=draft-comments` only)

When `MODE=draft-comments`, append the following to the shared brief **before** the per-dimension addendum. It extends the output contract so every confident finding ships with a copy-paste-ready PR comment.

> **Additional output requirement (draft-comments mode):** for every finding with `Category: confident`, append a `**Draft comment:**` block immediately after `**Code context:**`. Smells get no draft comment — they appear in the report but are not posted to the PR.
>
> Updated per-confident-finding shape:
>
> ```
> 1. `path/to/file:line-range` — <one-line summary>
>    **Severity:** high | medium | low
>    **Category:** confident
>    **Why:** <1–2 sentence reasoning>
>    **Counter-argument:** <strongest case against this finding; "none" if no real case exists>
>    **Proposed change:** <concrete, actionable description>
>    **Code context:**
>    ```diff
>    <~5–10 lines as unified diff>
>    ```
>    **Draft comment:**
>    > <GitHub-flavored markdown — see drafting rules below>
> ```
>
> **Drafting rules for the comment:**
> - Write from the reviewer's voice, addressing the PR author directly.
> - Open with the problem in one sentence — no "I noticed that…" / "It seems like…" filler.
> - Follow with a concrete suggestion: actionable, not a vague concern.
> - Prefer a fenced ` ```suggestion ` block when the change is a single small edit GitHub can apply directly. Skip the suggestion block for structural changes.
> - 1–3 sentences total. No restating of severity (that's reviewer mental model, not author-facing).
> - Avoid hedging adjectives ("maybe", "perhaps could possibly"); stay direct but collaborative.
> - Do NOT include the `**Draft comment:**` block on smells (`Category: smell`) — smells are reviewer-only notes.
> - Do NOT include the `**Draft comment:**` block on the `No issues found.` short-circuit.

#### Per-dimension prompt addendum

After the shared brief, append the dimension-specific instruction:

| Reviewer | Model | Addendum |
|---|---|---|
| **Simplicity** | opus (inherit — omit `model` field) | "Your dimension is **simplicity**. Could the same requirement be met with materially less code, fewer abstractions, or fewer moving parts? Flag: premature abstraction, over-parameterization, speculative generality, layers added for hypothetical futures, indirection that doesn't pay for itself. You may NOT propose changes that violate the ticket A/C." |
| **Performance** | opus (inherit) | "Your dimension is **performance and data-flow correctness**. Look for: wrong data structures (lists where dicts/sets fit, repeated linear scans), N+1 query patterns / inefficient DB access, missing `Include`/eager loading where it matters, unnecessary allocations on hot paths, repeated work that could be hoisted. Skip micro-optimizations a reviewer wouldn't raise." |
| **Consistency** | sonnet | "Your dimension is **codebase consistency and conventions compliance** — two parts. **(1) Consistency:** compare patterns introduced by the diff against existing patterns for similar problems (use Grep/Glob to find neighbours). Flag: new patterns where an established one exists, inconsistent naming/structure compared with siblings. **(2) Conventions compliance:** read *in full* every conventions file listed in the shared brief (`CLAUDE.md` / `AGENTS.md`, root and nested). Extract each concrete, checkable rule, then verify the diff complies. A nested file's rule governs files beneath it and refines/overrides the root for those paths. Flag each violation with the **exact rule quoted and its source file cited** (e.g. `src/api/AGENTS.md`). Most rule violations are `confident` — a documented rule is an objective standard, so the counter-argument is usually 'none'; a violation with a legitimate, diff-specific justification becomes a `smell`. Skip purely mechanical formatting/whitespace rules that `/ds:pre-review` already enforces (avoid overlap) unless the diff plainly breaks them. If no conventions files were found, fall back to inferring conventions from neighbouring code." |
| **Readability** | sonnet | "Your dimension is **readability**. Is the intent of each non-trivial change obvious from the code alone? Flag: unclear names, missing-but-needed early returns, deeply nested conditionals, long functions doing multiple things, magic literals lacking a named constant. Do NOT suggest adding comments — prefer expressive code per repo conventions." |
| **Extraction/Duplication** | sonnet | "Your dimension is **extraction and duplication**. Use Grep to verify duplication is real (not just superficially similar). Flag: duplicated logic within the diff or between the diff and existing code, copy-paste blocks differing only in literals, extract-method candidates. Each finding must reference both/all duplicated sites." |
| **Test Coverage** | sonnet | "Your dimension is **test coverage**. For every non-trivial behavior change in the diff — new functions/methods with logic, new conditional branches, new error paths, new public APIs, modified business rules — check whether a test exercises it. Use Grep/Glob to (a) locate test files for the changed code (test-file naming conventions vary by repo: deduce from neighbours and `CLAUDE.md`), and (b) find tests for analogous existing code so you know what 'covered' looks like in *this* repo. Flag: new logic with no test, new conditional branch covered only on the happy path, modified behavior whose existing test was not updated, new public/exported surface without an integration test where the repo's convention requires one. Skip: trivial getters/setters, pure renames, comment/doc-only changes, formatting, generated code, infra/YAML/config, and anything in directories the repo's existing tests do not cover (deduce). Respect the repo's testing posture — if `CLAUDE.md` or neighbour evidence says 'no tests for X', do not invent a requirement. Reference both the diff location and the expected test location (or analogue) in every finding." |

Mark `🔬 Analysis: launch review sub-agents` as `completed` after all six sub-agents return.

### Step 3: Aggregate & Present Findings

Mark `📋 Findings report` as `in_progress`.

1. Parse each sub-agent's structured findings block.

2. **Print the full aggregated report as a regular text message** before calling any other tool. The user can ONLY see your text output — they cannot see sub-agent return values.

   Within each dimension, split findings into two subsections by `Category`: **Confident** then **Smells**. Use a flat 1..N numbering across the entire report so individual findings can be referenced unambiguously in follow-up chat.

   ```
   ## /ds:review findings — PR #<N> (<title>)

   ### Simplicity
   **Confident** (M findings)
   1. `path/to/file:line-range` — <summary> (severity)
      Why: ...
      Counter-argument: ...
      Proposed: ...
      Code context:
      ```diff
      ...
      ```

   **Smells** (K findings)
   2. `path/to/file:line-range` — <summary> (severity)
      Why: ...
      Counter-argument: ...
      Proposed: (needs unpacking) or <description>
      Code context:
      ```diff
      ...
      ```

   ### Performance
   **Confident** (M findings)
   ...
   **Smells** (K findings)
   ...

   ### Consistency
   ...

   ### Readability
   ...

   ### Extraction/Duplication
   ...

   ### Test Coverage
   ...

   **Summary:** <T> findings — <C> confident, <S> smells — across 6 dimensions (H high, M medium, L low).
   ```

   Omit the **Confident** or **Smells** subsection header for any dimension where that subsection is empty (don't print empty `(0 findings)` headers).

3. **Zero-findings short-circuit:** if total findings == 0, print:
   > **Review passed — no substantive findings.**

   - **If `MODE=own`:** proceed to Step 8 (ticket context gets a "Review passed" session entry), then Step 9.
   - **If `MODE=draft-comments`:** skip directly to Step 9 (final summary).

Mark `📋 Findings report` as `completed`.

### Mode branch

- **If `MODE=own`:** proceed to **Step 8** (Update Ticket Context).
- **If `MODE=draft-comments`:** proceed to **Step 3.5** (Print Draft PR Comments), then **Step 9**.

### Step 3.5: Print Draft PR Comments (`MODE=draft-comments` only)

Mark `🗒️ Print draft PR comments (confident only)` as `in_progress`.

For every finding with `Category: confident`, print a focused copy-paste block. **Smells are excluded entirely from this step** — they appeared in Step 3's report for your private read; they are not posted to the PR.

Group entries by `file:line` (sort alphabetically by file path, then ascending by starting line number). If the same `file:line` carries confident findings from two different dimensions, include both blocks, each prefixed with `(<dimension>)`.

Use this exact layout:

```
## Draft PR comments — PR #<N> (<PR_TITLE>)
Mode: draft-comments — copy-paste these into GitHub as line comments. Confident findings only; smells (see report above) are not drafted.

### `path/to/file:line-range`
<draft comment markdown verbatim from the finding's Draft comment: block>

### `path/to/other-file:42-48`
(<dimension>) <draft comment markdown>

(<dimension>) <draft comment markdown>
...
```

Special cases:
- Zero confident findings (only smells surfaced): print `> No confident findings to draft — the report above lists smells for your private review.` and continue.
- Zero total (from the zero-findings short-circuit): you are not in this step — Step 3 jumped you straight to Step 9.

Mark `🗒️ Print draft PR comments (confident only)` as `completed`, then jump to **Step 9**.

### Step 8: Update Ticket Context (`MODE=own` only — skip in draft-comments mode)

Mark `📝 Update ticket context` as `in_progress`.

If `MODE=draft-comments`, this step does not exist in the per-mode checklist — skip silently. Reviewing someone else's PR is not your ticket work; no audit entry is written.

If `TICKET_ID` is `null`, mark this step `completed` with note "No ticket ID — ticket context not updated" and continue.

Otherwise, launch a `general-purpose` sub-agent (`model: "haiku"`) to append a new session entry to `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md`. Pass it:

- **Session title:** `Review via /ds:review` (or `Review passed (no findings)` for the zero-findings path)
- **Branch name** (from `git branch --show-current`)
- **Repository name** (from `git remote get-url origin` or `gh repo view --json name`)
- **Accomplished:** one line — `<T> findings surfaced — <C> confident, <S> smells across 6 dimensions.` On the zero-findings path: `Review passed — no substantive findings across 6 dimensions.`
- **Key decisions:** notable smells worth offline follow-up — pull the 1–3 highest-severity / most significant smells from the report as bullets, each `<file:line> — <one-line summary>`. Omit the section entirely if there are no smells or none feels significant.
- **Files changed:** omit. This command does not modify the working tree.

The sub-agent should append a new section under `## Sessions` following the existing document template (see `~/dotfiles/claude/CLAUDE.md` "Ticket Context Documents" → Document Template). If the file does not exist, create it.

**Sub-agent allowed tools:** `Bash(git *), Read, Write, Edit`

Mark `📝 Update ticket context` as `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress`.

The summary format differs by mode.

**If `MODE=own`:**

```
/ds:review — PR #<N> (<title>)
Findings: <T> total — <C> confident, <S> smells — across 6 dimensions (H high, M medium, L low)
Ticket context updated: yes / no — <reason if no>
```

Suggest next steps:
- Engage with individual findings in chat (reference by `#N`) to discuss, dismiss, or act on them.
- Re-run `/ds:review` after addressing the major findings if more rounds are needed.
- Proceed to human review (mark PR ready with `gh pr ready` if it's a draft).

**If `MODE=draft-comments`:**

```
/ds:review (draft-comments mode) — PR #<N> (<title>)
PR author: <PR_AUTHOR>   You: <ME>
Findings: <T> total — <C> confident, <S> smells — across 6 dimensions (H high, M medium, L low)
Drafted as PR comments: <C> (confident only — smells excluded)
No changes were made to the branch, PR, or ticket context.
```

Suggest next steps:
- Copy the draft comments above into the GitHub PR review.
- Use the smells (above the draft section) as a private prompt list for offline discussion with the author.
- Re-run `/ds:review <pr-number>` after the author pushes updates.

Mark `✅ Final summary` as `completed`.

## Important Notes

- **Mode-aware flow**: the command auto-detects `own` vs `draft-comments` mode from PR author at Step 0.4. Both modes print the full categorized report; `own` additionally writes a ticket-context audit entry, `draft-comments` additionally prints copy-paste-ready draft comments for confident findings only.
- **No apply / commit / push**: this command surfaces findings only. It does not edit files, commit, or push. The user reads the report and acts on individual findings in follow-up chat as needed.
- **Render findings as text**: the report is printed as a regular text message. There is no selection prompt — the report is the deliverable.
- **Sub-agents are read-only**: analysis sub-agents have no `Edit`/`Write` in their allowed tools. The main agent never edits the working tree.
- **Fewer high-signal findings**: every sub-agent prompt instructs to skip borderline issues. The mandatory `Counter-argument` field is part of the bar — if writing it talks the reviewer out of the finding, the finding self-prunes.
- **Categorization is at capture**: each finding is `confident` or `smell` based on whether the proposed fix is concrete and whether the counter-argument is trivial. Smells are first-class; they need no proposed change (`(needs unpacking)` is acceptable).
- **Respect prior decisions**: the ticket-context summary in the shared brief is authoritative — sub-agents must not re-litigate.
- **Conventions compliance**: Step 1 discovers every `CLAUDE.md`/`AGENTS.md` applicable to the changed files (root + nested, ordered most-specific first); the Consistency reviewer checks the diff against their documented rules and cites the exact rule and its source file per violation. Purely mechanical formatting rules owned by `/ds:pre-review` are skipped to avoid overlap.
- **Always update ticket context** (when a ticket is detected in `MODE=own`) — including on the zero-findings path. The audit trail matters.
- **`/ds:review` is not `/ultrareview`**: this command is local-only, free, and agent-driven. Do not invoke or reference the cloud `/ultrareview`.
- **Parallel sub-agents**: launch all six reviewers in a single tool-use turn so they run concurrently. Do not chain them.
