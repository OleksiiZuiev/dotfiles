---
description: Work on a Linear ticket — convention-checked plan, implement, one commit, push. Flags: +temp-worktree (isolate in a throwaway worktree and fold back), +auto-plan
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TaskCreate, TaskGet, TaskList, TaskUpdate, AskUserQuestion, EnterPlanMode
argument-hint: [+temp-worktree] [+auto-plan] [+fold-timeout=<Nm>] [extra context]
---

You are helping the user work on a Linear ticket. The command auto-detects whether to start
fresh or continue previous work, plans interactively, runs a convention-aware plan self-check
and a post-implementation convention check, and ends in exactly one commit that gets pushed.

By default the work happens **in the current checkout**. The `+temp-worktree` flag switches
on an isolation lifecycle: the implementation runs in a **private throwaway worktree** off
the feature branch and the resulting commit is **folded back** onto the live feature tip —
which lets several independent sessions work the same feature branch at once without
trampling each other's working tree, and tolerates another session committing in the meantime.

### Temp-Worktree Mode

{{#if $ARGUMENTS}}
{{!-- Isolation is opt-in. The + prefix avoids the Claude CLI consuming it as a CLI flag. --}}
If the text "{{$ARGUMENTS}}" contains `+temp-worktree`, then **temp-worktree mode is active**. In this mode:
- Step 2.9 creates a throwaway worktree, Step 5 folds the commit back onto the feature branch, and Step 6 tears the worktree down
- Strip `+temp-worktree` from the arguments before processing the rest as extra context
{{/if}}

**Unless that flag is present, temp-worktree mode is OFF — this is the default.** In default
mode you work directly in the current checkout: **skip Steps 2.9, 5 and 6 entirely**. There is
no worktree to create, no dependency sync to run, no fold-back to perform and nothing to tear
down — the Step 4 commit lands straight on the feature branch. `+fold-timeout` is meaningless
in default mode and is ignored (still strip it from the arguments).

### Auto-Plan Mode

{{#if $ARGUMENTS}}
{{!-- Check if +auto-plan flag is present in arguments. Uses + prefix instead of -- to avoid Claude CLI consuming it as a CLI flag --}}
If the text "{{$ARGUMENTS}}" contains `+auto-plan`, then **auto-plan mode is active**. In this mode:
- Do **NOT** call `EnterPlanMode` or `ExitPlanMode`. The `ExitPlanMode` tool always renders an approval prompt the user must clear, so calling it would defeat the flag — no prompt text can suppress that gate.
- Instead, write the full plan as a `## Plan` markdown section directly in your response (for transparency), then proceed straight to Step 2.9.
- Strip `+auto-plan` from the arguments before processing the rest as extra context
{{/if}}

## Your Task

### Step 0: Extract Ticket ID from Branch Name

Run `git branch --show-current` to get the current branch name. This is the **feature
branch** `F` — remember it; everything folds back onto it.

The branch follows the pattern `{type}/{ticket-id}-{slug}` (e.g., `feature/eng-123-add-user-auth`).
- Strip everything before the first `/`, then take the first two hyphen-separated segments as the ticket ID (e.g., `eng-123`)
- Convert to uppercase for display (e.g., `ENG-123`)

If extraction fails (branch doesn't match pattern), inform the user and exit:
> Could not extract ticket ID from branch name. Expected format: `{type}/{prefix-number}-{slug}` (e.g., `feature/eng-123-add-auth`).

Store the extracted ticket ID as `TICKET_ID` and the full branch name as `F`.

{{#if $ARGUMENTS}}
Additional context from user: "{{$ARGUMENTS}}"
{{/if}}

### Step 0.5: Pre-Seed Progress Checklist

**Before doing anything else**, pre-seed the following fixed checklist. When the `Task*`
tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`) are available, mirror the
checklist into them so it stays visible to the user; otherwise keep it in your own
messages. The checklist is mandatory and runs in order either way — the tools only make
it visible.

> Throughout this command, "mark X as `in_progress`/`completed`" means: update the
> checklist wherever you are keeping it. Never skip a step because a tool is missing, and
> never narrate which tracking tools this build has — just track the checklist and carry
> on.

Create these items (all with status `pending`). Items 1, 5 and 6 are **temp-worktree mode
only — omit them entirely in default mode**:
1. `🌳 Create isolated worktree` — see Step 2.9 *(temp-worktree mode only)*
2. `🔧 Implementation` — placeholder, will be replaced with plan tasks in Step 3
3. `🔎 Convention check (Sonnet sub-agent)` — see Step 3.5
4. `💾 Commit (exactly one commit)` — see Step 4
5. `🔀 Fold-back onto feature branch` — see Step 5 *(temp-worktree mode only)*
6. `🧹 Remove throwaway worktree` — see Step 6 *(temp-worktree mode only)*
7. `📝 Update ticket context: launch sub-agent` — see Step 7
8. `🚀 Push & PR` — see Step 8
9. `✅ Final summary` — see Step 9

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{TICKET_ID}.md`

### Working Location (`WT`)

Every step below refers to the working location as `WT`. What it points at depends on the mode:

- **Temp-worktree mode**: the throwaway worktree created in Step 2.9.
- **Default mode**: the absolute path of the **current working directory** — capture it once with
  `pwd` in Step 2.9.

Either way `git -C "{WT}" …` and `{WT}/<path>` are literally correct, so the steps read the same
in both modes.

### Critical Rules

- **In temp-worktree mode, the implementation worktree is sacred.** From Step 2.9 onward, ALL file
  changes (`Edit`/`Write`) use absolute paths **under the worktree `WT`**, and ALL git runs as
  `git -C "$WT" …`. **Never modify files under the current working directory** — that is the
  feature branch's own worktree and a concurrent session may be relying on it. The only
  things done in the current directory are the fold-back (Step 5) and cleanup (Step 6).
  In default mode this rule does not apply: `WT` *is* the current checkout, and edits, builds and
  the commit all happen there.
- **If auto-plan mode is active**: Do NOT call `EnterPlanMode` or `ExitPlanMode`. Write the full plan as a `## Plan` markdown section in your response, then proceed directly to Step 2.9. There is no approval gate — skipping it is the entire point of the flag.
- **If auto-plan mode is NOT active**: You MUST call `EnterPlanMode` before any implementation work, then write the plan and call `ExitPlanMode`. The user gets a permission prompt to review and approve. NEVER write or modify code without an approved plan.

### Step 1: Detect Phase

Check two signals to determine whether this is a fresh start or a continuation:

1. **Ticket context file**: Does `{context-path}/{TICKET_ID}.md` exist?
2. **Diff against main**: Run `git diff origin/main --stat` — are there changes on this branch?

**Phase detection logic:**
- **Fresh start** (no context file, OR context file exists but no diff against main): Go to Step 2A
- **Continuation** (context file exists AND diff against main exists): Go to Step 2B

Display the detected phase:
```
Ticket: {TICKET_ID}
Phase: Fresh start / Continuation
Context file: exists / not found
Branch diff: changes found / clean
```

### Step 2A: Fresh Start

#### 2A.1. Load Existing Ticket Context (if exists)

If `{context-path}/{TICKET_ID}.md` exists:
- Read and summarize previous sessions
- Use this context to inform planning (avoid re-exploring solved problems, build on previous decisions)

#### 2A.2. Fetch Linear Ticket Details

Use `mcp__claude_ai_Linear__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

Extract the ticket title, description, comments, and any linked resources.
Look for Notion page links in the description or comments and fetch those automatically.

#### 2A.3. Explore the Codebase

- Use Grep, Glob, and Read tools to understand relevant code areas
- Use the Task tool with subagent_type=Explore for broader context gathering
- Focus on areas mentioned in the ticket or related to the feature/fix

#### 2A.4. Ask Clarifying Questions

If requirements are unclear or multiple approaches are viable, use AskUserQuestion.
Don't assume implementation details not specified in the ticket.

#### 2A.5. Plan the Implementation

Create a detailed implementation plan covering:
- Overview of the change
- Files to be created/modified
- Implementation steps with rationale
- Testing approach
- Any risks or considerations

Do NOT include worktree or post-implementation steps in the plan — those are already pre-seeded in the checklist from Step 0.5 and will run automatically.

Before finalizing, apply the **Convention-Aware Plan Self-Check (Step 2.7)** to revise the plan so it names how it complies with the repo's design-level conventions.

- **If auto-plan mode is active**: write the plan as a `## Plan` markdown section in your response, skip `EnterPlanMode`/`ExitPlanMode` entirely, and proceed directly to Step 2.9.
- **Otherwise**: call `EnterPlanMode`, write the plan, then call `ExitPlanMode` and wait for user approval before continuing.

Then proceed to **Step 2.9** (shared flow).

### Step 2B: Continuation

#### 2B.1. Load Ticket Context (Required)

Read `{context-path}/{TICKET_ID}.md` and summarize previous sessions:
- Number of sessions
- Most recent session: date, branch, what was accomplished
- Key decisions made across sessions

Display the summary so the user can confirm the starting point.

#### 2B.2. Fetch Linear Ticket

Use `mcp__claude_ai_Linear__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

Extract and display:
- Title and current status
- Description (brief excerpt)
- Any new comments since last session
- Related/blocking issues

#### 2B.3. Determine Follow-Up Prompt

{{#if $ARGUMENTS}}
Follow-up change: "{{$ARGUMENTS}}"
{{else}}
No follow-up prompt provided. Use AskUserQuestion to ask: "What would you like to work on next for this ticket?"
{{/if}}

#### 2B.4. Plan the Follow-Up Change

Plan the follow-up change. The plan should:
- Build on what was done in previous sessions (don't redo completed work)
- Reference specific decisions from ticket context
- Include the specific follow-up change
- Include files to be created/modified
- Include testing approach

Do NOT include worktree or post-implementation steps in the plan — those are already pre-seeded in the checklist from Step 0.5.

Before finalizing, apply the **Convention-Aware Plan Self-Check (Step 2.7)** to revise the plan so it names how it complies with the repo's design-level conventions.

- **If auto-plan mode is active**: write the plan as a `## Plan` markdown section in your response, skip `EnterPlanMode`/`ExitPlanMode` entirely, and proceed directly to Step 2.9.
- **Otherwise**: call `EnterPlanMode`, write the plan, then call `ExitPlanMode` and wait for user approval before continuing.

Then proceed to **Step 2.9** (shared flow).

### Step 2.7: Convention-Aware Plan Self-Check

Applies to both **Step 2A.5** and **Step 2B.4**, in interactive and `+auto-plan` modes. Run it on the drafted plan *before* presenting it — before `ExitPlanMode`, or before writing the `## Plan` section under auto-plan.

The goal: make the plan demonstrably comply with the conventions of the repo you're working in — especially the **design-level** rules that are expensive to fix once the code exists. Scale the effort to the size of the change (a one-line follow-up needs little; a new component needs more).

1. Identify the areas/files the plan will create or touch.
2. Discover the conventions that apply to them: the user's global `~/.claude/CLAUDE.md`, plus every `AGENTS.md` and `CLAUDE.md` found in each of those directories up to the repo root (most-specific first; a nested file refines the root).
3. Also read the **repo-keyed steering overlay** if present — your personal, user-level rules for this repo (maintained by `/ds:distill`). Resolve `{repo-key}` as the basename of the main repo root: `basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"` (worktree-stable — `--git-common-dir` always points at the main repo's `.git`). Read `~/.claude/overlays/{repo-key}.md` and fold its `## Plan directives` bullets into this self-check alongside the discovered conventions. If the file or that section is absent, proceed with just the discovered conventions.
4. Revise the plan so it **names** how it complies with the design-level rules, rather than restating the rule. Concretely:
   - Name the methods/functions you'll add and keep their scope tight — avoid one long method where the conventions favor small ones.
   - State **where** new code lands — prefer a component specific to this change over bloating a large shared component, and say which.
   - Call out any other structural convention the change has to honor.
5. The mechanical rules (comment style, naming, dead-history comments) are **not** the focus here — those are enforced after implementation by the Step 3.5 convention check. Keep this step about structure and design.

Then continue with the auto-plan / `EnterPlanMode` finalization in the calling step.

### Step 2.9: Establish the Working Location

Do this AFTER plan approval and BEFORE any file changes.

**Default mode (no `+temp-worktree`):** run `pwd` and store the result as `WT` — you work in the
current checkout. Confirm you are still on the feature branch `F`. A **dirty working tree is
fine** here (there is no fold-back to protect); just be careful to commit only your own changes
in Step 4. There is no checklist item for this — go straight to Step 3.

**Everything below is temp-worktree mode only.**

Mark `🌳 Create isolated worktree` as `in_progress`.

**Pre-flight (in the current directory — the feature branch's worktree):**
- Confirm you are on the feature branch `F` (it must match `{type}/{ticket}-{slug}`).
- Confirm the working tree is clean: run `git status --porcelain`. If there is any output, **stop** and tell the user to commit or stash first — the fold-back in Step 5 cherry-picks onto this worktree and requires it clean.

**Create the throwaway worktree:**
1. Generate a short random suffix: run `openssl rand -hex 3` (fall back to `echo $RANDOM` if `openssl` is unavailable). Call it `SUFFIX`.
2. Temp branch `T = "{F}-{SUFFIX}"` (e.g. `feature/eng-123-add-auth-a1b2c3`). Two concurrent sessions get different suffixes, so they never collide on branch name or path.
3. Compute the worktree path `WT`:
   - Run `git rev-parse --path-format=absolute --git-common-dir`. Its parent directory is the **main repo root** (this works whether you are in the main repo or a worktree).
   - `WT = "{parent-of-main-repo-root}/{main-repo-name}-worktrees/{T-without-its-type-prefix}"`, i.e. strip everything up to and including the first `/` of `T` for the directory name. This matches the `start-worktree` convention.
4. Create it off the current feature tip: `git worktree add -b "{T}" "{WT}" HEAD`.
   - Do **not** record this worktree in the cd-repo / lclaude picker — it is transparent plumbing that will be removed in Step 6.
5. If creation fails, inform the user and exit.

Remember `F`, `T`, and `WT` for the rest of the session. Mark the item `completed`.

### Step 3: Implement the Plan (in `WT`)

In the checklist, replace the `🔧 Implementation` placeholder with the plan's implementation steps — one item each.

Implement the plan directly (no sub-agent — you have full context from planning), **entirely inside `WT`**:
- File edits: absolute paths under `WT`.
- Git: `git -C "$WT" …`.
- Build/test: invoke the tool with its directory flag pointed at `WT`
  (e.g. `uv run --directory "{WT}/<subdir>" pytest …`, `dotnet test "{WT}/..."`,
  `npm --prefix "{WT}" test`, `go test -C "{WT}" ./...`). Do not `cd`.

**Temp-worktree mode only** — a throwaway worktree starts empty of everything but tracked files:
- **Read each file at its `{WT}` path before editing** — planning-phase reads were against a
  different worktree path, so the Edit tool needs a fresh Read of the `{WT}` copy.
- **Install deps first — a fresh worktree has none.** A newly created worktree shares no
  `.venv` / `node_modules` / build outputs with the main checkout. Before building or
  testing, install/sync dependencies *in the worktree* (point at the subproject dir as
  needed):
  - Python / uv workspace: `uv sync --all-packages --directory "{WT}/<subdir>"`. A plain
    `uv run` builds a venv that is **missing the workspace-member editables**, so
    `pytest`/`ty` fail with `ModuleNotFoundError` and a flood of unresolved-imports.
  - Node: `npm --prefix "{WT}" install`.   .NET: `dotnet restore`.
  If lint/type/test report mass unresolved-import / module-not-found errors, that is the
  missing install — **not** a code defect. Sync, then re-run.

1. Execute each implementation task sequentially
2. Run tests and verify as you go (against `WT`)
3. Mark each implementation item `completed` as you go
4. **Then continue to the post-implementation steps.** Do NOT stop after implementation.

## Post-Implementation Steps

Work through these in order, marking each `in_progress` when starting and `completed` when done. All commit and git operations target `WT`.

### Step 3.5: Convention Compliance Check (Sonnet sub-agent)

Mark `🔎 Convention check (Sonnet sub-agent)` as `in_progress`. This runs after implementation and **before** the commit, so its fixes land in the single Step 4 commit.

Launch a `Task` sub-agent with `model: "sonnet"` to check the freshly written code against **your own conventions** and auto-apply the safe subset of fixes. The rules are **not hardcoded here** — they are read from two sources: the conventions that already apply to the changed files, **plus** your repo-keyed steering overlay's `## Enforced` rules (`~/.claude/overlays/{repo-key}.md`, maintained by `/ds:distill`). The overlay carries the recurring, already-stated-but-ignored mechanical rules that most need a hard check. Kept deliberately narrower than `/ds:review`: it enforces mechanical, locally-fixable rules only, never a full audit.

**Sub-agent prompt:**
> You are checking uncommitted changes in a git worktree against the repository's own conventions and applying only the safe, mechanical fixes.
>
> 1. List the changed files: `git -C "{WT}" diff --name-only HEAD`.
> 2. Discover the conventions that apply to those files: the user's global `~/.claude/CLAUDE.md`, plus every `AGENTS.md` and `CLAUDE.md` found in each changed file's directory and its ancestors up to the repo root. Read them all (most-specific first; a nested file refines the root).
> 2b. Also read the repo-keyed steering overlay if present: compute `{repo-key}` as `basename "$(dirname "$(git -C "{WT}" rev-parse --path-format=absolute --git-common-dir)")"`, then read `~/.claude/overlays/{repo-key}.md`. Treat every bullet under its `## Enforced` section as a **priority mechanical rule** for this repo — enforce it in addition to the mechanical subset inferred from the conventions above. If the file or that section is absent, skip.
> 3. Read the actual diff: `git -C "{WT}" diff HEAD`.
> 4. From those conventions **and the overlay's `## Enforced` rules**, enforce **only the mechanical, locally-fixable rules** — the kind that can be safely corrected in a finished diff without redesign. Examples of what qualifies: comments that merely restate the code, refactoring-history comments ("refactored from…", "now uses…", "previously…"), trivial naming/formatting deviations the conventions explicitly call out. **Do NOT** make design-level changes (decomposition, moving logic between components, method-splitting) — those are handled at planning time, not here.
> 5. Apply the qualifying fixes directly to the files (absolute paths under `{WT}`; `Read` each file before `Edit`). Don't touch anything a rule doesn't clearly cover.
> 6. Be conservative: when a rule needs judgment or a fix would amount to a rewrite, leave it and mention it rather than applying it.
> 7. Return a short bullet list of what you changed (file + one-line reason), or "no changes — diff already complies".

**Sub-agent allowed tools:** `Read, Edit, Grep, Glob, Bash(git *)`

Record the sub-agent's summary (count of fixes, or "clean") for the final summary, then mark the item `completed`.

### Step 4: Commit (exactly one commit)

Mark `💾 Commit (exactly one commit)` as `in_progress`.

Make **exactly one** commit in `WT`, then capture its SHA:

1. Run `git -C "{WT}" status` and `git -C "{WT}" diff` to see all changes.
2. Run `git -C "{WT}" log --oneline -5` to match the recent commit message style.
3. Stage the relevant files: `git -C "{WT}" add <specific files>` (avoid .env, credentials, etc.).
   In **default mode** the tree may have been dirty before you started — stage **only** the files
   you changed in Step 3 and leave any pre-existing modifications untouched, so the one commit
   cannot swallow unrelated work. Never `git add -A` / `git add .`.
4. Commit using a HEREDOC (use the `Co-Authored-By` trailer your environment/harness specifies; the line below is the default):
   ```bash
   git -C "{WT}" commit -m "$(cat <<'EOF'
   <conventional commit message>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
5. Capture the full SHA: `git -C "{WT}" rev-parse HEAD`. Store it as `SHA`.
6. Do NOT push.

Mark the item `completed`.

### Step 5: Fold-Back onto the Feature Branch

**Temp-worktree mode only.** In default mode the Step 4 commit is already on `F` — there is
nothing to fold back. Skip to Step 7. (`SHA` is then the commit on `F`; only a Step 8 rebase
can still rewrite it, which is why Step 8 captures `PUSHED_SHA` separately.)

Mark `🔀 Fold-back onto feature branch` as `in_progress`.

This runs in the **current directory** (the feature branch `F`). It cherry-picks `SHA` onto
the *live* feature tip, so if another session committed since this session started, you land
on top of their commit.

#### Step 5.1: Check Worktree Readiness

Before cherry-picking, verify the primary worktree is in a state that allows it. All checks
run in the current directory (the feature branch worktree).

**The worktree is ready when ALL of these hold:**
- No in-progress sequencer operation: `git rev-parse -q --verify CHERRY_PICK_HEAD`,
  `git rev-parse -q --verify MERGE_HEAD`, and `git rev-parse -q --verify REVERT_HEAD` all
  fail (refs absent), AND the paths returned by `git rev-parse --git-path rebase-merge`
  and `git rev-parse --git-path rebase-apply` do not exist on disk.
- Working tree clean: `git status --porcelain` is empty.
- No lock: `$(git rev-parse --git-dir)/index.lock` does not exist.

**Decision tree:**

1. **Ready** → proceed directly to Step 5.2.

2. **Sequencer op in progress** (or `index.lock` present) — a concurrent session is
   mid-operation. **Wait without interfering.** Start a background bounded poll using
   `run_in_background=true` with an `until`-loop that re-checks readiness every ~10 s and
   exits once the worktree is ready or the timeout elapses. Tell the user what's blocking
   (e.g., "Waiting for the feature worktree to finish its in-progress cherry-pick…").
   Default timeout: **15 minutes**; the `+fold-timeout=<N>m` argument (stripped before
   processing, same as `+auto-plan`) overrides it. Do NOT abort, `--continue`, or otherwise
   touch the other session's operation. Do NOT force-remove `index.lock`.
   - On the background-poll notification: re-check readiness immediately (the gap between
     wait-clearing and cherry-pick is a new race window), then:
     - If ready → proceed to Step 5.2.
     - If timed out → go to the timeout case below.

3. **Working tree dirty with no sequencer op and no lock** — this is not a transient state
   to outlast. **Stop and report a recovery handle:**
   ```
   Fold-back blocked: the primary worktree has uncommitted changes and no in-progress operation.
   Commit:      {SHA}    (verified, on temp branch)
   Temp branch: {T}
   Worktree:    {WT}
   Commit or stash the uncommitted changes on {F}, then cherry-pick {SHA} onto {F} manually,
   or re-run /ds:work-on once the working tree is clean.
   ```
   Do NOT remove the throwaway worktree. Skip Steps 6–8; go to Step 9 and report the
   partial outcome.

4. **Timeout** — stop cleanly. Do NOT remove the throwaway worktree. Skip Steps 6–8; go to
   Step 9 and report a recovery handle:
   ```
   Fold-back timed out waiting for the feature worktree to free up.
   Commit:       {SHA}            (verified, on temp branch)
   Temp branch:  {T}
   Worktree:     {WT}
   The primary worktree is busy (concurrent {cherry-pick|merge|rebase} in progress).
   Re-run /ds:work-on (it will resume the fold-back) once it's clear, or cherry-pick
   {SHA} onto {F} manually.
   ```

#### Step 5.2: Cherry-Pick

1. Cherry-pick: `git cherry-pick "{SHA}"`.
   - **Index-lock contention** (output mentions `index.lock` / "another git process"): a
     session started folding back in the narrow window since the readiness check. Retry the
     readiness check (up to ~5 attempts, ~10 s apart) before retrying the cherry-pick. Do
     not force-remove the lock.
   - **Clean success**: the commit is now on `F`. Continue to Step 6.
   - **Conflict**: resolve it **inline**:
     - List conflicts: `git diff --name-only --diff-filter=U`.
     - For each, read the file, resolve the conflict markers honoring the intent of BOTH
       sides (your change and whatever the other session landed), then `git add <file>`.
     - Finalize: `git cherry-pick --continue` (use a HEREDOC message if an editor would open).
   - **Unresolvable conflict**: run `git cherry-pick --abort`, then **STOP without removing
     the worktree**. Report a recovery handle so the user can finish manually:
     ```
     Fold-back blocked by an unresolvable conflict.
     Commit:      {SHA}
     Temp branch: {T}
     Worktree:    {WT}
     Resolve manually (e.g. `git cherry-pick {SHA}` and fix), or rebase {T} onto {F}.
     ```
     Skip Steps 6–8; go to Step 9 and report the partial outcome.

> **Note:** Step 8 runs a `fetch → rebase → push` in this same primary worktree and has the
> same concurrency exposure to an in-progress sequencer operation. Consider applying the
> readiness check from Step 5.1 there as well if needed.

Mark the item `completed` once the commit is on `F`.

### Step 6: Remove the Throwaway Worktree

**Temp-worktree mode only.** In default mode there is no worktree to remove — skip to Step 7.

Mark `🧹 Remove throwaway worktree` as `in_progress`. Only run this after a successful fold-back.

Tear down the worktree in one call:

- `worktree-teardown "{WT}" "{T}"`

This removes the directory (a coreutils `rm -rf` that clears the pnpm/`node_modules`
tree and long paths where `git worktree remove --force` fails "Directory not empty" on
Windows), prunes the now-stale registration, then deletes the temp branch `{T}` — in that
order, because git refuses to delete a branch still registered to a worktree. It is a
`bash.d` helper, not a raw `rm -rf`, precisely so the destructive-command approval prompt
(which fires even under auto permission mode) never sees an `rm`, and teardown runs
unattended.

Mark the item `completed`.

### Step 7: Update Ticket Context

Mark `📝 Update ticket context: launch sub-agent` as `in_progress`.

Use the Task tool with a subagent (`model: "haiku"`) to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{TICKET_ID}`
- Context file path
- Branch name (`F`)
- Repository name
- What was accomplished
- Key decisions made — for each, include the **rationale (the *why*)** when it is clear from the session: the option chosen, the main alternative rejected, and the reason. Where the rationale isn't clear, pass the decision alone — do **not** invent one.
- Files changed
- The Step 3.5 outcome, as a line of its own: `Convention check: N fixes applied` or `Convention check: clean`. A later `/ds:review2` reads this to learn that the mechanical conventions were already enforced against this diff, and narrows its Consistency reviewer to structural compliance instead of re-checking the same rules.

The subagent should record the convention-check line under the session's `#### Accomplished` bullets, and otherwise append a new session entry following the existing document format — or, when the context file does not exist yet, create it from the template in the `ticket-context` skill (`~/.claude/skills/ticket-context/SKILL.md`). Record each decision in the template's `#### Key Decisions` → `- {decision}: {rationale}` form. When no rationale was supplied for a decision, record just the decision without a fabricated reason.

Mark the item `completed`.

### Step 8: Push & Create/Update PR

Mark `🚀 Push & PR` as `in_progress`.

Your commit is on the *local* feature tip (put there by Step 5's fold-back in temp-worktree
mode, or directly by Step 4 in default mode), but another session may have **pushed** to the
remote `{F}` in the meantime. Integrate the remote before pushing:

1. Fetch the remote tip: `git fetch origin "{F}"`.
2. If local has diverged from `origin/{F}`, rebase your folded-back commit(s) on top:
   `git rebase "origin/{F}"`.
   - **Clean** → continue.
   - **Conflict** → resolve inline honoring BOTH sides (same approach as Step 5), then
     `git rebase --continue`. If unresolvable, `git rebase --abort` and STOP with a
     recovery handle (the commit `SHA`, branch `{F}`); skip to Step 9 and report.
3. Push: `git push -u origin "{F}"`.
   - If still **rejected (non-fast-forward)** — a session pushed inside the race window —
     repeat fetch → rebase → push (up to ~3 attempts). **Never** use `--force`.
   - On success, capture the pushed commit for the summary: `PUSHED_SHA = git rev-parse HEAD`
     (in the current dir, like the `git fetch`/`git push` above) and
     `COMMIT_URL = "$(gh repo view --json url -q .url)/commit/{PUSHED_SHA}"`. Any rebase above
     — and, in temp-worktree mode, the Step 5 cherry-pick — rewrites the SHA, so `PUSHED_SHA`,
     not the Step 4 `SHA`, is the commit that actually landed on the remote.
4. Your Step 3 verification predates any commits the rebase pulled in (usually unrelated
   areas). CI on the PR is the backstop for the integrated tip; optionally re-run the
   targeted tests if the rebase touched the same area you changed.
5. Check if a PR already exists: `gh pr view --json url,number,baseRefName` (exit code 0 = exists).
6. **If no PR exists**: launch a Task sub-agent (`model: "sonnet"`) to create a draft PR.

**Sub-agent prompt:**
> Create a draft PR for the current branch, automatically detecting whether it is stacked on another feature branch.
>
> 1. Get the ticket ID from the branch name: strip everything before the first `/`, take the first two hyphen-separated segments, uppercase them (e.g., `feature/eng-123-foo` → `ENG-123`)
> 2. Fetch the Linear ticket using `mcp__claude_ai_Linear__get_issue` with the ticket ID and `includeRelations: true`
> 3. Read the ticket context file at `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` if it exists
> 4. Run `git log --oneline origin/main..HEAD` and `git diff origin/main...HEAD --stat` to understand all changes
> 4b. Detect the base branch by running `stack-parent` (a `bash.d` helper; `stack-parent --help` states the rule).
>    It prints `<parent-branch> <pr-number>` when the branch is stacked, `<parent-branch> -` when that
>    parent has no open PR, and nothing (exit 1) when the branch is based on main.
>    - **Nothing** → `BASE_BRANCH=main`; go to step 5.
>    - **`<parent> <num>`** → `BASE_BRANCH=<parent>`, `PARENT_PR_NUM=<num>`; go to steps 5b–5d.
>    - **`<parent> -`** → warn: "Parent branch `<parent>` has no open PR — create one first, then re-run to link the stack." Then do step 5 with `--base <parent>` added (no stacked-PR notice, there is no parent PR to reference) and skip 5b–5d.
> 5. **Base is main** — create a standard draft PR:
>    `gh pr create --draft` with title (short summary from ticket title and changes) and body with sections: Summary, Linear ticket link, Test plan. Use HEREDOC for the body.
> 5b. **Stacked PR flow** — ensure the `gh-stack` extension is installed:
>    `gh extension list | grep -q gh-stack || gh extension install github/gh-stack`
> 5c. Create the PR targeting the parent branch:
>    `gh pr create --draft --base "$BASE_BRANCH"` with title and body. Open the body with the stacked-PR notice:
>    `> ⚡ Stacked on #PARENT_PR_NUM (\`$BASE_BRANCH\`) — will retarget to main when that branch merges.`
>    Followed by the standard sections: Summary, Linear ticket link, Test plan. Use HEREDOC for the body.
>    Create the PR here rather than leaving it to `gh stack link` in 5d: left to itself the extension opens the PR with its own generated title and not as a draft.
> 5d. Register the stack with the GitHub native stacked-PR system:
>    ```bash
>    GH_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" gh stack link "$BASE_BRANCH" "$(git branch --show-current)"
>    ```
>    `GH_REPO` is required, not decorative: the extension parses `origin` itself and rejects an SSH host alias (`git@github-work:owner/repo.git`) that `gh` core resolves fine, dying with "none of the git remotes … point to a known GitHub host".
>    Linking also pushes every branch in the stack to `origin`. That is harmless here because Step 8.3 already pushed this branch and the parent has an open PR, so both are on the remote already.
>    **A link failure is not fatal** — the PR exists and already targets the right base. Report the error and carry on.
>    Capture and report the output (it confirms stack registration).
> 6. Return the PR URL and number (and the `gh stack link` result if this was a stacked PR)

**Sub-agent allowed tools:** `Bash, mcp__claude_ai_Linear__get_issue, Read, Glob`
(`Bash` unrestricted: `stack-parent` and the `GH_REPO=… gh …` prefix in 5d match no narrower
`Bash(...)` pattern.)

7. **If PR already exists**: note the PR URL and number from the `gh pr view` output. If its
   `baseRefName` is not `main` and `stack-parent` names a parent, run step 5d's `gh stack link` as
   well, so a re-run on a stacked branch converges instead of leaving the stack unregistered.

Store the results (PR URL and number, plus `PUSHED_SHA` and `COMMIT_URL`) for the final summary.

Mark the item `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress`.

Show what was implemented:
```
Work completed: {TICKET_ID}
Phase: Fresh start / Continuation
Mode: in-place / temp-worktree
Change: [brief description of what was done]
Files modified: [count]
Convention check: N fixes applied / clean
Worktree: {WT} → removed / kept (fold-back blocked)   [omit this line in default mode]
Fold-back: clean / conflict resolved / blocked        [omit this line in default mode]
Committed: {PUSHED_SHA} — {COMMIT_URL}  /  {SHA} (worktree, not pushed — fold-back blocked)
Ticket context updated: yes/no
PR: created #N <url> (draft) / pushed to existing #N <url> / not pushed (fold-back blocked)
Stack: based on {parent} #N — linked / link failed: {error}      [omit this line when based on main]
```

Mark the item `completed`.

Suggest next steps:
- `/ds:work-on <next change>` if more work needed

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches
- Either mode leaves the feature branch `F` with exactly one new commit and no leftover plumbing — in temp-worktree mode the isolation is invisible once it's done
- Reach for `+temp-worktree` when another session is (or may be) working the same feature branch; for a solo session the default in-place mode does the same work without the worktree setup, dependency sync, file re-reads and fold-back
