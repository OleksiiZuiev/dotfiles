---
description: Seven-dimension review of the current PR — code quality plus reliability, operability, configuration and efficacy, with every finding tiered by user impact.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(find *), Read, Write, Edit, Grep, Glob, Task, TaskCreate, TaskGet, TaskList, TaskUpdate, AskUserQuestion, mcp__claude_ai_Linear__get_issue
argument-hint: [+comment] [+ask] [<pr-number>] [--to <file>] [--bar low|medium|high]
---

You are performing a substantive review of a pull request. The goal is to absorb the mechanical reviewer effort on bigger PRs by surfacing the issues a thoughtful human reviewer would actually raise across seven dimensions: **simplicity & readability, performance, consistency/conventions/duplication, test coverage, reliability & operability, configuration & capacity, and efficacy & claims**.

Every finding is categorized at capture time as either **confident** (concrete proposed change with a trivial/empty counter-argument) or **smell** (real trade-off surfaced by the counter-argument, or no concrete fix). Smells are first-class output — they don't need to come with a fix. Every finding also carries an **impact tier** — `user-facing`, `efficacy` or `maintenance` — which is what the report leads with, because that is the tier a merge decision turns on.

The command never touches the working tree — no edits, no commits, no pushes. It surfaces findings in chat for the user to read and act on selectively in follow-up prompts. The one thing it can write is the PR itself, and only behind the `+comment` flag. The mode-aware behavior:

- **`MODE=own`** (PR author == you): print the categorized report and write an audit entry to ticket context.
- **`MODE=draft-comments`** (PR author ≠ you): print the categorized report and additionally render copy-paste-ready `Draft comment:` blocks for **confident findings only**. Smells appear in the report for your private read but are not drafted as PR comments. No ticket-context writes.

**`+comment`** (either mode) posts the findings to the PR as one inline review instead of leaving you to copy-paste. Every shown finding posts, confident and smell alike, and **nothing is confirmed first** — the payload is previewed so the transcript records what went out, then submitted. `--bar` is the only filter on what reaches the PR. So with the flag on, a smell *can* reach the PR; without it, the no-post default above still holds.

**`+ask`** puts the human back in the loop, and does nothing on its own: with `+comment` it restores the two gates — each smell triaged one-by-one with `AskUserQuestion` (Step 6), then one confirmation on the whole payload (Step 7c), the same in-the-loop posture `/ds:polish-pr` uses. The confident/smell split still decides the *voice* of every draft — assertion for a confident finding, question for a smell — on both paths; under `+ask` it additionally decides which findings need a per-item decision.

**`--bar low|medium|high`** (default `medium`) sets the **reporting bar** — how high a finding has to clear to be shown. Full semantics in Step 3.2; the short version is that a higher bar means fewer findings, and it only ever filters the `maintenance` tier.

**Distinction from siblings:**
- `/ds:work-on` Step 3.5 — the mechanical convention check on the freshly written code, before the commit. Auto-applies; owns the mechanical lane, but only on runs that passed `+checks`. Without it the lane falls to this command's Consistency reviewer.
- `/ds:polish-pr` — addresses *human* reviewer comments already posted on the PR.
- `/ds:review` (this command) — substantive seven-dimension review of the PR, before/between human review rounds (own or someone else's). Every finding is tiered by user impact, and `+comment` posts them to the PR instead of leaving you to copy-paste them.

## Your Task

### Step 0: Detect PR & Gather Inputs

0. **Parse arguments.** `$ARGUMENTS` may contain an optional `+comment` flag, an optional `+ask` flag, an optional PR number, an optional `--to <file>` flag and an optional `--bar <level>` flag, in any order:
   - `POST_COMMENTS` = `on` if the text contains `+comment`, else `off`.
   - `ASK` = `on` if the text contains `+ask`, else `off`.
   - **Strip the `+comment` and `+ask` tokens before parsing anything else** — otherwise either is mistaken for the PR number. (The `+` prefix, as in `/ds:polish-pr`'s `+temp-worktree`, stops the Claude CLI consuming them as CLI flags.)
   - `OUT_FILE` = the token following `--to` (the findings file to write findings into), else empty. When set, Step 3.6 appends the findings to it as shared-format item blocks.
   - `BAR` = the token following `--bar`, else `medium`. Accepts `low`, `medium`, `high`. Anything else is not fatal — print `> Unknown bar '<value>' — using medium.` and continue with `medium`.
   - `PR_ARG` = the first bare token that is **not** `--to` or `--bar`, and not the value of either, else empty. **Both flag values must be excluded**, or `/ds:review --bar high` reads `high` as the PR number.

   `ASK=on` with `POST_COMMENTS=off` is not fatal — print `> +ask has no effect without +comment — nothing is posted, so there is nothing to confirm.` and continue.

   When `POST_COMMENTS=on`, print the flag line so the posting behaviour is visible before any analysis runs:
   - `ASK=off`: `> +comment: on — every shown finding posts to the PR as one review, unprompted. The payload is previewed first; --bar is the only filter. Add +ask to triage each smell and confirm before posting.`
   - `ASK=on`: `> +comment +ask: on — confident findings post after one confirmation; smells are triaged one-by-one. Nothing reaches GitHub unconfirmed.`

   When `BAR` is not `low`, print the bar line too, so the filter is visible before any analysis runs rather than discovered in the report:
   > `--bar medium — low-severity maintenance findings are held back, smells and confident alike. user-facing and efficacy findings always show.`

   (At `--bar high`: `--bar high — low- and medium-severity maintenance findings are held back, smells and confident alike. user-facing and efficacy findings always show.`)

1. **Resolve the PR number.**
   - If `PR_ARG` is set, use PR **#`PR_ARG`**.
   - Otherwise auto-detect from the current branch:
   ```bash
   gh pr view --json number --jq '.number'
   ```
   - **If failed** (no PR for current branch): inform the user and stop:
     > No PR found for branch `<branch-name>`. Create one first with `/ds:create-pr` (or `gh pr create`), or pass the number directly: `/ds:review <pr-number>`.

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

### Step 0.5: Pre-Seed the Checklist

Before doing anything else, create the checklist. The seed list mirrors what will actually run so the multi-step flow survives a long session — same pattern as the pre-seed step in `/ds:work-on` (Step 0.5). When the `Task*` tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`) are available, mirror the checklist into them so it stays visible to the user; otherwise keep it in your own messages. Never narrate which tracking tools this build has.

1. `🔬 Analysis: launch review sub-agents`
2. `📋 Findings report`
3. `📄 Write findings to <OUT_FILE>` — *only when `OUT_FILE` is set*
4. `🗒️ Draft PR comments` — *only when `MODE=draft-comments` or `POST_COMMENTS=on`*
5. `🎯 Anchor findings to diff lines` — *`POST_COMMENTS=on` only*
6. `🙋 Triage smells (in-the-loop)` — *`POST_COMMENTS=on` **and** `ASK=on` only*
7. `🚀 Preview & post review to PR` — *`POST_COMMENTS=on` only*
8. `📝 Update ticket context` — *`MODE=own` only*
9. `✅ Final summary`

### Step 1: Load Shared Context

These become the **brief** that the analysis sub-agents receive, so they all start with the same picture. Issue the independent lookups **in a single message** — the discovery script, the Linear call and the context-file read do not depend on each other, and running them serially is the largest avoidable delay before the sub-agents launch.

1. **Conventions files — discover paths, do NOT read the contents.** The documented rules the diff must comply with live in every `CLAUDE.md` and `AGENTS.md` that governs a changed file, not just the repo root: a monorepo keeps subsystem rules in nested files, and `CLAUDE.md` is sometimes just a thin pointer to a sibling `AGENTS.md`. The brief passes **paths**; the Consistency reviewer is the only consumer and reads them in full itself. Reading them here as well would put the whole set in this context for no further use.

2. **Sibling-file inventory** — the unchanged files that the changed files sit beside. A file that *should* have changed and did not cannot be found in a diff, by definition; this inventory is the only thing that makes it reachable. One listing per **directory**, not per changed file.

   Steps 1 and 2 share one script (in `MODE=draft-comments`, swap the first line for `gh pr diff <pr-number> --name-only`):
   ```bash
   CHANGED=$(git diff origin/<BASE>...HEAD --name-only)
   echo '--- conventions ---'
   echo "$CHANGED" | while read -r f; do
     d=$(dirname "$f")
     while :; do
       for n in CLAUDE.md AGENTS.md; do [ -f "$d/$n" ] && printf '%s\n' "$d/$n"; done
       [ "$d" = "." ] && break
       d=$(dirname "$d")
     done
   done | sort -u
   echo '--- siblings ---'
   echo "$CHANGED" | xargs -r -n1 dirname | sort -u | while read -r d; do
     printf '\n== %s ==\n' "$d"; ls "$d" | head -50
   done
   ```
   - Order the conventions paths **most-specific (deepest) → least-specific (repo root)** — a nested file refines or overrides the root's rules for files beneath it. If none are found, note "no conventions files"; the Consistency reviewer falls back to inferring conventions from neighbouring code.
   - Keep the sibling listing only where the shape is meaningful — per-environment config (`agentserver-*.tfvars`), per-provider adapters, per-entity migrations, a family of handlers. Skip directories where the neighbours are simply unrelated files, and skip any directory with a very large flat listing unless the changed file's name has an obvious family (a shared prefix or suffix). Record each family as `<pattern>: <N> files, <M> in the diff — <the ones not in the diff>`.
   - In `MODE=draft-comments` the conventions files are read from your current checkout — a fine proxy, since conventions rarely differ from the PR head. If the PR itself adds or edits a conventions file, account for that from the diff.

3. **Linear ticket** (only if `TICKET_ID` is set):
   ```
   mcp__claude_ai_Linear__get_issue with id=TICKET_ID, includeRelations=true
   ```
   Capture title, description, acceptance criteria, status. **Keep the acceptance criteria verbatim** — the Efficacy reviewer walks them one at a time, so a paraphrase costs it the check.

4. **Ticket context file**: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` — read if it exists. Summarize previous-session decisions so the reviewers don't re-litigate settled questions. Two things to extract specifically:
   - The decisions themselves, for the brief's "prior decisions" block.
   - **Whether a session entry for this branch records a `Convention check:` line** (written by `/ds:work-on` Step 7). Only the values `N fixes applied` and `clean` mean the mechanical conventions were already enforced against this diff before the commit — set `MECHANICAL_ENFORCED` to that value and surface it in the brief. Leave it unset when the line reads `skipped` (that run opted out of `/ds:work-on`'s `+checks`) or when no such line exists at all: either way nobody checked, and the Consistency reviewer must.

5. **Dependency source paths** — where the installed source of a dependency the diff relies on can actually be read. Several of the highest-value findings a reviewer makes turn on what a library *does*, not on what the calling code assumes about it; without a path, a sub-agent can only guess.
   - Scope it to dependencies the diff touches: a version bump in `pyproject.toml` / `package.json` / `*.csproj`, or an import the diff adds.
   - Resolve each, in order:
     1. **A local clone** — per `~/.claude/CLAUDE.md`, a DataSnipper package usually exists at `C:\work\github\{org}\{repo}`. Check `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` when the name is partial. This is the best source because it carries history.
     2. **The project's installed tree** — `.venv/lib/python*/site-packages/<pkg>`, `node_modules/<pkg>`, or the uv/npm cache.
   - A package resolving to a *different version* than the diff depends on is still useful, but say so: the sub-agents must know they are reading a neighbouring version, not the one under review.
   - Record `<package> <version-if-known> → <path>` for each. Anything unresolved is recorded as unresolved — that is information too, and it changes how a finding gets framed.

Print a brief "Review context loaded" summary so the user sees what the reviewers will see:

```
Reviewing PR #<N>: <PR title>
Ticket: <TICKET_ID> — <ticket title>  (or "no ticket detected")
Base: origin/<base>
Diff: <files-changed> files, +<additions>/-<deletions>
Context file: loaded / not found / no ticket
Conventions: <N> files — <paths, most→least specific>  (or "none found")
Mechanical conventions: enforced by /ds:work-on Step 3.5 (<value>) / not checked
Dependency sources: <pkg>@<version> → <path>, …  (or "none resolved" / "no dependency changes")
Sibling families: <pattern> <M>/<N> in diff, …  (or "none")
Lanes: 7 launched / <N> launched, skipped <lane> (<reason>)
```

### Step 2: Launch Multi-Agent Analysis (parallel)

Mark `🔬 Analysis: launch review sub-agents` as `in_progress`.

Launch the reviewers below **in a single message with one parallel `Task` tool call each**. Each call uses `subagent_type: "general-purpose"`. Apply the model tiering shown.

**Sub-agent allowed tools (all):** `Bash(git diff*), Bash(git log*), Bash(git show*), Bash(ls *), Bash(find *), Read, Grep, Glob`. NO Edit — sub-agents surface findings only; nothing in this command modifies the working tree.

**Skip a lane whose subject is entirely absent from the diff.** A lane with nothing to review still ingests the whole diff to answer "No issues found" — the most expensive way there is to learn nothing. Skip **Configuration & Capacity** when the diff changes no config, infra, dependency version or tuned literal; skip **Test Coverage** when the diff is documentation-only. The bar is *entirely absent*, not *small* — when in doubt, run the lane. Name every skipped lane and its reason in the context banner and in the Step 3 footer, so a thin report is never mistaken for a clean one.

#### Core brief — prepend to every sub-agent prompt

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
> - **user-facing** = a user's request gets slower, an error reaches them, or the service's availability now depends on something it did not depend on before. Say how far the blast radius reaches — whether it lands only on the session that triggered it, or on every concurrent session sharing the process or replica. **"Gets slower" must be sized before it can claim this tier**: say what the extra work costs and what the operation it sits in already costs, and give the ratio. A multiplier — "N × D calls per render", "once per row", "on every keystroke" — is a count, not a size; it becomes one only when you say what one call costs and what the surrounding operation costs. An effect you cannot size is `maintenance`, however large its multiplier looks.
> - **efficacy** = the change may not achieve the purpose it states, or something it claims — in a docstring, a comment, the PR body, the ticket — is not true of the code as written.
> - **maintenance** = everything else: hygiene, readability, duplication, future cost. The default when neither of the above applies. Most findings are this, and that is fine — do not inflate a finding's tier to get it read.
>
> **Severity on an effect-shaped finding.** Where a finding's case rests on an effect — slower, more memory, more calls, more allocations — its `Severity` follows the ratio you sized above, not the multiplier that led you to it. An effect you could not size is `low`. That is the only severity rule stated here; everywhere else, judge as a reviewer would.
>
> **Rules of engagement:**
> - Return ONLY findings a thoughtful human reviewer would actually raise. If you have to reach for a finding, skip it. Fewer high-signal findings > many low-signal findings.
> - Every finding MUST have a non-empty `Counter-argument:` field. "none" is acceptable when the finding really has no real case against it (genuine no-brainer) — but the field must be present.
> - Every finding MUST have a `Code context:` block — a unified-diff fenced block showing ~5–10 lines of surrounding code with the change applied as `-`/`+` lines. For smells where `Proposed change:` is `(needs unpacking)`, include the unmodified code excerpt (no diff markers needed) so the reader sees the area in question.
> - Findings are not confined to the changed lines. A file that should have changed and did not, an unchanged caller the diff breaks, or a claim in an unchanged docstring the diff falsifies are all in scope — anchor them to a real `file:line` either way.
> - Do NOT propose changes that violate the ticket acceptance criteria or any prior decision listed above. If you believe an acceptance criterion is itself the problem, say so as a finding rather than quietly working around it.
> - You may use `git show`, `Grep`, and `Glob` to look at the surrounding code for context — but stay within your dimension's lane.

#### Specialist inputs — append only to the lanes that consume them

Broadcasting these to every reviewer costs a copy per lane and buys nothing in the lanes that are not told to use them.

**Dependency sources** → append to **Reliability & Operability**, **Configuration & Capacity**, **Efficacy & Claims** only:

> **Dependency sources** (readable installed source for the dependencies this diff relies on):
> <`<package>@<version> → <path>` per line, marking any that resolved to a different version than the diff depends on, or "none resolved">
>
> **Reading the installed source of a dependency this diff relies on is in scope**, using the paths above. Do NOT assert a dependency's behaviour you have not read. If the source is unavailable, say so explicitly and frame the finding as a question that names precisely what would answer it — an honest question about an unread contract is a better finding than a confident guess.

**Sibling families** → append to **Configuration & Capacity** only:

> **Sibling families** (files beside the changed ones, and which are in the diff):
> <`<pattern>: <N> files, <M> in the diff — not in the diff: <names>` per line, or "none">

**Mechanical-conventions status** → append to **Consistency, Conventions & Duplication** only, and only when `MECHANICAL_ENFORCED` is set:

> **Mechanical conventions:** already enforced against this diff by `/ds:work-on` Step 3.5 (<value>).

#### Per-dimension prompt addendum

After the core brief and any specialist inputs, append the dimension-specific instruction:

| Reviewer | Model | Addendum |
|---|---|---|
| **Simplicity & Readability** | opus (inherit — omit `model` field) | "Your dimension is **simplicity and readability** — two questions answered on one reading of the same code. **(1) Simplicity:** could the same requirement be met with materially less code, fewer abstractions, or fewer moving parts? Flag: premature abstraction, over-parameterization, speculative generality, layers added for hypothetical futures, indirection that doesn't pay for itself. **(2) Readability:** is the intent of each non-trivial change obvious from the code alone? Flag: unclear names, missing-but-needed early returns, deeply nested conditionals, long functions doing multiple things, magic literals lacking a named constant. Do NOT suggest adding comments — prefer expressive code per repo conventions. You may NOT propose changes that violate the ticket acceptance criteria. Where a finding answers both questions, file it once." |
| **Performance** | opus (inherit) | "Your dimension is **performance and data-flow correctness**. Look for: wrong data structures (lists where dicts/sets fit, repeated linear scans), N+1 query patterns / inefficient DB access, missing `Include`/eager loading where it matters, unnecessary allocations on hot paths, repeated work that could be hoisted. **Size every effect before you file it.** Put the work you want removed against the budget of the operation it sits in — the render, the request, the query — and say the ratio out loud. Repeated work that is a rounding error against an unavoidable cost in the same pass does not earn a concept to remove it, however large its multiplier looks; the standard trap is optimizing a list that looks unbounded but is already bounded by something more expensive beside it. **A change that strictly removes work or code is exempt** — it costs nothing, so it needs no sizing: hoisting a call out of a loop, or moving one into the branch that actually reads its result, stands on its own. Concurrency stalls and event-loop blocking belong to the Reliability & Operability reviewer — leave those to it." |
| **Consistency, Conventions & Duplication** | sonnet | "Your dimension is **codebase consistency, conventions compliance and duplication** — three parts, all answerable from one pass of Grep/Glob over the neighbouring code. Do that exploration once and use it for all three. **(1) Consistency:** compare patterns introduced by the diff against existing patterns for similar problems. Flag: new patterns where an established one exists, inconsistent naming/structure compared with siblings. **(2) Conventions compliance:** read *in full* every conventions file listed in the brief (`CLAUDE.md` / `AGENTS.md`, root and nested). Extract each concrete, checkable rule, then verify the diff complies. A nested file's rule governs files beneath it and refines/overrides the root for those paths. Flag each violation with the **exact rule quoted and its source file cited** (e.g. `src/api/AGENTS.md`). Most rule violations are `confident` — a documented rule is an objective standard, so the counter-argument is usually 'none'; a violation with a legitimate, diff-specific justification becomes a `smell`. **If the brief carries a `Mechanical conventions: already enforced` line, skip the mechanical rules entirely** — that pass auto-applied the mechanical, locally-fixable rules and the repo overlay's `## Enforced` list before the commit, and it explicitly refuses design-level changes. Spend the whole budget on structural compliance instead, which is exactly what it left behind. When the brief carries no such line, nobody checked and mechanical violations are in scope. If no conventions files were found, fall back to inferring conventions from neighbouring code. **(3) Duplication:** use Grep to verify duplication is real, not just superficially similar. Flag: duplicated logic within the diff or between the diff and existing code, copy-paste blocks differing only in literals, extract-method candidates. Each such finding must reference both/all duplicated sites. Where a finding answers more than one of the three parts, file it once." |
| **Test Coverage** | sonnet | "Your dimension is **test coverage**. For every non-trivial behavior change in the diff — new functions/methods with logic, new conditional branches, new error paths, new public APIs, modified business rules — check whether a test exercises it. Use Grep/Glob to (a) locate test files for the changed code (test-file naming conventions vary by repo: deduce from neighbours and `CLAUDE.md`), and (b) find tests for analogous existing code so you know what 'covered' looks like in *this* repo. Flag: new logic with no test, new conditional branch covered only on the happy path, modified behavior whose existing test was not updated, new public/exported surface without an integration test where the repo's convention requires one. **Weight by consequence, not by line count** — the statement whose failure takes the service down deserves a test far more than a branch in a formatter, so say what an untested path costs when it breaks. **Also judge whether a test that exists can fail for the reason it exists**: a test that mocks the very dependency whose real contract is the risk, an assertion that also holds on empty output, a test proving only that a *different* exception wasn't raised. Where a test's subject is a dependency's behaviour rather than this code's contract, say so — the repo conventions forbid re-verifying a dependency. Skip: trivial getters/setters, pure renames, comment/doc-only changes, formatting, generated code, infra/YAML/config, and anything in directories the repo's existing tests do not cover (deduce). Respect the repo's testing posture — if `CLAUDE.md` or neighbour evidence says 'no tests for X', do not invent a requirement. Reference both the diff location and the expected test location (or analogue) in every finding." |
| **Reliability & Operability** | opus (inherit) | "Your dimension is **reliability and operability** — for every failure path the diff introduces or moves, two questions answered on one traversal: does it happen, and can the person on call see it. Walk each path once and answer both; where a finding answers both, file it once. **(A) Reliability — does it happen, and who pays.** For every new or changed call the diff introduces, ask what happens when it is slow, unreachable, or returns something the code does not expect. Flag: (a) an await on a non-essential subsystem with no timeout and no `except`, where a fault there takes down something that should outlive it — startup lifecycle, request handling, shutdown; compare against how the neighbouring subsystems in the same function handle the same risk. (b) An exception that can escape a callback, hook, or background task that nothing supervises — name what stops working for the remaining life of the process when it dies, and whether anything would make that visible. (c) An `async def` body with no `await` on a path that can loop, or synchronous work (logging, serialization, CPU, blocking I/O) long enough to stall the event loop; when a timeout is configured around such a body, say plainly that it cannot fire, because a timeout that cannot preempt is worse than none — it reads as a bound that isn't there. (d) A lock, or app-scoped/process-scoped state, that turns one session's fault into every concurrent session's fault — state the blast radius explicitly rather than leaving it implied. (e) Shutdown ordering: whether a drain, flush, or close step can be skipped because an earlier step raised, and whether its timeout fits inside the platform's own grace period. (f) A failure class the change *introduces* that the old code did not have — buffering, caching, batching and retrying all trade one failure mode for another, so name the new one. The test is a fault that is plausible in production, not any theoretical one — do not propose defensive handling nobody would add. **(B) Operability — whether the person on call, who did not write this code, can see what it does when it goes wrong.** Flag: (a) a failure path the change introduces or moves that nothing counts, logs, or traces — including the case where the *detector itself* fails silently and its silence is indistinguishable from healthy quiet. (b) An instrument whose claimed coverage is wider than its real coverage: read every path that reaches it and name the ones that do not — a dependency that logs-and-returns instead of raising is the usual culprit, and the claim is usually in a docstring or the PR body. (c) A label on a metric that is not also a structured field on the log record for the same event: an operator alerting on the metric cannot pivot to the logs on that dimension. Check every failure path carries the same field shape — a field present on one path and absent on its sibling is a finding, because a filter that works for one silently misses the other. (d) Log volume and cost under **sustained fault**, not steady state: one record per event for the length of an outage window, a traceback formatted inline on a request path, a multi-line dump per call. (e) A log message whose wording steers an operator to the wrong cause — most often a message hardcoded to one failure mode inside an `except` that catches several. (f) An existing alert, dashboard, or saved query this change silently invalidates: the old signal stops appearing and the change looks like a success either way. Grep for message text the diff moves or removes. Every operability finding must name the operational question that cannot be answered without the change you propose — do NOT propose telemetry for its own sake." |
| **Configuration & Capacity** | sonnet | "Your dimension is **configuration and capacity**. Flag: (a) a tuned value with no stated reasoning anywhere — the diff, PR body, or ticket must say why *this* number; and any deviation from a library or platform default must be explained, in both directions (raising and lowering). (b) A value whose consequence is not worked out: what throughput, memory footprint, or latency does it imply, and does this system's actual traffic shape fit inside it? Do the arithmetic and show it in the finding. (c) A timeout or budget that does not fit inside the platform's own budget — container termination grace period, server shutdown window, upstream deadline; an unhonourable timeout is a false promise. (d) Back-pressure left unspecified: when the bounded thing is full, does the caller reject immediately or wait, and for how long? Read the dependency source from the brief rather than inferring it from an error message's wording. (e) **Cross-environment drift** — the brief lists each changed file's sibling family. A sibling that carries the same block and was not updated is a finding: say what it runs on instead, and when that first bites someone. This check must look outside the diff, and it is the one thing no other reviewer can do. (f) A version constraint that admits a behaviour change with no code change — a range where the diff depends on semantics that only a pin protects. Skip values that are obviously conventional for the ecosystem and unchanged by the diff." |
| **Efficacy & Claims** | opus (inherit) | "Your dimension is **efficacy and claims** — does the change do what it says, and is what it says true? You are the only reviewer whose lane is the gap between stated intent and code, so do not drift into code quality. Flag: (a) the fix relabels or relocates the failure rather than removing it. Trace the root cause the ticket names through the new code and say whether the same trigger still produces the same loss under a different name. Where you cannot tell without the dependency's source, read it (paths in the brief); where you still cannot tell, raise it as a question and say precisely what would answer it. (b) A claim in a docstring, code comment, PR body, or commit message the code does not support — quote the claim, then name the path that breaks it. (c) An acceptance criterion the diff does not meet, **including one met only partly** — a rule applied to six of nine files, a counter that observes three of four paths, a bound set on one caller and not its sibling. Walk the acceptance-criteria list explicitly, one at a time, and say for each whether it is met, partly met, or unmet. (d) A new risk the change introduces that is written down nowhere — a loss class, a latency class, a new dependency. If the change is a trade rather than a win, that trade belongs in the PR body; say so. (e) A claim you cannot verify at all, and exactly what it would take to verify it. Every finding must be anchored: quote the claim or the acceptance-criterion line, then name the code that contradicts it. A vague 'this might not work' is not a finding." |

Mark `🔬 Analysis: launch review sub-agents` as `completed` after all sub-agents return.

### Step 3: Aggregate & Present Findings

Mark `📋 Findings report` as `in_progress`.

1. Parse each sub-agent's structured findings block.

2. **Apply the bar.** The bar is a **severity ladder** over both categories — `Category` plays no part in it, so a confident finding is filtered on exactly the same terms as a smell. Partition the parsed findings into `shown` and `held back`, per `BAR`:

   | Bar | Held back |
   |---|---|
   | `low` | nothing |
   | `medium` | findings with `low` severity |
   | `high` | findings with `low` or `medium` severity |

   **Then rescue by tier: a finding whose `Impact` is `user-facing` or `efficacy` is never held back**, at any bar and any severity — those are the two tiers a merge decision turns on, so severity does not get to hide one. Only `maintenance` findings can be filtered. That exemption is what makes the ladder nested: everything shown at `high` is shown at `medium`, and everything shown at `medium` is shown at `low`.

   The bar acts at **report time**, not in the sub-agent brief, so every run captures the same findings and a re-run at `--bar low` reveals the held-back tail without re-analysing.

   Record two counts — `HELD_S` (held-back smells) and `HELD_C` (held-back confident findings) — and their sum as `HELD`. You need all three for the footer, Step 8 and Step 9; the findings themselves play no further part in this run. Keep the two counts apart rather than reporting one number: a held-back smell is a trade-off you didn't read, but a held-back confident finding is a **concrete fix** you didn't read, and those are worth telling apart at a glance.

3. **Assign a flat 1..N id across the shown findings only**, in dimension order (the order of the table above), so every finding can be referenced unambiguously in follow-up chat. Numbering is contiguous — do not leave gaps where a finding was held back, because a gap at `#4` invites a question about a finding that is not in the report to answer it from.

4. **Print the aggregated report as a regular text message** before calling any other tool. The user can ONLY see your text output — they cannot see sub-agent return values.

   The report leads with the impact summary, because that is the tier a merge decision turns on and the detail below it is long.

   **How much detail the body carries depends on `OUT_FILE`:**
   - **`OUT_FILE` not set** — the chat report is the only copy. Print every shown finding in full under its dimension.
   - **`OUT_FILE` set** — Step 3.6 is about to write every finding in full to that file, and `/ds:polish` re-displays each block when it triages. Printing full detail twice buys nothing. Print full detail for `user-facing` and `efficacy` findings only; give each `maintenance` finding its one-line entry in the impact summary plus a `detail → <OUT_FILE> F<n>` pointer, and say so once under the summary.

   ```
   ## /ds:review findings — PR #<N> (<title>) · bar: <BAR>

   ### Impact summary

   **User-facing** (<N>) — regresses a request, an error reaches a user, or availability now depends on this
   - #3 `path/to/file:line` — <summary>   (Reliability & Operability · high · confident)
   - #7 `path/to/file:line` — <summary>   (Performance · medium · smell)

   **Efficacy** (<N>) — may not achieve its stated purpose, or claims something the code does not support
   - #11 `path/to/file:line` — <summary>   (Efficacy & Claims · high · confident)

   **Maintenance** (<N>) — hygiene, readability, duplication, future cost
   - #1 `path/to/file:line` — <summary>   (Simplicity & Readability · low · smell)
   - …

   ---

   ### Simplicity & Readability
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
   ### Consistency, Conventions & Duplication
   ### Test Coverage
   ### Reliability & Operability
   ### Configuration & Capacity
   ### Efficacy & Claims
   ...

   **Totals:** <T> shown — <C> confident, <S> smells — across <L> lanes (H high, M medium, L low).
   > Lanes skipped: <lane> (<reason>), …
   > Bar: <BAR> — held back: <HELD_S> smells, <HELD_C> confident findings. Re-run with `--bar low` to see them.
   ```

   Within each impact tier, order by severity (high → low). Omit an impact tier's heading entirely when it has no findings. Omit the **Confident** or **Smells** subsection header for any dimension where that subsection is empty, and omit a dimension's `###` heading entirely when it returned no findings — a report with empty sections is harder to read than a short one. Omit the `Lanes skipped:` line when every lane ran, and the `Bar:` line when `HELD` is 0 (always the case at `--bar low`). When only one of the two held counts is 0, still print both, so the zero is stated rather than inferred from a missing clause.

5. **Nothing-to-show short-circuit:** if the shown count == 0, print one of two lines — which one depends on whether the reviewers found nothing or the bar hid everything they found. Do not print the first when the second is true; "review passed" is a false claim about a PR whose only findings were filtered out.
   - **Nothing was captured** (shown == 0 **and** `HELD` == 0):
     > **Review passed — no substantive findings.**
   - **Everything captured was held back** (shown == 0 **and** `HELD` > 0):
     > **No findings at bar `<BAR>`** — held back: <HELD_S> smells, <HELD_C> confident findings. Re-run with `--bar low` to see them.

   Either way, skip Steps 3.6 through 7 — there is nothing to write, draft, anchor or post. Add `> OUT_FILE: nothing written (nothing to show).` when `OUT_FILE` is set, and `> +comment: nothing to post.` when `POST_COMMENTS=on`. Then go to **Step 8** in `MODE=own` (the audit entry names which of the two cases it was) or straight to **Step 9** in `MODE=draft-comments`.

Mark `📋 Findings report` as `completed`.

### Step 3.6: Write Findings to File (`OUT_FILE` set only)

Runs in **both** modes. If `OUT_FILE` is empty, skip this step.

Mark `📄 Write findings to <OUT_FILE>` as `in_progress`.

Append the findings to `OUT_FILE` as shared-format item blocks so `/ds:polish <OUT_FILE>` can act on them later. The format is owned by `/ds:polish` (see that command for the full spec); the **writer slice** is:

**Only the shown findings are written.** A finding held back by the bar does not reach the findings file, smell or confident — a finding you never read turning up in your `/ds:polish` queue is the same noise, just moved downstream. To capture the held-back tail in a file, re-run with `--bar low --to <file>`.

1. **File shape:**
   - If `OUT_FILE` does not exist, create it with a skeleton — title, an empty Inbox, then the `---` that separates Inbox from thread:
     ```
     # Findings — <PR_TITLE> (PR #<N>)
     <!-- shared findings file · written by /ds:review & /ds:analyze-pr · triaged by /ds:polish -->

     ## Inbox
     <!-- your questions/notes; only this zone is read by /ds:analyze-pr -->

     ---
     ```
   - If it exists, append below its existing content (the thread zone lives below the first `---`).
2. **Next id:** scan the file for `### F<n> · ` headings; `next = max(n) + 1` (start at `F1` if none). Continue the same counter across findings so review + analyze-pr never collide.
3. **One item block per finding**, under a `## /ds:review — <YYYY-MM-DD>` group heading. Map each finding's existing fields:
   - heading → `### F<next++> · review:<dimension> · <category>` — `<dimension>` ∈ simplicity-readability | performance | consistency-duplication | test-coverage | reliability-operability | configuration | efficacy; `<category>` = the finding's `confident`/`smell`
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

### Step 4: Draft PR Comments (`MODE=draft-comments` **or** `POST_COMMENTS=on`)

Skip entirely when neither applies. Mark `🗒️ Draft PR comments` as `in_progress`.

You draft these yourself, from the findings you already hold — each carries `Why`, `Counter-argument`, `Proposed change` and a `Code context:` block, which is everything a comment needs. The sub-agents are not asked to draft: a draft written in a sub-agent has to be ingested and reprinted here anyway, and in the common case you triage and post only a fraction of them.

**Which findings get a draft:**
- `POST_COMMENTS=off` (draft-comments mode alone): **shown confident findings only**. Smells stay reviewer-only.
- `POST_COMMENTS=on`: **every shown finding**, confident and smell. A smell's draft is written in question form either way; under `ASK=on` it is not posted until approved one-by-one in Step 6, and under `ASK=off` it enters the Step 7 payload as drafted.

A finding the bar held back is never drafted — it was never printed, so it is not yours to hand the author.

**Comment shape — every draft uses these labels, in this order:**

```
**Problem:** <one sentence>
**Suggestion:** <the concrete change>
**Alternatives:** <the other viable option(s)>      ← smells only; omit for confident findings

_(auto-review by Claude)_                           ← `POST_COMMENTS=on` only; always the last line
```

The labels are not decoration: the author must be able to read the defect and the proposed change without inferring either from prose.

**Drafting rules:**
- Write from the reviewer's voice, addressing the PR author directly.
- **Problem** is one sentence — no "I noticed that…" / "It seems like…" filler.
- **For an `Impact: user-facing` finding, Problem names who is affected and how** — which users, in which situation, and how far it spreads beyond the one session. This is what separates a comment an author acts on from one they file as a nit. Where the finding rests on an effect, Problem carries the **size** you gave it, not the multiplier that led you to it: the author is the one who decides whether a fix is worth its cost, and they can only do that against a number.
- **For an `Impact: efficacy` finding, Problem quotes the claim or acceptance criterion first**, then names the code that contradicts it.
- **Suggestion** is actionable, not a vague concern.
- 1–3 sentences per label. No restating of severity (that's reviewer mental model, not author-facing).
- Avoid hedging adjectives ("maybe", "perhaps could possibly"); stay direct but collaborative.
- **When `POST_COMMENTS=on`, close every comment body with `_(auto-review by Claude)_`** on its own line, preceded by a blank line and placed after any ` ```suggestion ` block — it is always the last line. GitHub shows an inline comment on its own, away from the review body, so the comment has to say for itself that a machine wrote it. When `POST_COMMENTS=off` the footer is omitted: you paste those drafts in under your own name.
- **Confident findings** — assertion voice. **Problem** states the defect. Follow the labelled block with a fenced ` ```suggestion ` block **only** when the change is a single small edit GitHub can apply directly; never for a structural change. No `**Alternatives:**` line.
- **Smell findings** — question voice, because a smell is by definition a live trade-off. **Problem** states the concern *as a question* the author is better placed to answer; **Suggestion** names the option you lean toward; **Alternatives** names the other viable option(s), and is required — it is what makes this a smell rather than a defect. Never a ` ```suggestion ` block: there is more than one viable answer, and GitHub's one-click apply would misrepresent that. Where `Proposed change:` is `(needs unpacking)`, **Suggestion** says what would settle the question — the check to run, the source to read, the person to ask — instead of proposing a fix you cannot justify.

**When `POST_COMMENTS=off`** (draft-comments mode alone), print the drafts as copy-paste blocks and then jump to **Step 9**. Order by impact tier — `user-facing`, then `efficacy`, then `maintenance` — and within a tier by `file:line` (alphabetically by path, then ascending by starting line), so the author reads the items that block a merge first. If the same `file:line` carries confident findings from two different dimensions, include both blocks, each prefixed with `(<dimension>)`.

```
## Draft PR comments — PR #<N> (<PR_TITLE>)
Mode: draft-comments — copy-paste these into GitHub as line comments. Confident findings only; smells (see report above) are not drafted.

### User-facing

#### `path/to/file:line-range`
<draft comment markdown>

### Efficacy

#### `path/to/other-file:42-48`
(<dimension>) <draft comment markdown>

### Maintenance

#### `path/to/third-file:10`
<draft comment markdown>
```

Omit any tier heading that has no confident findings. Special cases:
- Zero shown confident findings and `HELD_C` == 0 (the reviewers surfaced only smells): print `> No confident findings to draft — the report above lists smells for your private review.`
- Zero shown confident findings but `HELD_C` > 0 (the bar hid them all): print `> No confident findings to draft at bar <BAR> — <HELD_C> were held back. Re-run with --bar low before drafting.` Do not print the line above it; "the reviewers found none" is a different claim from "you filtered them out", and only one of them is true.

**When `POST_COMMENTS=on`**, do not print the copy-paste blocks — Step 7 previews every comment before it posts, and a copy-paste block would be dead weight. Continue to Step 5.

Mark `🗒️ Draft PR comments` as `completed`.

### Step 5: Anchor Findings to Diff Lines (`POST_COMMENTS=on` only)

Runs in **both** modes. Mark `🎯 Anchor findings to diff lines` as `in_progress`.

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

   The report above and any `--to <file>` output are already written and stay valid. Skip Steps 5–7, mark their items not applicable, and continue to the mode branch.

3. **Build the commentable-line set** from the PR's own diff — `gh pr diff <pr-number>`, **not** the local `git diff`, so both modes anchor against exactly what GitHub will accept. For each file, parse the hunk headers `@@ -a,b +c,d @@`; the RIGHT-side lines `c` through `c+d-1` are commentable (added and context lines both count).

4. **Route each finding** by its `file:line-range`:
   - Range end inside the set → `INLINE`, with `side: RIGHT` and `line` = the range end. Add `start_line` and `start_side: RIGHT` when the range start falls in the **same hunk**; when it doesn't, collapse to the single end line rather than spanning hunks.
   - Otherwise → `BODY`. This is the expected home for an unchanged caller the diff breaks, a docstring the diff falsifies, or a sibling file that should have changed — findings no diff-anchored comment can reach. Nothing is dropped for being unanchorable.

5. **Dedup guard.** A re-run after a push must not duplicate the review:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<pr-number>/comments --paginate \
     --jq '.[] | select(.user.login=="<ME>") | "\(.path):\(.line)"'
   ```
   Mark any finding whose `path:line` already carries a comment of yours as `already-posted` and drop it from the payload. Count them; they are reported, not silently discarded.

6. Print: `> Anchoring: <I> inline, <B> into review body, <D> skipped as already posted.`

Mark `🎯 Anchor findings to diff lines` as `completed`.

### Step 6: Triage Smells In-the-Loop (`POST_COMMENTS=on` **and** `ASK=on` only)

**When `ASK=off`, skip this step entirely**: every shown smell enters the Step 7 payload as drafted, in question voice. Print `> Smells: <N> posted as drafted (no +ask — not triaged).` and continue to Step 7. Mark the item not applicable.

Mark `🙋 Triage smells (in-the-loop)` as `in_progress`.

A confident finding has a concrete fix and a trivial counter-argument, so it needs no per-item decision — it goes straight to the Step 7 preview. A smell is the opposite: a live trade-off, or a problem with no obvious fix. Those get your judgement one at a time, on the same pattern as `/ds:polish-pr` Step 5.

Only the **shown** findings reach the PR at all — on both paths. A smell held back by the bar is never triaged or posted, and a held-back confident finding never enters the Step 7 payload — posting a comment the user did not read would be worse than the noise the bar exists to remove. This is the whole of the filter under `ASK=off`, which is why the bar is named in the `+comment` banner.

If there are no smells, print `> No smells to triage.` and continue.

**a. Scope guard first.** Seven dimensions can still surface a lot of smells, and one `AskUserQuestion` each would be an interrogation. If the smell count is **greater than 8**, ask once via `AskUserQuestion` before the loop:
- **Review all `<N>`** — every smell gets a decision
- **Only `user-facing` + `efficacy`** — the tiers a merge turns on; the rest stay in the chat report
- **Let me pick** — you name the finding ids to triage
- **Post no smells** — skip the loop; confident findings still post

Anything out of scope is recorded as `not posted (deferred)` and stays in the chat report only. The bar does upstream what this guard does downstream, so at the default bar it fires rarely; it stays as a second net.

**b. Then one at a time.** For each in-scope smell, print its flat report id, `file:line` and one-line summary; its `Why`, `Counter-argument` and `Proposed change`; its `Code context:` block; the drafted comment body verbatim, so you approve the exact words that will be posted; and its destination (`inline at <path>:<line>` or `review body (not anchorable to the diff)`).

Then `AskUserQuestion`:
- **Post as drafted** — add to the payload
- **Post all remaining smells in this dimension** — batch escape hatch, so a long tail of same-dimension smells can't turn into ten prompts
- **Modify wording** — you give the angle, redraft it, show the new body, and confirm once before adding
- **Don't post** — stays in the chat report only

Wait for each decision before showing the next smell. Confident findings never enter this loop.

**c. Print the tally:** `> Smells: <A> approved for posting, <D> declined, <F> deferred out of scope.`

Mark `🙋 Triage smells (in-the-loop)` as `completed`.

### Step 7: Preview & Post (`POST_COMMENTS=on` only; confirmation under `+ask`)

Mark `🚀 Preview & post review to PR` as `in_progress`.

**a. Assemble the review body.** In order:
1. One line naming the source — "Automated seven-dimension review via `/ds:review`."
2. `Posted: <U> user-facing, <E> efficacy, <M> maintenance.`
3. `### Findings outside the diff` — every `BODY` finding as `` `file:line` `` followed by its Problem/Suggestion (and Alternatives) block, each closing with its own `_(auto-review by Claude)_` line. Omit this heading entirely when there are none.
4. `🤖 Generated with [Claude Code](https://claude.ai/claude-code)` — **once, here only.** This link line never appears on an individual comment; the per-comment marker is the `_(auto-review by Claude)_` footer drafted in Step 4.

**b. Preview.** Runs on both paths — under `ASK=off` nobody confirms the payload, so printing it is the only record of what reached GitHub, and you need that record to go delete something. Print the payload exactly as it will appear on GitHub: the review body, then each inline comment under a `path:line (side)` header. Order by impact tier — `user-facing`, then `efficacy`, then `maintenance` — and within a tier by `path` then ascending `line`, so the author reads what blocks a merge first. Close with the counts:

```
<C> confident inline, <S> smells inline, <B> in review body.
```

**c. Confirm (`ASK=on` only).** When `ASK=off`, print `> Posting — no confirmation gate (+ask not set).` and go straight to sub-step d.

Under `ASK=on`, one `AskUserQuestion`:
- **Post review** — post everything previewed
- **Post inline only** — drop the `Findings outside the diff` section, keep the inline comments
- **Cancel** — post nothing

On **Cancel**, print `> Cancelled — nothing posted to the PR.` and continue to the mode branch. The report stands as the deliverable.

**d. Post.** Write the payload to a JSON file under the session scratchpad, then submit it as one review — one batched review is one notification and one reviewable unit, which is why it is preferred over posting each comment standalone:
```bash
gh api --method POST repos/{owner}/{repo}/pulls/<pr-number>/reviews --input <payload.json>
```
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

- **If `MODE=own`:** proceed to **Step 8**.
- **If `MODE=draft-comments`:** skip to **Step 9**. Reviewing someone else's PR is not your ticket work; no audit entry is written.

### Step 8: Update Ticket Context (`MODE=own` only)

Mark `📝 Update ticket context` as `in_progress`.

If `TICKET_ID` is `null`, mark this step `completed` with note "No ticket ID — ticket context not updated" and continue.

Otherwise, launch a `general-purpose` sub-agent (`model: "haiku"`) to append a new session entry to `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md`. Pass it:

- **Session title:** `Review via /ds:review` (or `Review passed (no findings)` when nothing was captured at all)
- **Branch name** (from `git branch --show-current`)
- **Repository name** (from `git remote get-url origin` or `gh repo view --json name`)
- **Accomplished:** one line — `<T> findings surfaced — <C> confident, <S> smells across <L> lanes; <U> user-facing, <E> efficacy.` When nothing was captured: `Review passed — no substantive findings across <L> lanes.` Name any skipped lane and why. When `+comment` posted, append `; <P> posted to the PR (<C2> confident, <S2> smells)` — the next session needs to know which findings are already public. Append ` — unprompted` when `ASK=off`, so a later session can tell a review a human approved item-by-item from one that posted itself.
- **Bar:** when `HELD` > 0, append `; reviewed at bar <BAR>, held back <HELD_S> smells and <HELD_C> confident findings` to the `Accomplished:` line. This is the **only** place a held-back finding is recorded, so a later session reading the audit trail is not misled into treating the review as exhaustive. Name the two counts separately: `HELD_C` > 0 means concrete fixes exist that nobody has read, which is a different debt from an unread trade-off.
- **Key decisions:** the findings worth carrying into the next session — take every `user-facing` and `efficacy` finding first (those change what merges), then fill up to 3–5 bullets with the most significant `maintenance` smells. Each bullet `<file:line> — <one-line summary>`. Omit the section entirely if nothing qualifies. Held-back findings are not eligible; the count on the `Accomplished:` line is all that records them.
- **Files changed:** omit. This command does not modify the working tree.

The sub-agent should append a new section under `## Sessions` following the existing document template (see the `ticket-context` skill). If the file does not exist, create it.

**Sub-agent allowed tools:** `Bash(git *), Read, Write, Edit`

Mark `📝 Update ticket context` as `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress`.

```
/ds:review — PR #<N> (<title>)                       [+ " (draft-comments mode)" when MODE=draft-comments]
PR author: <PR_AUTHOR>   You: <ME>                    [draft-comments mode only]
Findings: <T> shown — <C> confident, <S> smells — across <L> lanes (H high, M medium, L low)
Lanes skipped: <lane> (<reason>), …
Bar: <BAR> — held back: <HELD_S> smells, <HELD_C> confident findings
Impact: <U> user-facing, <E> efficacy, <M> maintenance
Drafted as PR comments: <C> (confident only — smells excluded)    [draft-comments mode, POST_COMMENTS=off]
Posted to PR: <P> comments (<I> inline, <B> in review body) — <review-url>    [POST_COMMENTS=on]
Ticket context updated: yes / no — <reason if no>     [MODE=own only]
```

Include the `Lanes skipped:` line only when a lane was skipped, and the `Bar:` line only when `HELD` > 0. When `POST_COMMENTS=on` but nothing was posted, say why in place of the counts: `none (nothing eligible)`, `none (local HEAD differs from PR head — push and re-run)`, or — reachable only under `ASK=on`, the one path with a gate to cancel at — `none (cancelled)`. In `MODE=draft-comments` close with `No changes were made to the branch, PR, or ticket context.` — or, when comments were posted, `No changes were made to the branch or ticket context.`, because the first claim is then false.

Suggest next steps:
- Address the user-facing and efficacy findings before asking for human review — those are the two tiers a reviewer blocks on. *(draft-comments: copy the drafts above into the PR review, user-facing tier first; or, with `+comment`, check the review URL renders as intended.)*
- Re-run at `--bar low` to read the <HELD> held-back findings — <HELD_C> of them are concrete fixes. *(Only when `HELD` > 0; drop the trailing clause when `HELD_C` is 0.)*
- Engage with individual findings in chat (reference by `#N`) to discuss, dismiss, or act on them.
- Re-run `/ds:review` after addressing the major findings if more rounds are needed. With `+comment`, the dedup guard means a re-run adds only what is new.
- Re-run with `+comment` to post the findings you want on the record for your reviewers — add `+ask` to read each smell and confirm the payload before any of it lands. *(Skip when `POST_COMMENTS=on` already ran.)*
- Proceed to human review (mark PR ready with `gh pr ready` if it's a draft). *(`MODE=own` only.)*

Mark `✅ Final summary` as `completed`.

## Important Notes

- **Never touches the working tree**: this command does not edit files, commit, or push, in any mode, with or without `+comment`. The single outward write it can make is posting comments to the PR, and only under `+comment` — unprompted by default, or behind the Step 6 triage and the Step 7c confirmation when `+ask` is set. What still holds on both paths: only shown findings post, a stale local head refuses to post at all, and the dedup guard drops what is already on the PR.
- **Sub-agents are read-only and drafting is not their job**: analysis sub-agents have no `Edit`/`Write`. They also do not write PR comments — Step 4 drafts from the findings they return, because a draft written in a sub-agent has to be ingested and reprinted anyway, and most drafts are never posted.
- **The ladder must stay nested**: shown-at-`high` ⊆ shown-at-`medium` ⊆ shown-at-`low`. The tier exemption is what guarantees it, and it is why the exemption applies at *every* rung rather than only at `high` — exempting `user-facing` at `high` alone would let a raised bar *reveal* a `user-facing` · `low` finding that `medium` had hidden, and every "re-run with `--bar low` to see them" line in this command assumes the opposite. Do not narrow the exemption to the top rung.
- **`--bar` runs the opposite way to `/code-review`'s `level`**: in the built-in `/code-review` skill, a *higher* level means *broader* coverage and *more* findings. Here a *higher* bar means *fewer*. That is why this flag is called a bar and not a level: the word would import the wrong direction from the neighbouring command. Do not "fix" the direction to match.
- **`event` is always `COMMENT`**: `APPROVE` and `REQUEST_CHANGES` are rejected by GitHub on your own PR, and this command is not a merge gate on anyone else's. It posts observations, never a verdict.
- **Two attribution levels, one occurrence each**: the `🤖 Generated with Claude Code` link line goes in the review body only — repeating it on twelve inline comments is noise. Every posted comment instead closes with a plain `_(auto-review by Claude)_` line, because an inline comment is read on its own, away from the body that would otherwise disclose it. Neither line ever appears twice in the same body, and the footer is posted-comments-only: a copy-paste draft you hand-post carries neither.
- **Lane discipline between neighbours**: Performance owns data structures and query patterns; Reliability & Operability owns concurrency stalls, event-loop blocking, and whether a failure is visible. Configuration owns the value of a knob; Efficacy owns whether the change it belongs to achieves its stated purpose. Each addendum names the boundary so two reviewers don't file the same finding twice. Within a merged lane the same rule applies inward: answer both questions on one traversal and file the finding once.
- **The mechanical lane belongs to `/ds:work-on` Step 3.5**, not to this command. When the ticket context records that check ran against this diff, the Consistency reviewer skips the mechanical rules and spends its budget on structural compliance. When it doesn't, they are in scope.
- **Fewer high-signal findings**: every sub-agent prompt instructs to skip borderline issues, and that applies to the merged lanes exactly as it did to the ten they replace. Seven reviewers is not a licence for a longer report — a run that returns twenty mediocre findings is a worse outcome than one that returns five good ones.
- **`/ds:review` is not `/ultrareview`**: this command is local-only, free, and agent-driven. Do not invoke or reference the cloud `/ultrareview`.
- **Parallel sub-agents**: launch every reviewer in a single tool-use turn so they run concurrently. Do not chain them.
