---
description: Ten-dimensional review of the current PR — code quality plus reliability, operability, configuration and efficacy, with every finding tiered by user impact.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(find *), Read, Write, Edit, Grep, Glob, Task, TodoWrite, AskUserQuestion, mcp__linear-server__get_issue
argument-hint: [+comment] [<pr-number>] [--to <file>] [--bar low|medium|high]
---

You are performing a substantive review of a pull request. The goal is to absorb the mechanical reviewer effort on bigger PRs by surfacing the issues a thoughtful human reviewer would actually raise across ten dimensions: **simplicity, performance, codebase consistency, readability, extraction/duplication, test coverage, reliability, operability, configuration/capacity, and efficacy/claims**.

Every finding is categorized at capture time as either **confident** (concrete proposed change with a trivial/empty counter-argument) or **smell** (real trade-off surfaced by the counter-argument, or no concrete fix). Smells are first-class output — they don't need to come with a fix. Every finding also carries an **impact tier** — `user-facing`, `efficacy` or `maintenance` — which is what the report leads with, because that is the tier a merge decision turns on.

The command never touches the working tree — no edits, no commits, no pushes. It surfaces findings in chat for the user to read and act on selectively in follow-up prompts. The one thing it can write is the PR itself, and only behind the `+comment` flag. The mode-aware behavior:

- **`MODE=own`** (PR author == you): print the categorized report and write an audit entry to ticket context.
- **`MODE=draft-comments`** (PR author ≠ you): print the categorized report and additionally render copy-paste-ready `Draft comment:` blocks for **confident findings only**, grouped by `file:line`. Smells appear in the report for your private read but are not drafted as PR comments. No ticket-context writes.

**`+comment`** (either mode) posts the findings to the PR as one inline review instead of leaving you to copy-paste. The confident/smell split is the confidence signal: confident findings post behind a single batch confirmation, and each smell is triaged one-by-one with `AskUserQuestion` — the same in-the-loop posture `/ds:polish-pr` uses. So with the flag on, a smell *can* reach the PR; without it, the no-post default above still holds.

**`--bar low|medium|high`** (default `medium`) sets the **reporting bar** — how high a smell has to clear to be shown. A higher bar means fewer findings. Ten dimensions of first-class smells have a long tail of `maintenance`-tier, `low`-severity notes; the bar is what keeps that tail out of a report you have to read in one sitting.

| Bar | Smells shown |
|---|---|
| `low` | all of them |
| `medium` | drop smells that are `maintenance` tier **and** `low` severity |
| `high` | smells must be `user-facing` or `efficacy` tier — every `maintenance` smell drops |

**Confident findings are never filtered by the bar,** at any severity or tier: a concrete fix with a trivial counter-argument is high-signal by construction. The bar applies at report time, so every run captures the same findings and a re-run at `--bar low` reveals the held-back tail without re-analysing.

**Distinction from siblings:**
- `/ds:pre-review` — style/naming/conventions on the local diff, before push. Cosmetic.
- `/ds:polish-pr` — addresses *human* reviewer comments already posted on the PR.
- `/ds:review` — the six-dimension v1. Still the daily driver; this command is its trial successor.
- `/ds:review2` (this command) — v1's six dimensions plus the reliability & operations cluster, impact tiering, two reach fixes (the installed source of a changed dependency is in scope, and unchanged sibling files are inventoried so a file that *should* have changed can be found), and `+comment` to post the findings to the PR instead of leaving you to copy-paste them.

## Your Task

### Step 0: Detect PR & Gather Inputs

0. **Parse arguments.** `$ARGUMENTS` may contain an optional `+comment` flag, an optional PR number, an optional `--to <file>` flag and an optional `--bar <level>` flag, in any order:
   - `POST_COMMENTS` = `on` if the text contains `+comment`, else `off`. **Strip the `+comment` token before parsing anything else** — otherwise it is mistaken for the PR number. (The `+` prefix, as in `/ds:polish-pr`'s `+temp-worktree`, stops the Claude CLI consuming it as a CLI flag.)
   - `OUT_FILE` = the token following `--to` (the findings file to write findings into), else empty. When set, Step 3.6 appends the findings to it as shared-format item blocks.
   - `BAR` = the token following `--bar`, else `medium`. Accepts `low`, `medium`, `high`. Anything else is not fatal — print `> Unknown bar '<value>' — using medium.` and continue with `medium`.
   - `PR_ARG` = the first bare token that is **not** `--to` or `--bar`, and not the value of either, else empty. **Both flag values must be excluded**, or `/ds:review2 --bar high` reads `high` as the PR number.

   When `POST_COMMENTS=on`, print the flag line so the posting behaviour is visible before any analysis runs:
   > `+comment: on — confident findings post after one confirmation; smells are triaged one-by-one. Nothing reaches GitHub unconfirmed.`

   When `BAR` is not `low`, print the bar line too, so the filter is visible before any analysis runs rather than discovered in the report:
   > `--bar medium — maintenance·low smells are held back. Confident findings are never filtered.`

   (At `--bar high`: `--bar high — only user-facing and efficacy smells are shown. Confident findings are never filtered.`)

1. **Resolve the PR number.**
   - If `PR_ARG` is set, use PR **#`PR_ARG`**.
   - Otherwise auto-detect from the current branch:
   ```bash
   gh pr view --json number --jq '.number'
   ```
   - **If failed** (no PR for current branch): inform the user and stop:
     > No PR found for branch `<branch-name>`. Create one first with `/ds:create-pr` (or `gh pr create`), or pass the number directly: `/ds:review2 <pr-number>`.

2. **Extract ticket ID from branch name** (same pattern as `/ds:work-on`):
   - Run `git branch --show-current`
   - Strip everything before the first `/`, take the first two hyphen-separated segments, uppercase them (e.g., `feature/eng-123-foo` → `ENG-123`)
   - If the branch does not match the pattern, set `TICKET_ID=null` and continue without Linear / ticket-context lookups. This is NOT a fatal error.

3. **PR metadata** (author is needed for mode detection, base ref for the diff fetch):
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

**If `OUT_FILE` is set** (either mode): insert `📄 Write findings to <OUT_FILE>` immediately after `📋 Findings report`.

**If `POST_COMMENTS=on`** (either mode): insert these three after `📋 Findings report` — or after `📄 Write findings to <OUT_FILE>` when that item exists too:

1. `🎯 Anchor findings to diff lines`
2. `🙋 Triage smells (in-the-loop)`
3. `🚀 Preview & post review to PR`

In `MODE=draft-comments` with `POST_COMMENTS=on`, do **not** seed `🗒️ Print draft PR comments (confident only)` — the Step 3.9 preview supersedes it.

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
   - If none are found, note "no conventions files" and continue; the Consistency reviewer falls back to inferring conventions from neighbouring code.
   - In `MODE=draft-comments` the files are read from your current checkout — a fine proxy, since conventions rarely differ from the PR head. If the PR itself adds or edits a conventions file, account for that from the diff.
2. **Linear ticket** (only if `TICKET_ID` is set):
   ```
   mcp__linear-server__get_issue with id=TICKET_ID, includeRelations=true
   ```
   Capture title, description, acceptance criteria, status. **Keep the acceptance criteria verbatim** — the Efficacy reviewer walks them one at a time, so a paraphrase costs it the check.
3. **Ticket context file**: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` — read if it exists. Summarize previous-session decisions so the reviewers don't re-litigate settled questions.
4. **PR description** (already fetched in Step 0).
5. **The full diff** (already fetched in Step 0).
6. **Dependency source paths** — where the installed source of a dependency the diff relies on can actually be read. Several of the highest-value findings a reviewer makes turn on what a library *does*, not on what the calling code assumes about it; without a path, a sub-agent can only guess.
   - Scope it to dependencies the diff touches: a version bump in `pyproject.toml` / `package.json` / `*.csproj`, or an import the diff adds.
   - Resolve each, in order:
     1. **A local clone** — per `~/.claude/CLAUDE.md`, a DataSnipper package usually exists at `C:\work\github\{org}\{repo}`. Check `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` when the name is partial. This is the best source because it carries history.
     2. **The project's installed tree** — `.venv/lib/python*/site-packages/<pkg>`, `node_modules/<pkg>`, or the uv/npm cache.
   - A package resolving to a *different version* than the diff depends on is still useful, but say so: the sub-agents must know they are reading a neighbouring version, not the one under review.
   - Record `<package> <version-if-known> → <path>` for each. Anything unresolved is recorded as unresolved — that is information too, and it changes how a finding gets framed.
7. **Sibling-file inventory** — the unchanged files that the changed files sit beside. A file that *should* have changed and did not cannot be found in a diff, by definition; this inventory is the only thing that makes it reachable.
   - For each changed file, list the files in its directory sharing the same naming shape, and mark which are in the diff:
     ```bash
     git diff origin/<BASE>...HEAD --name-only | while read -r f; do
       printf '%s:\n' "$f"
       ls "$(dirname "$f")" | head -50
     done
     ```
   - Keep it where the shape is meaningful — per-environment config (`agentserver-*.tfvars`), per-provider adapters, per-entity migrations, a family of handlers. Skip directories where the neighbours are simply unrelated files, and skip any directory with a very large flat listing unless the changed file's name has an obvious family (a shared prefix or suffix).
   - Record each family as `<pattern>: <N> files, <M> in the diff — <the ones not in the diff>`.

Print a brief "Review context loaded" summary so the user sees what the reviewers will see:

```
Reviewing PR #<N>: <PR title>
Ticket: <TICKET_ID> — <ticket title>  (or "no ticket detected")
Base: origin/<base>
Diff: <files-changed> files, +<additions>/-<deletions>
Context file: loaded / not found / no ticket
Conventions: <N> files — <paths, most→least specific>  (or "none found")
Dependency sources: <pkg>@<version> → <path>, …  (or "none resolved" / "no dependency changes")
Sibling families: <pattern> <M>/<N> in diff, …  (or "none")
```

### Step 2: Launch Multi-Agent Analysis (parallel)

Mark `🔬 Analysis: launch review sub-agents` as `in_progress`.

Launch the ten reviewers below **in a single message with ten parallel `Task` tool calls**. Each call uses `subagent_type: "general-purpose"`. Apply the model tiering shown.

**Sub-agent allowed tools (all ten):** `Bash(git diff*), Bash(git log*), Bash(git show*), Bash(ls *), Bash(find *), Read, Grep, Glob`. NO Edit — sub-agents surface findings only; nothing in this command modifies the working tree.

#### Shared brief — prepend to every sub-agent prompt

> You are reviewing PR #<N> in the current repo. Below is the shared context. After absorbing it, focus only on your dimension (described after this brief).
>
> **PR title:** <title>
> **PR body:**
> <body>
>
> **Linear ticket:** <TICKET_ID> — <title>
> **Linear description / acceptance criteria (verbatim):**
> <description-and-acceptance-criteria>
>
> **Prior decisions from ticket-context file** (do NOT re-litigate these — respect them):
> <bulleted summary of decisions from previous sessions, or "no prior context">
>
> **Repo conventions files** (most-specific → least-specific — read any that bear on your dimension):
> <bulleted list of the discovered `CLAUDE.md` / `AGENTS.md` paths, or "none found">
>
> **Dependency sources** (readable installed source for the dependencies this diff relies on):
> <`<package>@<version> → <path>` per line, marking any that resolved to a different version than the diff depends on, or "none resolved">
>
> **Sibling families** (files beside the changed ones, and which are in the diff):
> <`<pattern>: <N> files, <M> in the diff — not in the diff: <names>` per line, or "none">
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
>    **Impact:** user-facing | efficacy | maintenance
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
> - **drop entirely** = if writing the counter-argument talks you out of the finding, do not include it. The exercise of writing the counter-argument is itself the test; weak findings self-prune here.
>
> **Impact criteria — set `Impact` per finding.** This is what the report is ordered by, so it decides whether a reader sees your finding first or last. It is independent of `Category` and of `Severity`: a smell can be `user-facing`, a confident finding can be `maintenance`.
> - **user-facing** = a user's request gets slower, an error reaches them, or the service's availability now depends on something it did not depend on before. Say how far the blast radius reaches — whether it lands only on the session that triggered it, or on every concurrent session sharing the process or replica.
> - **efficacy** = the change may not achieve the purpose it states, or something it claims — in a docstring, a comment, the PR body, the ticket — is not true of the code as written.
> - **maintenance** = everything else: hygiene, readability, duplication, future cost. The default when neither of the above applies. Most findings are this, and that is fine — do not inflate a finding's tier to get it read.
>
> **Rules of engagement:**
> - Return ONLY findings a thoughtful human reviewer would actually raise. If you have to reach for a finding, skip it. Fewer high-signal findings > many low-signal findings.
> - Every finding MUST have a non-empty `Counter-argument:` field. "none" is acceptable when the finding really has no real case against it (genuine no-brainer) — but the field must be present.
> - Every finding MUST have a `Code context:` block — a unified-diff fenced block showing ~5–10 lines of surrounding code with the change applied as `-`/`+` lines. For smells where `Proposed change:` is `(needs unpacking)`, include the unmodified code excerpt (no diff markers needed) so the reader sees the area in question.
> - **Reading the installed source of a dependency this diff relies on is in scope**, using the paths above. Do NOT assert a dependency's behaviour you have not read. If the source is unavailable, say so explicitly and frame the finding as a question that names precisely what would answer it — an honest question about an unread contract is a better finding than a confident guess.
> - Findings are not confined to the changed lines. A file that should have changed and did not, an unchanged caller the diff breaks, or a claim in an unchanged docstring the diff falsifies are all in scope — anchor them to a real `file:line` either way.
> - Do NOT propose changes that violate the ticket acceptance criteria or any prior decision listed above. If you believe an acceptance criterion is itself the problem, say so as a finding rather than quietly working around it.
> - You may use `git show`, `Grep`, and `Glob` to look at the surrounding code for context — but stay within your dimension's lane.

#### Draft-comment addendum (`MODE=draft-comments` **or** `POST_COMMENTS=on`)

Append the following to the shared brief **before** the per-dimension addendum whenever `MODE=draft-comments` **or** `POST_COMMENTS=on`. It extends the output contract so a finding ships with the PR comment already written, next to the reasoning that produced it.

**Which findings get a draft depends on the flag:**
- `POST_COMMENTS=off` (draft-comments mode alone): **confident findings only**. Smells stay reviewer-only.
- `POST_COMMENTS=on`: **every finding, confident and smell**. A smell's draft is written in question form and is not posted until you approve it one-by-one in Step 3.8.

Substitute the applicable scope into the brief below where it says `<drafting scope>`.

> **Additional output requirement:** for every finding within `<drafting scope>`, append a `**Draft comment:**` block immediately after `**Code context:**`.
>
> Updated per-finding shape:
>
> ```
> 1. `path/to/file:line-range` — <one-line summary>
>    **Severity:** high | medium | low
>    **Impact:** user-facing | efficacy | maintenance
>    **Category:** confident | smell
>    **Why:** <1–2 sentence reasoning>
>    **Counter-argument:** <strongest case against this finding; "none" if no real case exists>
>    **Proposed change:** <concrete, actionable description, OR "(needs unpacking)">
>    **Code context:**
>    ```diff
>    <~5–10 lines as unified diff>
>    ```
>    **Draft comment:**
>    > <GitHub-flavored markdown — see the shape and drafting rules below>
> ```
>
> **Comment shape — every draft uses these labels, in this order:**
>
> ```
> **Problem:** <one sentence>
> **Suggestion:** <the concrete change>
> **Alternatives:** <the other viable option(s)>      ← smells only; omit for confident findings
> ```
>
> The labels are not decoration: the author must be able to read the defect and the proposed change without inferring either from prose.
>
> **Drafting rules:**
> - Write from the reviewer's voice, addressing the PR author directly.
> - **Problem** is one sentence — no "I noticed that…" / "It seems like…" filler.
> - **For an `Impact: user-facing` finding, Problem names who is affected and how** — which users, in which situation, and how far it spreads beyond the one session. This is what separates a comment an author acts on from one they file as a nit.
> - **For an `Impact: efficacy` finding, Problem quotes the claim or acceptance criterion first**, then names the code that contradicts it.
> - **Suggestion** is actionable, not a vague concern.
> - 1–3 sentences per label. No restating of severity (that's reviewer mental model, not author-facing).
> - Avoid hedging adjectives ("maybe", "perhaps could possibly"); stay direct but collaborative.
> - Do NOT add an attribution footer to an individual comment — it appears once in the review body.
>
> **Confident findings** — assertion voice. **Problem** states the defect. Follow the labelled block with a fenced ` ```suggestion ` block **only** when the change is a single small edit GitHub can apply directly; never for a structural change. No `**Alternatives:**` line.
>
> **Smell findings** — question voice, because a smell is by definition a live trade-off:
> - **Problem** states the concern *as a question* the author is better placed to answer.
> - **Suggestion** names the option you lean toward.
> - **Alternatives** names the other viable option(s) — this line is what makes it a smell rather than a defect, so it is required.
> - Never a ` ```suggestion ` block: there is more than one viable answer, and GitHub's one-click apply would misrepresent that.
> - Where `Proposed change:` is `(needs unpacking)`, **Suggestion** says what would settle the question — the check to run, the source to read, the person to ask — instead of proposing a fix you cannot justify.
>
> Do NOT include the `**Draft comment:**` block on the `No issues found.` short-circuit.

#### Per-dimension prompt addendum

After the shared brief, append the dimension-specific instruction:

| Reviewer | Model | Addendum |
|---|---|---|
| **Simplicity** | opus (inherit — omit `model` field) | "Your dimension is **simplicity**. Could the same requirement be met with materially less code, fewer abstractions, or fewer moving parts? Flag: premature abstraction, over-parameterization, speculative generality, layers added for hypothetical futures, indirection that doesn't pay for itself. You may NOT propose changes that violate the ticket acceptance criteria." |
| **Performance** | opus (inherit) | "Your dimension is **performance and data-flow correctness**. Look for: wrong data structures (lists where dicts/sets fit, repeated linear scans), N+1 query patterns / inefficient DB access, missing `Include`/eager loading where it matters, unnecessary allocations on hot paths, repeated work that could be hoisted. Skip micro-optimizations a reviewer wouldn't raise. Concurrency stalls and event-loop blocking belong to the Reliability reviewer — leave those to it." |
| **Consistency** | sonnet | "Your dimension is **codebase consistency and conventions compliance** — two parts. **(1) Consistency:** compare patterns introduced by the diff against existing patterns for similar problems (use Grep/Glob to find neighbours). Flag: new patterns where an established one exists, inconsistent naming/structure compared with siblings. **(2) Conventions compliance:** read *in full* every conventions file listed in the shared brief (`CLAUDE.md` / `AGENTS.md`, root and nested). Extract each concrete, checkable rule, then verify the diff complies. A nested file's rule governs files beneath it and refines/overrides the root for those paths. Flag each violation with the **exact rule quoted and its source file cited** (e.g. `src/api/AGENTS.md`). Most rule violations are `confident` — a documented rule is an objective standard, so the counter-argument is usually 'none'; a violation with a legitimate, diff-specific justification becomes a `smell`. Skip purely mechanical formatting/whitespace rules that `/ds:pre-review` already enforces (avoid overlap) unless the diff plainly breaks them. If no conventions files were found, fall back to inferring conventions from neighbouring code." |
| **Readability** | sonnet | "Your dimension is **readability**. Is the intent of each non-trivial change obvious from the code alone? Flag: unclear names, missing-but-needed early returns, deeply nested conditionals, long functions doing multiple things, magic literals lacking a named constant. Do NOT suggest adding comments — prefer expressive code per repo conventions." |
| **Extraction/Duplication** | sonnet | "Your dimension is **extraction and duplication**. Use Grep to verify duplication is real (not just superficially similar). Flag: duplicated logic within the diff or between the diff and existing code, copy-paste blocks differing only in literals, extract-method candidates. Each finding must reference both/all duplicated sites." |
| **Test Coverage** | sonnet | "Your dimension is **test coverage**. For every non-trivial behavior change in the diff — new functions/methods with logic, new conditional branches, new error paths, new public APIs, modified business rules — check whether a test exercises it. Use Grep/Glob to (a) locate test files for the changed code (test-file naming conventions vary by repo: deduce from neighbours and `CLAUDE.md`), and (b) find tests for analogous existing code so you know what 'covered' looks like in *this* repo. Flag: new logic with no test, new conditional branch covered only on the happy path, modified behavior whose existing test was not updated, new public/exported surface without an integration test where the repo's convention requires one. **Weight by consequence, not by line count** — the statement whose failure takes the service down deserves a test far more than a branch in a formatter, so say what an untested path costs when it breaks. **Also judge whether a test that exists can fail for the reason it exists**: a test that mocks the very dependency whose real contract is the risk, an assertion that also holds on empty output, a test proving only that a *different* exception wasn't raised. Where a test's subject is a dependency's behaviour rather than this code's contract, say so — the repo conventions forbid re-verifying a dependency. Skip: trivial getters/setters, pure renames, comment/doc-only changes, formatting, generated code, infra/YAML/config, and anything in directories the repo's existing tests do not cover (deduce). Respect the repo's testing posture — if `CLAUDE.md` or neighbour evidence says 'no tests for X', do not invent a requirement. Reference both the diff location and the expected test location (or analogue) in every finding." |
| **Reliability** | opus (inherit) | "Your dimension is **reliability and failure modes**. For every new or changed call the diff introduces, ask what happens when it is slow, unreachable, or returns something the code does not expect — and **who pays**. Flag: (a) an await on a non-essential subsystem with no timeout and no `except`, where a fault there takes down something that should outlive it — startup lifecycle, request handling, shutdown; compare against how the neighbouring subsystems in the same function handle the same risk. (b) An exception that can escape a callback, hook, or background task that nothing supervises — name what stops working for the remaining life of the process when it dies, and whether anything would make that visible. (c) An `async def` body with no `await` on a path that can loop, or synchronous work (logging, serialization, CPU, blocking I/O) long enough to stall the event loop; when a timeout is configured around such a body, say plainly that it cannot fire, because a timeout that cannot preempt is worse than none — it reads as a bound that isn't there. (d) A lock, or app-scoped/process-scoped state, that turns one session's fault into every concurrent session's fault — state the blast radius explicitly rather than leaving it implied. (e) Shutdown ordering: whether a drain, flush, or close step can be skipped because an earlier step raised, and whether its timeout fits inside the platform's own grace period. (f) A failure class the change *introduces* that the old code did not have — buffering, caching, batching and retrying all trade one failure mode for another, so name the new one. Read the dependency sources in the brief rather than assuming a library's failure behaviour. The test is a fault that is plausible in production, not any theoretical one — do not propose defensive handling nobody would add." |
| **Operability** | sonnet | "Your dimension is **operability** — whether the person on call, who did not write this code, can see what it does when it goes wrong. Flag: (a) a failure path the change introduces or moves that nothing counts, logs, or traces — including the case where the *detector itself* fails silently and its silence is indistinguishable from healthy quiet. (b) An instrument whose claimed coverage is wider than its real coverage: read every path that reaches it and name the ones that do not — a dependency that logs-and-returns instead of raising is the usual culprit, and the claim is usually in a docstring or the PR body. (c) A label on a metric that is not also a structured field on the log record for the same event: an operator alerting on the metric cannot pivot to the logs on that dimension. Check every failure path carries the same field shape — a field present on one path and absent on its sibling is a finding, because a filter that works for one silently misses the other. (d) Log volume and cost under **sustained fault**, not steady state: one record per event for the length of an outage window, a traceback formatted inline on a request path, a multi-line dump per call. (e) A log message whose wording steers an operator to the wrong cause — most often a message hardcoded to one failure mode inside an `except` that catches several. (f) An existing alert, dashboard, or saved query this change silently invalidates: the old signal stops appearing and the change looks like a success either way. Grep for message text the diff moves or removes. Every finding must name the operational question that cannot be answered without the change you propose — do NOT propose telemetry for its own sake." |
| **Configuration & Capacity** | sonnet | "Your dimension is **configuration and capacity**. Flag: (a) a tuned value with no stated reasoning anywhere — the diff, PR body, or ticket must say why *this* number; and any deviation from a library or platform default must be explained, in both directions (raising and lowering). (b) A value whose consequence is not worked out: what throughput, memory footprint, or latency does it imply, and does this system's actual traffic shape fit inside it? Do the arithmetic and show it in the finding. (c) A timeout or budget that does not fit inside the platform's own budget — container termination grace period, server shutdown window, upstream deadline; an unhonourable timeout is a false promise. (d) Back-pressure left unspecified: when the bounded thing is full, does the caller reject immediately or wait, and for how long? Read the dependency source from the brief rather than inferring it from an error message's wording. (e) **Cross-environment drift** — the brief lists each changed file's sibling family. A sibling that carries the same block and was not updated is a finding: say what it runs on instead, and when that first bites someone. This check must look outside the diff, and it is the one thing no other reviewer can do. (f) A version constraint that admits a behaviour change with no code change — a range where the diff depends on semantics that only a pin protects. Skip values that are obviously conventional for the ecosystem and unchanged by the diff." |
| **Efficacy & Claims** | opus (inherit) | "Your dimension is **efficacy and claims** — does the change do what it says, and is what it says true? You are the only reviewer whose lane is the gap between stated intent and code, so do not drift into code quality. Flag: (a) the fix relabels or relocates the failure rather than removing it. Trace the root cause the ticket names through the new code and say whether the same trigger still produces the same loss under a different name. Where you cannot tell without the dependency's source, read it (paths in the brief); where you still cannot tell, raise it as a question and say precisely what would answer it. (b) A claim in a docstring, code comment, PR body, or commit message the code does not support — quote the claim, then name the path that breaks it. (c) An acceptance criterion the diff does not meet, **including one met only partly** — a rule applied to six of nine files, a counter that observes three of four paths, a bound set on one caller and not its sibling. Walk the acceptance-criteria list explicitly, one at a time, and say for each whether it is met, partly met, or unmet. (d) A new risk the change introduces that is written down nowhere — a loss class, a latency class, a new dependency. If the change is a trade rather than a win, that trade belongs in the PR body; say so. (e) A claim you cannot verify at all, and exactly what it would take to verify it. Every finding must be anchored: quote the claim or the acceptance-criterion line, then name the code that contradicts it. A vague 'this might not work' is not a finding." |

Mark `🔬 Analysis: launch review sub-agents` as `completed` after all ten sub-agents return.

### Step 3: Aggregate & Present Findings

Mark `📋 Findings report` as `in_progress`.

1. Parse each sub-agent's structured findings block.

2. **Apply the bar** — partition the parsed findings into `shown` and `held back`, per `BAR`:
   - `low` — nothing is held back.
   - `medium` — hold back each **smell** whose `Impact` is `maintenance` **and** whose `Severity` is `low`. Both conditions must hold: a `maintenance` · `medium` smell is shown, and so is a `user-facing` · `low` smell.
   - `high` — hold back every **smell** whose `Impact` is `maintenance`, at any severity.

   **Findings with `Category: confident` are never held back**, whatever their impact or severity. Record the held-back count as `HELD`; you need it for the footer, Step 8 and Step 9, but the findings themselves play no further part in this run.

3. **Assign a flat 1..N id across the shown findings only**, in dimension order (the order of the table above), so every finding can be referenced unambiguously in follow-up chat. Numbering is contiguous — do not leave gaps where a finding was held back, because a gap at `#4` invites a question about a finding that is not in the report to answer it from.

4. **Print the aggregated report as a regular text message** before calling any other tool. The user can ONLY see your text output — they cannot see sub-agent return values.

   The report leads with the impact summary, because that is the tier a merge decision turns on and the detail below it is long. Then the per-dimension body, each dimension split into **Confident** then **Smells**.

   ```
   ## /ds:review2 findings — PR #<N> (<title>) · bar: <BAR>

   ### Impact summary

   **User-facing** (<N>) — regresses a request, an error reaches a user, or availability now depends on this
   - #3 `path/to/file:line` — <summary>   (Reliability · high · confident)
   - #7 `path/to/file:line` — <summary>   (Performance · medium · smell)

   **Efficacy** (<N>) — may not achieve its stated purpose, or claims something the code does not support
   - #11 `path/to/file:line` — <summary>   (Efficacy & Claims · high · confident)

   **Maintenance** (<N>) — hygiene, readability, duplication, future cost
   - #1 `path/to/file:line` — <summary>   (Simplicity · low · smell)
   - …

   ---

   ### Simplicity
   **Confident** (M findings)
   1. `path/to/file:line-range` — <summary> (severity · impact)
      Why: ...
      Counter-argument: ...
      Proposed: ...
      Code context:
      ```diff
      ...
      ```

   **Smells** (K findings)
   2. `path/to/file:line-range` — <summary> (severity · impact)
      Why: ...
      Counter-argument: ...
      Proposed: (needs unpacking) or <description>
      Code context:
      ```diff
      ...
      ```

   ### Performance
   ...
   ### Consistency
   ...
   ### Readability
   ...
   ### Extraction/Duplication
   ...
   ### Test Coverage
   ...
   ### Reliability
   ...
   ### Operability
   ...
   ### Configuration & Capacity
   ...
   ### Efficacy & Claims
   ...

   **Totals:** <T> shown — <C> confident, <S> smells — across 10 dimensions (H high, M medium, L low).
   > Bar: <BAR> — <HELD> smells held back. Re-run with `--bar low` to see them.
   ```

   Omit the `Bar:` footer line entirely when `HELD` is 0 — which is always the case at `--bar low`. Everything the report counts is a *shown* finding; held-back smells appear nowhere in the impact summary or the per-dimension body, only in that one footer number.

   Within each impact tier, order by severity (high → low). Omit an impact tier's heading entirely when it has no findings. Omit the **Confident** or **Smells** subsection header for any dimension where that subsection is empty, and omit a dimension's `###` heading entirely when it returned no findings — a ten-dimension report with four empty sections is harder to read than a six-section one.

5. **Nothing-to-show short-circuit:** if the shown count == 0, print one of two lines — which one depends on whether the reviewers found nothing or the bar hid everything they found. Do not print the first when the second is true; "review passed" is a false claim about a PR whose only findings were filtered out.
   - **Nothing was captured** (shown == 0 **and** `HELD` == 0):
     > **Review passed — no substantive findings.**
   - **Everything captured was held back** (shown == 0 **and** `HELD` > 0):
     > **No findings at bar `<BAR>`** — <HELD> smells held back, no confident findings. Re-run with `--bar low` to see them.

   Either way, the rest of the run is the same:
   - If `OUT_FILE` is set, also print `> OUT_FILE: nothing written (nothing to show).` — no item blocks are added (Step 3.6 is skipped).
   - If `POST_COMMENTS=on`, also print `> +comment: nothing to post.` — Steps 3.7–3.9 are skipped.
   - **If `MODE=own`:** proceed to Step 8 (ticket context gets a session entry naming which of the two cases it was), then Step 9.
   - **If `MODE=draft-comments`:** skip directly to Step 9 (final summary).

Mark `📋 Findings report` as `completed`.

### Step 3.6: Write Findings to File (`OUT_FILE` set only)

Runs in **both** modes, before the mode branch. If `OUT_FILE` is empty, skip this step. (On the nothing-to-show short-circuit above you won't reach this step — nothing is written.)

Mark `📄 Write findings to <OUT_FILE>` as `in_progress`.

Append the findings to `OUT_FILE` as shared-format item blocks so `/ds:polish <OUT_FILE>` can act on them later. The format is owned by `/ds:polish` (see that command for the full spec); the **writer slice** is:

**Only the shown findings are written.** A smell held back by the bar does not reach the findings file — a finding you never read turning up in your `/ds:polish` queue is the same noise, just moved downstream. To capture the held-back tail in a file, re-run with `--bar low --to <file>`.

1. **File shape:**
   - If `OUT_FILE` does not exist, create it with a skeleton — title, an empty Inbox, then the `---` that separates Inbox from thread:
     ```
     # Findings — <PR_TITLE> (PR #<N>)
     <!-- shared findings file · written by /ds:review2 & /ds:analyze-pr · triaged by /ds:polish -->

     ## Inbox
     <!-- your questions/notes; only this zone is read by /ds:analyze-pr -->

     ---
     ```
   - If it exists, append below its existing content (the thread zone lives below the first `---`).
2. **Next id:** scan the file for `### F<n> · ` headings; `next = max(n) + 1` (start at `F1` if none). Continue the same counter across findings so review + analyze-pr never collide.
3. **One item block per finding**, under a `## /ds:review2 — <YYYY-MM-DD>` group heading. Map each finding's existing fields:
   - heading → `### F<next++> · review:<dimension> · <category>` — `<dimension>` ∈ simplicity | performance | consistency | readability | extraction | test-coverage | reliability | operability | configuration | efficacy; `<category>` = the finding's `confident`/`smell`
   - `- **Status:** open`
   - `- **Item:**` ← the finding's one-line summary
   - `- **Impact:**` ← the finding's `Impact`
   - `- **Location:**` ← the finding's `file:line` (omit the line if absent)
   - `- **Detail:**` ← the finding's `Why`
   - `- **Counter-argument:**` ← the finding's `Counter-argument`
   - `- **Proposed change:**` ← the finding's `Proposed change` (keep `(needs unpacking)` for smells)
   - `- **Resolution:** —`
   - then the finding's `Code context:` fenced block verbatim
4. **Write:** `Read` the current file, append the new group (plus the skeleton if newly created), `Write` it back — preserving existing content verbatim (Read+Write, not Edit; robust on multi-line markdown).
5. Print: `> Wrote <T> findings to <OUT_FILE> (ids F<a>–F<b>). Run /ds:polish <OUT_FILE> to act on them.`

Mark `📄 Write findings to <OUT_FILE>` as `completed`.

### Step 3.7: Anchor Findings to Diff Lines (`POST_COMMENTS=on` only)

Runs in **both** modes. If `POST_COMMENTS=off`, skip Steps 3.7–3.9 entirely. On the nothing-to-show short-circuit you never reach this step — print `> +comment: nothing to post.` there instead.

Mark `🎯 Anchor findings to diff lines` as `in_progress`.

GitHub accepts an inline review comment only on a line inside a diff hunk, and this command's brief explicitly puts findings *outside* the changed lines in scope. So before anything is posted, every finding is routed to one of two destinations.

1. **Head SHA:**
   ```bash
   gh pr view <pr-number> --json headRefOid --jq '.headRefOid'   # HEAD_SHA
   ```

2. **Unpushed-commit guard (`MODE=own` only).** In `MODE=own` the report was built from the local working tree, but GitHub anchors comments against the *pushed* head. Compare:
   ```bash
   git rev-parse HEAD
   ```
   If it differs from `HEAD_SHA`, the local diff's line numbers do not describe the PR — every anchor would be wrong, or worse, land on unrelated code. Stop here:
   > Local HEAD (`<sha>`) differs from the PR head (`<HEAD_SHA>`). Push first, then re-run with `+comment` — comment anchors are computed against the pushed diff.

   The report above and any `--to <file>` output are already written and stay valid. Skip Steps 3.7–3.9, mark their todos not applicable, and continue to the mode branch.

3. **Build the commentable-line set** from the PR's own diff — `gh pr diff <pr-number>`, **not** the local `git diff`, so both modes anchor against exactly what GitHub will accept. For each file, parse the hunk headers `@@ -a,b +c,d @@`; the RIGHT-side lines `c` through `c+d-1` are commentable (added and context lines both count).

4. **Route each finding** by its `file:line-range`:
   - Range end inside the set → `INLINE`, with `side: RIGHT` and `line` = the range end. Add `start_line` and `start_side: RIGHT` when the range start falls in the **same hunk**; when it doesn't, collapse to the single end line rather than spanning hunks.
   - Otherwise → `BODY`. This is the expected home for an unchanged caller the diff breaks, a docstring the diff falsifies, or a sibling file that should have changed — findings no diff-anchored comment can reach.

5. **Dedup guard.** A re-run after a push must not duplicate the review:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<pr-number>/comments --paginate \
     --jq '.[] | select(.user.login=="<ME>") | "\(.path):\(.line)"'
   ```
   Mark any finding whose `path:line` already carries a comment of yours as `already-posted` and drop it from the payload. Count them; they are reported, not silently discarded.

6. Print: `> Anchoring: <I> inline, <B> into review body, <D> skipped as already posted.`

Mark `🎯 Anchor findings to diff lines` as `completed`.

### Step 3.8: Triage Smells In-the-Loop (`POST_COMMENTS=on` only)

Mark `🙋 Triage smells (in-the-loop)` as `in_progress`.

A confident finding has a concrete fix and a trivial counter-argument, so it needs no per-item decision — it goes straight to the Step 3.9 preview. A smell is the opposite: a live trade-off, or a problem with no obvious fix. Those get your judgement one at a time, on the same pattern as `/ds:polish-pr` Step 5.

Only the **shown** smells reach this loop. A smell held back by the bar is never triaged and never posted — posting a comment the user did not read would be worse than the noise the bar exists to remove.

If there are no smells, print `> No smells to triage.` and continue.

**a. Scope guard first.** Ten dimensions can surface a lot of smells, and one `AskUserQuestion` each would be an interrogation. If the smell count is **greater than 8**, ask once via `AskUserQuestion` before the loop:
- **Review all `<N>`** — every smell gets a decision
- **Only `user-facing` + `efficacy`** — the tiers a merge turns on; the rest stay in the chat report
- **Let me pick** — you name the finding ids to triage
- **Post no smells** — skip the loop; confident findings still post

Anything out of scope is recorded as `not posted (deferred)` and stays in the chat report only.

**b. Then one at a time.** For each in-scope smell, print:
- its flat report id, `file:line`, and one-line summary
- `Why`, `Counter-argument`, `Proposed change`
- its `Code context:` block
- the drafted comment body verbatim, so you approve the exact words that will be posted
- its destination: `inline at <path>:<line>` or `review body (not anchorable to the diff)`

Then `AskUserQuestion`:
- **Post as drafted** — add to the payload
- **Post all remaining smells in this dimension** — batch escape hatch, so a long tail of same-dimension smells can't turn into ten prompts
- **Modify wording** — you give the angle, redraft it, show the new body, and confirm once before adding
- **Don't post** — stays in the chat report only

Wait for each decision before showing the next smell. Confident findings never enter this loop.

**c. Print the tally:** `> Smells: <A> approved for posting, <D> declined, <F> deferred out of scope.`

The bar does upstream what this scope guard does downstream, so at the default bar the guard fires far less often than it did before the bar existed. It stays as a second net — a PR can still surface more than eight `medium`-severity smells that all clear the bar.

Mark `🙋 Triage smells (in-the-loop)` as `completed`.

### Step 3.9: Preview, Confirm, Post (`POST_COMMENTS=on` only)

Mark `🚀 Preview & post review to PR` as `in_progress`.

**a. Assemble the review body.** In order:
1. One line naming the source — "Automated ten-dimension review via `/ds:review2`."
2. `Posted: <U> user-facing, <E> efficacy, <M> maintenance.`
3. `### Findings outside the diff` — every `BODY` finding as `` `file:line` `` followed by its Problem/Suggestion (and Alternatives) block. Omit this heading entirely when there are none.
4. `🤖 Generated with [Claude Code](https://claude.ai/claude-code)` — **once, here only.** Never on an individual comment.

**b. Preview.** Print the payload exactly as it will appear on GitHub: the review body, then each inline comment under a `path:line (side)` header. Order by impact tier — `user-facing`, then `efficacy`, then `maintenance` — and within a tier by `path` then ascending `line`, so the author reads what blocks a merge first. Close with the counts:

```
<C> confident inline, <S> approved smells inline, <B> in review body.
```

**c. Gate.** One `AskUserQuestion`:
- **Post review** — post everything previewed
- **Post inline only** — drop the `Findings outside the diff` section, keep the inline comments
- **Cancel** — post nothing

On **Cancel**, print `> Cancelled — nothing posted to the PR.` and continue to the mode branch. The report stands as the deliverable.

**d. Post.** Write the payload to a JSON file under the session scratchpad, then submit it as one review:
```bash
gh api --method POST repos/{owner}/{repo}/pulls/<pr-number>/reviews --input <payload.json>
```
Payload shape:
```json
{
  "commit_id": "<HEAD_SHA>",
  "body": "<review body>",
  "event": "COMMENT",
  "comments": [
    {"path": "src/a.py", "line": 42, "side": "RIGHT", "body": "..."},
    {"path": "src/b.py", "start_line": 10, "start_side": "RIGHT", "line": 14, "side": "RIGHT", "body": "..."}
  ]
}
```
- `event` is **always `COMMENT`**. `APPROVE` and `REQUEST_CHANGES` are rejected on your own PR, and this command is not a merge gate in either mode.
- One batched review is one notification and one reviewable unit — that is why it is preferred over posting each comment standalone.

**e. Failure handling.** The batch POST is atomic: a single unacceptable anchor returns 422 and nothing lands. On a 422 naming a line or path, do **not** guess which comment offended. Fall back to two passes:
1. Post the review body alone, with `"comments": []`.
2. Post each inline comment individually, one JSON file per comment so the body needs no shell escaping and `line` stays an integer:
   ```bash
   gh api --method POST repos/{owner}/{repo}/pulls/<pr-number>/comments --input <one-comment.json>
   ```
   ```json
   {"commit_id": "<HEAD_SHA>", "path": "src/a.py", "line": 42, "side": "RIGHT", "body": "..."}
   ```
   Each failure is then isolated. Report which comments landed and which did not, naming the ones that failed and why. No retry loops.

On success, print the review URL from the response's `html_url`.

Mark `🚀 Preview & post review to PR` as `completed`.

### Mode branch

- **If `MODE=own`:** proceed to **Step 8** (Update Ticket Context).
- **If `MODE=draft-comments`:**
  - `POST_COMMENTS=off` → proceed to **Step 3.5** (Print Draft PR Comments), then **Step 9**.
  - `POST_COMMENTS=on` → **skip Step 3.5** and go straight to **Step 9**. The Step 3.9 preview already showed every comment and they are posted; a copy-paste block would be dead weight.

### Step 3.5: Print Draft PR Comments (`MODE=draft-comments` and `POST_COMMENTS=off` only)

Skip this step when `POST_COMMENTS=on` — Step 3.9 both previewed and posted the comments.

Mark `🗒️ Print draft PR comments (confident only)` as `in_progress`.

For every finding with `Category: confident`, print a focused copy-paste block. **Smells are excluded entirely from this step** — they appeared in Step 3's report for your private read; they are not posted to the PR.

Order the blocks by impact tier — `user-facing`, then `efficacy`, then `maintenance` — and within a tier by `file:line` (alphabetically by path, then ascending by starting line). Posting in that order means the author reads the items that block a merge first. If the same `file:line` carries confident findings from two different dimensions, include both blocks, each prefixed with `(<dimension>)`.

Use this exact layout:

```
## Draft PR comments — PR #<N> (<PR_TITLE>)
Mode: draft-comments — copy-paste these into GitHub as line comments. Confident findings only; smells (see report above) are not drafted.

### User-facing

#### `path/to/file:line-range`
<draft comment markdown verbatim from the finding's Draft comment: block>

### Efficacy

#### `path/to/other-file:42-48`
(<dimension>) <draft comment markdown>

### Maintenance

#### `path/to/third-file:10`
<draft comment markdown>
...
```

Omit any tier heading that has no confident findings.

Special cases:
- Zero confident findings (only smells surfaced): print `> No confident findings to draft — the report above lists smells for your private review.` and continue.
- Zero shown (from the nothing-to-show short-circuit): you are not in this step — Step 3 jumped you straight to Step 9.

Mark `🗒️ Print draft PR comments (confident only)` as `completed`, then jump to **Step 9**.

### Step 8: Update Ticket Context (`MODE=own` only — skip in draft-comments mode)

Mark `📝 Update ticket context` as `in_progress`.

If `MODE=draft-comments`, this step does not exist in the per-mode checklist — skip silently. Reviewing someone else's PR is not your ticket work; no audit entry is written.

If `TICKET_ID` is `null`, mark this step `completed` with note "No ticket ID — ticket context not updated" and continue.

Otherwise, launch a `general-purpose` sub-agent (`model: "haiku"`) to append a new session entry to `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md`. Pass it:

- **Session title:** `Review via /ds:review2` (or `Review passed (no findings)` when nothing was captured at all)
- **Branch name** (from `git branch --show-current`)
- **Repository name** (from `git remote get-url origin` or `gh repo view --json name`)
- **Accomplished:** one line — `<T> findings surfaced — <C> confident, <S> smells across 10 dimensions; <U> user-facing, <E> efficacy.` When nothing was captured: `Review passed — no substantive findings across 10 dimensions.` When `+comment` posted, append `; <P> posted to the PR (<C2> confident, <S2> approved smells)` — the next session needs to know which findings are already public.
- **Bar:** when `HELD` > 0, append `; reviewed at bar <BAR>, <HELD> smells held back` to the `Accomplished:` line. This is the **only** place a held-back finding is recorded, so a later session reading the audit trail is not misled into treating the review as exhaustive.
- **Key decisions:** the findings worth carrying into the next session — take every `user-facing` and `efficacy` finding first (those change what merges), then fill up to 3–5 bullets with the most significant `maintenance` smells. Each bullet `<file:line> — <one-line summary>`. Omit the section entirely if nothing qualifies. Held-back findings are not eligible; the count on the `Accomplished:` line is all that records them.
- **Files changed:** omit. This command does not modify the working tree.

The sub-agent should append a new section under `## Sessions` following the existing document template (see `~/.claude/CLAUDE.md` "Ticket Context Documents" → Document Template). If the file does not exist, create it.

**Sub-agent allowed tools:** `Bash(git *), Read, Write, Edit`

Mark `📝 Update ticket context` as `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress`.

The summary format differs by mode.

**If `MODE=own`:**

```
/ds:review2 — PR #<N> (<title>)
Findings: <T> shown — <C> confident, <S> smells — across 10 dimensions (H high, M medium, L low)
Bar: <BAR> — <HELD> smells held back
Impact: <U> user-facing, <E> efficacy, <M> maintenance
Posted to PR: <P> comments (<I> inline, <B> in review body) — <review-url>
Ticket context updated: yes / no — <reason if no>
```

Include the `Bar:` line only when `HELD` > 0. Include the `Posted to PR:` line only when `POST_COMMENTS=on`. When nothing was posted, say why in place of the counts: `none (cancelled)`, `none (nothing eligible)`, or `none (local HEAD differs from PR head — push and re-run)`.

Suggest next steps:
- Address the user-facing and efficacy findings before asking for human review — those are the two tiers a reviewer blocks on.
- Re-run at `--bar low` to read the <HELD> held-back smells. *(Include this line only when `HELD` > 0.)*
- Engage with individual findings in chat (reference by `#N`) to discuss, dismiss, or act on them.
- Re-run `/ds:review2` after addressing the major findings if more rounds are needed.
- Re-run with `+comment` to post the findings you want on the record for your reviewers — the dedup guard keeps a second run from duplicating anything already posted. *(Skip this line when `POST_COMMENTS=on` already ran.)*
- Proceed to human review (mark PR ready with `gh pr ready` if it's a draft).

**If `MODE=draft-comments`:**

```
/ds:review2 (draft-comments mode) — PR #<N> (<title>)
PR author: <PR_AUTHOR>   You: <ME>
Findings: <T> shown — <C> confident, <S> smells — across 10 dimensions (H high, M medium, L low)
Bar: <BAR> — <HELD> smells held back
Impact: <U> user-facing, <E> efficacy, <M> maintenance
Drafted as PR comments: <C> (confident only — smells excluded)
No changes were made to the branch, PR, or ticket context.
```

Include the `Bar:` line only when `HELD` > 0.

**When `POST_COMMENTS=on`,** replace the last two lines — the "no changes" claim is false once comments are posted:

```
Posted to PR: <P> comments (<I> inline, <B> in review body) — <review-url>
No changes were made to the branch or ticket context.
```

Suggest next steps:
- Copy the draft comments above into the GitHub PR review, user-facing tier first. *(`POST_COMMENTS=on`: they are already posted — check the review URL renders as intended.)*
- Use the smells (above the draft section) as a private prompt list for offline discussion with the author. *(`POST_COMMENTS=on`: only the smells you declined remain private.)*
- Re-run at `--bar low` to read the <HELD> held-back smells before that discussion. *(Include this line only when `HELD` > 0.)*
- Re-run `/ds:review2 <pr-number>` after the author pushes updates. With `+comment`, the dedup guard means a re-run adds only what is new.

Mark `✅ Final summary` as `completed`.

## Important Notes

- **Relationship to `/ds:review`**: this is the trial v2. It keeps every v1 behaviour — mode detection, the mandatory `Counter-argument`, the confident/smell split, `--to <file>`, the ticket-context audit — and adds four dimensions, the impact tier, two reach fixes, and `+comment`. `/ds:review` stays in place as the daily driver until v2 is trusted, and does **not** get `+comment` — the flag is part of what v2 is trialling.
- **Mode-aware flow**: the command auto-detects `own` vs `draft-comments` mode from PR author at Step 0.4. Both modes print the categorized report; `own` additionally writes a ticket-context audit entry, `draft-comments` additionally prints copy-paste-ready draft comments for confident findings only. `+comment` is orthogonal to the mode — it works in both, and in `draft-comments` it replaces the copy-paste block with a posted review.
- **Never touches the working tree**: this command does not edit files, commit, or push, in any mode, with or without `+comment`. The user reads the report and acts on individual findings in follow-up chat as needed. The single outward write it can make is posting comments to the PR, and only under `+comment`.
- **`+comment` semantics**: the confident/smell split *is* the confidence signal, so no new judgement is invented for posting. A **confident** finding — concrete fix, trivial counter-argument — posts behind one batch confirmation. A **smell** — real trade-off, or no concrete fix — gets a per-finding `AskUserQuestion` in Step 3.8, and posts only if you approve it, in question form with its alternatives named. This is the one thing that overrides the default that smells are never posted. All three impact tiers are eligible; `maintenance` is not filtered out.
- **`--bar` semantics**: the bar filters **smells only** — `low` shows all of them, `medium` (the default) holds back `maintenance` · `low` smells, `high` holds back every `maintenance` smell. Confident findings are never filtered, because a concrete fix with a trivial counter-argument is high-signal at any severity. The bar acts at **report time**, not in the sub-agent brief, so every run captures the same findings and re-running at `--bar low` reveals the held-back tail without re-analysing. `--to <file>` and `+comment` both respect it — a finding the user never read must not reach their `/ds:polish` queue or the PR — and the ticket-context entry is the one place that records what it hid.
- **`--bar` runs the opposite way to `/code-review`'s `level`**: in the built-in `/code-review` skill, a *higher* level means *broader* coverage and *more* findings. Here a *higher* bar means *fewer*. That is why this flag is called a bar and not a level: the word would import the wrong direction from the neighbouring command. Do not "fix" the direction to match.
- **Nothing reaches GitHub unconfirmed**: Step 3.9 previews the exact review body and every inline comment, then gates on a single `AskUserQuestion` with a Cancel option. Confident findings need no per-item approval, but they do not bypass that gate.
- **`event` is always `COMMENT`**: `APPROVE` and `REQUEST_CHANGES` are rejected by GitHub on your own PR, and this command is not a merge gate on anyone else's. It posts observations, never a verdict.
- **Inline comments can only anchor inside a diff hunk**, but this command's brief deliberately puts findings outside the changed lines in scope. Step 3.7 routes each finding accordingly: anchorable ones become inline comments, the rest fold into the review body under `Findings outside the diff`. Nothing is dropped for being unanchorable. The batched review POST is atomic, so one bad anchor 422s the whole thing — the fallback posts the body alone, then each comment individually, and reports which landed.
- **`+comment` in `MODE=own` requires a pushed head**: the `own`-mode report is built from the local working tree, but GitHub anchors comments against the pushed head. Step 3.7 compares `git rev-parse HEAD` to the PR's `headRefOid` and refuses to post when they differ, because every anchor would be off. The report itself is still valid and still printed.
- **A re-run is safe**: Step 3.7's dedup guard drops any finding whose `path:line` already carries a comment of yours, so running `+comment` again after the author pushes adds only what is new instead of duplicating the review.
- **Attribution once**: the `🤖 Generated with Claude Code` line goes in the review body only. Repeating it on twelve inline comments is noise.
- **Impact tiering**: every finding carries `user-facing`, `efficacy` or `maintenance`, and the report leads with a tiered summary so the merge-relevant findings are read first. The tier is independent of both severity and category — a smell can be user-facing, a confident finding can be maintenance. Most findings are `maintenance`; that is the honest default, and reviewers are told not to inflate a tier to get read.
- **Dependency source is in scope**: Step 1.6 resolves where a changed dependency's installed source can be read (local clone first, then the project's installed tree), and the shared brief forbids asserting a dependency's behaviour that was not read. Where the source is unavailable, a reviewer must frame the finding as a question naming what would answer it. This is what lets a reviewer check a library's real contract instead of trusting the calling code's assumption about it.
- **Sibling inventory finds what the diff cannot show**: Step 1.7 lists the unchanged files beside each changed one. A per-environment config updated in six of nine files, a provider adapter family missing one member, a migration without its pair — none of these appear in a diff, so nothing else can reach them. The Configuration & Capacity reviewer owns the check.
- **Findings are not confined to changed lines**: the shared brief says so explicitly, so an unchanged caller the diff breaks, or an unchanged docstring the diff falsifies, is fair game — anchored to a real `file:line` either way.
- **Findings-file output (`--to <file>`)**: when `--to <file>` is passed, Step 3.6 *additionally* appends the findings to that file as shared-format item blocks (under a dated `## /ds:review2 — DATE` group), so `/ds:polish <file>` can triage and apply them later. The `Impact` field rides along as a free-form field — `/ds:polish` parses only the `### F<n> · ` heading and `Status`, so the extra field passes through untouched.
- **Render findings as text**: the report is printed as a regular text message, and it is the deliverable. Without `+comment` there is no selection prompt at all; with it, the only prompts are the smell triage in Step 3.8 and the post gate in Step 3.9, both of which act on the already-printed report rather than replacing it.
- **Sub-agents are read-only**: analysis sub-agents have no `Edit`/`Write` in their allowed tools. The main agent never edits the working tree.
- **Fewer high-signal findings**: every sub-agent prompt instructs to skip borderline issues, and that instruction applies to the four new dimensions exactly as it does to the six original ones. Ten reviewers is not a licence for a longer report — a run that returns twenty mediocre findings is a worse outcome than one that returns five good ones.
- **Lane discipline between neighbours**: Performance owns data structures and query patterns; Reliability owns concurrency stalls and event-loop blocking. Operability owns whether a failure is *visible*; Reliability owns whether it *happens*. Configuration owns the value of a knob; Efficacy owns whether the change it belongs to achieves its stated purpose. Each addendum names the boundary so two reviewers don't file the same finding twice.
- **Categorization is at capture**: each finding is `confident` or `smell` based on whether the proposed fix is concrete and whether the counter-argument is trivial. Smells are first-class; they need no proposed change (`(needs unpacking)` is acceptable).
- **Respect prior decisions**: the ticket-context summary in the shared brief is authoritative — sub-agents must not re-litigate. The exception is Efficacy, which may flag an acceptance criterion it believes is itself the problem, as a finding rather than a quiet workaround.
- **Conventions compliance**: Step 1 discovers every `CLAUDE.md`/`AGENTS.md` applicable to the changed files (root + nested, ordered most-specific first); the Consistency reviewer checks the diff against their documented rules and cites the exact rule and its source file per violation. Purely mechanical formatting rules owned by `/ds:pre-review` are skipped to avoid overlap.
- **Always update ticket context** (when a ticket is detected in `MODE=own`) — including when nothing was captured, and including when the bar held everything back. The audit trail matters.
- **`/ds:review2` is not `/ultrareview`**: this command is local-only, free, and agent-driven. Do not invoke or reference the cloud `/ultrareview`.
- **Parallel sub-agents**: launch all ten reviewers in a single tool-use turn so they run concurrently. Do not chain them.
