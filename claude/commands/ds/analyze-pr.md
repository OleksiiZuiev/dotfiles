---
description: PR-scoped Q&A. Pass a question for one-shot analysis, or a file path containing bulleted questions for thorough grouped+parallelised analysis appended back into the file.
allowed-tools: Bash(git *), Bash(gh *), Bash(test *), Read, Write, Edit, Grep, Glob, Agent, TaskCreate, TaskGet, TaskList, TaskUpdate, mcp__claude_ai_Linear__get_issue
argument-hint: <question | file-path>
---

You are answering question(s) about a pull request — your own or a teammate's — by grounding the analysis in the diff, the Linear ticket, and the repo's conventions. The posture is **thinking buddy**, not reviewer: explain what the code does, why it's wired that way, whether it's compatible with X, what the trade-offs are. This is the counterpart to `/ds:review` (seven-dimension audit) for situations where you arrive with a specific question list instead of an opinion request.

The command has two modes, auto-detected from `$ARGUMENTS`:

- **Prompt mode** — `$ARGUMENTS` is a free-text question. One sub-agent answers it, response printed to chat. No file writes.
- **File mode** — `$ARGUMENTS` is a path to a markdown file that contains bulleted questions/tasks. The command plans groupings, fans out one parallel sub-agent per group, aggregates, and **appends the analysis back into the same file** below a `---` separator. The original bullets are preserved untouched. Alongside the narrative answers it also emits **shared-format item blocks** for the actionable items (a hybrid output), so `/polish-findings <file>` can triage and apply them. The format is owned by the `polish-findings` skill.

**Distinction from siblings:**
- `/ds:work-on` Step 3.5 — mechanical convention pass on the freshly written code, before the commit.
- `/ds:review` — opinionated seven-dimension substantive audit. Fixed output shape.
- `/ds:analyze-pr` (this command) — answers *the user's* questions about a PR. Open-ended shape driven by the questions.

## Your Task

### Step 0: Detect mode, PR, and ticket

1. **Argument required.** If `$ARGUMENTS` is empty, stop with:
   > Usage: `/ds:analyze-pr <question>` for a one-shot analysis, or `/ds:analyze-pr <path/to/questions.md>` for parallel analysis appended back into the file.

2. **Mode detection.** Treat the whole `$ARGUMENTS` as a candidate file path:
   ```bash
   test -f "$ARGUMENTS" && echo "file" || echo "prompt"
   ```
   - Exit 0 → `MODE=file`, `INPUT_FILE="$ARGUMENTS"`.
   - Exit non-zero → `MODE=prompt`, `PROMPT="$ARGUMENTS"`.

3. **PR detection** (auto from current branch):
   ```bash
   gh pr view --json number --jq '.number'
   ```
   If this fails (no PR for current branch), stop:
   > No PR found for branch `<branch>`. Create one first with `/ds:create-pr` (or `gh pr create`).

4. **Ticket ID extraction** (same pattern as `/ds:review`, `/ds:work-on`):
   - Run `git branch --show-current`.
   - Strip everything before the first `/`, take the first two `-`-separated segments, uppercase (e.g. `feat/int-419-foo` → `INT-419`).
   - If the branch does not match the pattern, set `TICKET_ID=null` and continue without Linear/ticket-context lookups. NOT a fatal error.

5. **PR metadata:**
   ```bash
   gh pr view <N> --json title,body,url,author,baseRefName
   ```
   Capture `PR_TITLE`, `PR_BODY`, `PR_URL`, `PR_AUTHOR`, `BASE=.baseRefName`.

6. **Diff** — always via `gh pr diff` so the command works from any worktree (including teammate PRs you've checked out elsewhere):
   ```bash
   gh pr diff <N>
   ```
   If the diff is empty, stop:
   > No changes on this PR. Nothing to analyse.

7. **Print mode banner** as a text message:
   ```
   > /ds:analyze-pr — PR #<N> "<title>" — MODE=<file|prompt> — ticket=<ID or "none">
   ```

### Step 0.5: Pre-Seed the Post-Analysis Checklist

Pre-seed the per-mode checklist so the multi-step flow survives a long session. When the `Task*` tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`) are available, mirror the checklist into them so it stays visible to the user; otherwise keep it in your own messages. Never narrate which tracking tools this build has.

**If `MODE=prompt`:**

1. `🔬 Single-pass analysis`
2. `📋 Print result`

**If `MODE=file`:**

1. `🗂️ Parse bullets from <INPUT_FILE>`
2. `🧩 Plan groupings`
3. `🔬 Launch parallel analysis sub-agents`
4. `🧵 Aggregate findings`
5. `📝 Append analysis to <INPUT_FILE>`
6. `📋 Print summary`

### Step 1: Load Shared Brief

Read into context — this becomes the **shared brief** prepended to every sub-agent prompt so they all start with the same picture:

1. **Repo `CLAUDE.md`** at the repo root.
2. **Linear ticket** (only if `TICKET_ID` is set):
   ```
   mcp__claude_ai_Linear__get_issue with id=TICKET_ID, includeRelations=true
   ```
   Capture title, description, acceptance criteria, status.
3. **Ticket context file:** `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/<TICKET_ID>.md` — read if it exists. Summarise previous-session decisions so the analyser doesn't re-litigate settled questions.
4. **PR title/body** (already fetched in Step 0).
5. **Full diff** (already fetched in Step 0).

### Step 2: Branch on mode

#### Branch A — `MODE=prompt`

Mark `🔬 Single-pass analysis` as `in_progress`.

Launch **one** `Agent` sub-agent (`subagent_type: "general-purpose"`, model inherited — opus). The prompt is the shared brief followed by:

> **Your question:** `<PROMPT>`
>
> Answer concretely with reference to the diff. Use `Grep`/`Read`/`git show` to look at surrounding code as needed. Show short code excerpts where they help (≤10 lines, fenced). Reference files as `path/to/file:line-range`. Don't pad — if the answer is two paragraphs, give two paragraphs. End with a one-line takeaway.

Mark `🔬 Single-pass analysis` as `completed` after the sub-agent returns.

Mark `📋 Print result` as `in_progress`. **Print the sub-agent's response as a regular text message** (users can only see your text output, not sub-agent return values). Mark `completed`. Done.

#### Branch B — `MODE=file`

**B.1: Parse bullets.** Mark `🗂️ Parse bullets from <INPUT_FILE>` as `in_progress`.

Read `INPUT_FILE`. Identify the section *above* any existing `---` horizontal rule (so re-runs don't ingest prior analyses as new questions). Inside that section, extract every line matching `^\s*[*-]\s+` — each is one question/task bullet. Preserve original order and capture each bullet's text verbatim.

If zero bullets found, stop:
> No bulleted questions found in `<INPUT_FILE>` (looked above any `---` separator). Add some bullets and re-run.

Mark `completed`.

**B.2: Plan groupings.** Mark `🧩 Plan groupings` as `in_progress`.

Reason about the parsed bullets yourself (no sub-agent). Decide:
- Which bullets are tightly coupled and should share a section (e.g. multiple questions about the same component).
- Whether any **cross-cutting** finding warrants its own top-level section (e.g. "branch is behind main", "PR mixes two unrelated changes").
- Original bullet order is preserved in the final section numbering — groupings just merge adjacent or related bullets.

Produce a plan in working memory:

```
sections: [
  { n: 1, title: "<short>", bullet_indices: [0, 1] },
  { n: 2, title: "<short>", bullet_indices: [2] },
  ...
]
cross_cutting: ["<topic>", ...]   # optional
```

Mark `completed`.

**B.3: Launch parallel analysis sub-agents.** Mark `🔬 Launch parallel analysis sub-agents` as `in_progress`.

Launch one `Agent` call per planned section, **all in a single message** so they run concurrently. Plus one extra `Agent` call for the cross-cutting block if any. Use `subagent_type: "general-purpose"`.

**Model tiering:**
- Sections containing ≥3 bullets, or the cross-cutting call → opus (inherit, omit `model` field).
- Single-bullet sections → `model: "sonnet"`.

#### Shared brief — prepend to every sub-agent prompt

> You are analysing PR #<N> in the current repo. Below is the shared context. After absorbing it, focus only on your slice (described after this brief). Do not modify files — you only return your analysis.
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
> **Diff to analyse:**
> ```diff
> <full diff from gh pr diff>
> ```

#### Per-section addendum (for each section sub-agent)

> You are answering this slice of questions for PR #<N>. Produce ONE markdown section starting with `## <section_n>. <title>`. Within the section, answer each bullet **thoroughly**. If multiple bullets fit one narrative, weave them together; otherwise use `### <sub-heading>` per bullet. Show short code excerpts (≤10 lines, fenced) where they help; use ` ```diff ` blocks when proposing changes. Reference files as `path/to/file:line-range`. End with a 1–2-sentence verdict where applicable.
>
> **Your bullets:**
> 1. `<bullet text>`
> 2. `<bullet text>`
> ...
>
> Use `Grep`/`Read`/`git show` to look at surrounding code as needed. Stay focused on the bullets you were given — don't drift into adjacent topics.

#### Per-cross-cutting addendum (if any)

> You are surfacing cross-cutting findings about PR #<N> that don't fit any single user-supplied bullet but the user should know about. Produce ONE markdown section starting with `## Cross-cutting finding: <title>` (or one `##` section per topic if multiple). Examples of what counts: branch significantly behind base, PR mixing unrelated changes, breaking-change without deprecation path, missing migration, scope creep beyond the ticket.
>
> **Topics to cover:** <topic 1>, <topic 2>, ...
>
> Be selective — only raise findings that materially affect how the user should think about the PR. If on closer inspection a topic is not real, drop it. Keep each section short and concrete.

Mark `🔬 Launch parallel analysis sub-agents` as `completed` after all sub-agents return.

**B.4: Aggregate findings.** Mark `🧵 Aggregate findings` as `in_progress`.

Collect each sub-agent's returned markdown section. Assemble in this exact order:

1. Header: `# Analysis — <YYYY-MM-DD>` (today's date) followed by `PR-<N> on branch `<branch>` vs `<base>`.`
2. Cross-cutting section(s), if any.
3. Numbered sections in **original bullet order** (sort by lowest bullet index per section).
4. `## Summary` — 4–8-line synthesis **you write yourself** (sub-agents didn't see each other's output, so only the main agent can synthesise). When the analysis surfaced actionable items, group them under inline labels: **Blockers**, **Strong**, **Worth doing**, **Optional**. When the analysis is purely explanatory (no recommendations), make this section a short bulleted recap instead.
5. **Action items** (the hybrid emission — this is what `/polish-findings` consumes; the narrative above stays as-is). After the Summary, emit a `## Action items — /ds:analyze-pr — <YYYY-MM-DD>` section with one shared-format item block per *actionable* item from the Summary. Emit an item only when there's something to potentially do or a question worth tracking — skip purely informational answers. Mapping:
   - **Blockers / Strong** → `category = confident`
   - **Worth doing / Optional** → `category = smell`
   - A question you answered that the user may want to track or that implies a decision → `category = question` (`Status: answered` when no action is needed; `Status: open` when it implies one)
   - **Ids:** scan the current `INPUT_FILE` for existing `### F<n> · ` headings and start `next = max(n)+1` (so blocks added by `/ds:review` or a prior analyze-pr run aren't clobbered; `F1` if none).
   - Item block shape (format owned by the `polish-findings` skill):
     ```
     ### F<next++> · analyze-pr · <category>
     - **Status:** open
     - **Item:** <one-line summary of the action / question>
     - **Location:** `path:line`            (if the analysis pinned one; else omit)
     - **Detail:** <1–2 lines: the why, or the answer for a question>
     - **Proposed change:** <concrete action, or (needs unpacking) for a smell>
     - **Resolution:** —
     ```
   - If there are no actionable items, omit the `## Action items` section entirely.

Mark `completed`.

**B.5: Append analysis to file.** Mark `📝 Append analysis to <INPUT_FILE>` as `in_progress`.

`Read` the current full content of `INPUT_FILE`. Construct the new content by appending:

```
<existing content>

---

<aggregated analysis from B.4>
```

`Write` the result back to `INPUT_FILE`. (Use `Read` + `Write` rather than `Edit` — `Edit`'s exact-string-replace is brittle on multi-line markdown.)

Mark `completed`.

**B.6: Print summary.** Mark `📋 Print summary` as `in_progress`.

Print as a regular text message:

```
> Wrote analysis to <INPUT_FILE>. Sections: <N>. Cross-cutting: <yes|no>.

<the `## Summary` block from B.4 inlined here so the user sees the gist without opening the file>
```

Mark `completed`. Done.

## Important Notes

- **Mode auto-detection** via `test -f` keeps the surface tiny: one argument, two modes. Single-token args like `INT-123` correctly fall through to prompt mode (no file by that name).
- **No commits / pushes / ticket-context writes.** Read-mostly. The only file this command writes is the user-named input file in MODE=file. Analysing is not ticket work.
- **Worktree-friendly:** uses `gh pr diff` rather than `git diff origin/<base>...HEAD`, so the user can be on any branch (including a teammate's PR checked out elsewhere).
- **Re-run safety:** Step B.1 only parses bullets above any existing `---` separator. Re-running on an already-analysed file will re-parse the same bullets and append a second analysis block — acceptable; user can prune. Refusing re-runs would be a future tweak.
- **Render results as text:** sub-agent responses must be printed by the main agent as text — users only see your text output, not `Agent` return values.
- **Parallel sub-agents:** in MODE=file, all section `Agent` calls go in a single tool-use turn so they run concurrently. Do not chain them.
- **Sub-agents are read-only:** the shared brief tells every analysis sub-agent not to modify files. The main agent does all file writes in B.5.
- **Hybrid output (file mode).** Below the `---`, the narrative answers stay the primary output; alongside them a `## Action items — /ds:analyze-pr — DATE` section emits shared-format item blocks for the *actionable* subset (`confident`/`smell`/`question`), so `/polish-findings <file>` can triage and apply them. The narrative is preserved in full — the items are an addition, not a replacement. Ids continue from the file's max `F<n>` so review + analyze-pr blocks coexist.
- **Still not `/ds:review`.** This command answers the questions the user brought; it does not run the seven-dimension audit or draft PR comments. The item blocks it emits are just its actionable conclusions rendered in the shared format.
