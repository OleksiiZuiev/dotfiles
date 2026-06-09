---
description: Work on a Linear ticket in an isolated worktree, then fold the commit back onto the feature branch — lets multiple sessions share one branch without colliding. Flags: +auto-plan
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, EnterPlanMode, TodoWrite
argument-hint: [+auto-plan] [extra context]
---

You are helping the user work on a Linear ticket. This is the **v2** of `/ds:work-on`:
the implementation happens in a **private throwaway worktree** off the feature branch, and
the single resulting commit is **folded back** onto the live feature tip. This lets several
independent sessions work the same feature branch at once without trampling each other's
working tree, and tolerates another session committing in the meantime.

It is otherwise the same workflow as `/ds:work-on`: auto-detects fresh start vs continuation,
plans interactively, then runs the post-implementation steps.

### Auto-Plan Mode

{{#if $ARGUMENTS}}
{{!-- Check if +auto-plan flag is present in arguments. Uses + prefix instead of -- to avoid Claude CLI consuming it as a CLI flag --}}
If the text "{{$ARGUMENTS}}" contains `+auto-plan`, then **auto-plan mode is active**. In this mode:
- Do **NOT** call `EnterPlanMode` or `ExitPlanMode`. The `ExitPlanMode` tool always renders an approval prompt the user must clear, so calling it would defeat the flag — no prompt text can suppress that gate.
- Instead, write the full plan as a `## Plan` markdown section directly in your response (for transparency), then proceed straight to worktree creation (Step 2.9).
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

**Before doing anything else**, pre-seed the following fixed checklist using whatever
progress-tracking tool this build exposes — `TodoWrite` if available, otherwise the
`TaskCreate`/`TaskUpdate` family (recent builds ship Task* instead of TodoWrite). If
neither is available, track the checklist inline in your messages. Either way these
steps are mandatory and run in order; the tool is only for visibility.

> Throughout this command, "mark X as in_progress/completed" and "use TodoWrite to …"
> mean: update whichever tracking tool you pre-seeded here (or your inline list). Never
> skip a step just because a specific tool name is unavailable.

Create these items (all with status `pending`):
1. `🌳 Create isolated worktree` — see Step 2.9
2. `🔧 Implementation` — placeholder, will be replaced with plan tasks in Step 3
3. `💾 Commit (one commit in the worktree)` — see Step 4
4. `🔀 Fold-back onto feature branch` — see Step 5
5. `🧹 Remove throwaway worktree` — see Step 6
6. `📝 Update ticket context: launch sub-agent` — see Step 7
7. `🚀 Push & PR` — see Step 8
8. `✅ Final summary` — see Step 9

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{TICKET_ID}.md`

### Critical Rules

- **The implementation worktree is sacred.** From Step 2.9 onward, ALL file changes
  (`Edit`/`Write`) use absolute paths **under the worktree `WT`**, and ALL git runs as
  `git -C "$WT" …`. **Never modify files under the current working directory** — that is the
  feature branch's own worktree and a concurrent session may be relying on it. The only
  things done in the current directory are the fold-back (Step 5) and cleanup (Step 6).
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

Use `mcp__linear-server__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

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

Do NOT include worktree or post-implementation steps in the plan — those are already pre-seeded in the todo list from Step 0.5 and will run automatically.

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

Use `mcp__linear-server__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

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

Do NOT include worktree or post-implementation steps in the plan — those are already pre-seeded in the todo list from Step 0.5.

- **If auto-plan mode is active**: write the plan as a `## Plan` markdown section in your response, skip `EnterPlanMode`/`ExitPlanMode` entirely, and proceed directly to Step 2.9.
- **Otherwise**: call `EnterPlanMode`, write the plan, then call `ExitPlanMode` and wait for user approval before continuing.

Then proceed to **Step 2.9** (shared flow).

### Step 2.9: Create the Isolated Worktree

Mark `🌳 Create isolated worktree` as `in_progress` via your tracking tool. Do this AFTER plan approval and BEFORE any file changes.

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

Remember `F`, `T`, and `WT` for the rest of the session. Mark the todo `completed`.

### Step 3: Implement the Plan (in the worktree)

Using your tracking tool, replace the `🔧 Implementation` placeholder with specific implementation tasks from the plan. Each task should be a separate item.

Implement the plan directly (no sub-agent — you have full context from planning), but **entirely inside the worktree `WT`**:
- File edits: absolute paths under `WT`. **Read each file at its `{WT}` path before
  editing** — planning-phase reads were against a different worktree path, so the Edit
  tool needs a fresh Read of the `{WT}` copy.
- Git: `git -C "$WT" …`.
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
- Build/test: invoke the tool with its directory flag pointed at `WT`
  (e.g. `uv run --directory "{WT}/<subdir>" pytest …`, `dotnet test "{WT}/..."`,
  `npm --prefix "{WT}" test`, `go test -C "{WT}" ./...`). Do not `cd`.

1. Execute each implementation task sequentially
2. Run tests and verify as you go (against `WT`)
3. Using your tracking tool, mark each implementation task as `completed` as you go
4. **Then continue to the post-implementation steps.** Do NOT stop after implementation.

## Post-Implementation Steps

Work through these in order — using your tracking tool, mark each `in_progress` when starting and `completed` when done. All commit and git operations target the worktree `WT`.

### Step 4: Commit (one commit in the worktree)

Mark `💾 Commit (one commit in the worktree)` as `in_progress` via your tracking tool.

Make **exactly one** commit in the worktree, then capture its SHA:

1. Run `git -C "{WT}" status` and `git -C "{WT}" diff` to see all changes.
2. Run `git -C "{WT}" log --oneline -5` to match the recent commit message style.
3. Stage the relevant files: `git -C "{WT}" add <specific files>` (avoid .env, credentials, etc.).
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

Mark the todo `completed`.

### Step 5: Fold-Back onto the Feature Branch

Mark `🔀 Fold-back onto feature branch` as `in_progress` via your tracking tool.

This runs in the **current directory** (the feature branch `F`). It cherry-picks `SHA` onto
the *live* feature tip, so if another session committed since this session started, you land
on top of their commit.

1. Cherry-pick: `git cherry-pick "{SHA}"`.
   - **Index-lock contention** (output mentions `index.lock` / "another git process"): another session is folding back right now. Wait briefly and retry — up to ~5 attempts. Do not force-remove the lock.
   - **Clean success**: the commit is now on `F`. Continue to Step 6.
   - **Conflict**: resolve it **inline**:
     - List conflicts: `git diff --name-only --diff-filter=U`.
     - For each, read the file, resolve the conflict markers honoring the intent of BOTH sides (your change and whatever the other session landed), then `git add <file>`.
     - Finalize: `git cherry-pick --continue` (use a HEREDOC message if an editor would open).
   - **Unresolvable conflict**: run `git cherry-pick --abort`, then **STOP without removing the worktree**. Report a recovery handle so the user can finish manually:
     ```
     Fold-back blocked by an unresolvable conflict.
     Commit:   {SHA}
     Temp branch: {T}
     Worktree:    {WT}
     Resolve manually (e.g. `git cherry-pick {SHA}` and fix), or rebase {T} onto {F}.
     ```
     Skip Steps 6–8; go to Step 9 and report the partial outcome.

Mark the todo `completed` once the commit is on `F`.

### Step 6: Remove the Throwaway Worktree

Mark `🧹 Remove throwaway worktree` as `in_progress` via your tracking tool. Only run this after a successful fold-back.

1. Remove the worktree (long-path aware, with a force fallback):
   - `git -c core.longpaths=true worktree remove "{WT}"`
   - if that fails: `git -c core.longpaths=true worktree remove --force "{WT}"`
2. Delete the temp branch: `git branch -D "{T}"`.
3. Prune stale references: `git worktree prune`.

Mark the todo `completed`.

### Step 7: Update Ticket Context

Mark `📝 Update ticket context: launch sub-agent` as `in_progress` via your tracking tool.

Use the Task tool with a subagent (`model: "haiku"`) to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{TICKET_ID}`
- Context file path
- Branch name (`F`)
- Repository name
- What was accomplished
- Key decisions made
- Files changed

The subagent should append a new session entry following the existing document format.

Mark the todo `completed`.

### Step 8: Push & Create/Update PR

Mark `🚀 Push & PR` as `in_progress` via your tracking tool.

The fold-back (Step 5) put your commit on the *local* feature tip, but another session
may have **pushed** to the remote `{F}` in the meantime (Step 5 only handles a *local*
concurrent commit). Integrate the remote before pushing:

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
     `COMMIT_URL = "$(gh repo view --json url -q .url)/commit/{PUSHED_SHA}"`. The cherry-pick
     in Step 5 (and any rebase above) rewrites the SHA, so `PUSHED_SHA` — not the worktree
     `SHA` from Step 4 — is the commit that actually landed on the remote.
4. Your Step 3 verification predates any commits the rebase pulled in (usually unrelated
   areas). CI on the PR is the backstop for the integrated tip; optionally re-run the
   targeted tests if the rebase touched the same area you changed.
5. Check if a PR already exists: `gh pr view --json url,number` (exit code 0 = exists).
6. **If no PR exists**: launch a Task sub-agent (`model: "sonnet"`) to create a draft PR.

**Sub-agent prompt:**
> Create a draft PR for the current branch.
>
> 1. Get the ticket ID from the branch name: strip everything before the first `/`, take the first two hyphen-separated segments, uppercase them (e.g., `feature/eng-123-foo` → `ENG-123`)
> 2. Fetch the Linear ticket using `mcp__linear-server__get_issue` with the ticket ID and `includeRelations: true`
> 3. Read the ticket context file at `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` if it exists
> 4. Run `git log --oneline origin/main..HEAD` and `git diff origin/main...HEAD --stat` to understand all changes
> 5. Create a draft PR using `gh pr create --draft` with:
>    - Title: short summary derived from the ticket title and changes
>    - Body: structured description with sections for Summary, Linear ticket link, and Test plan
>    - Use HEREDOC for the body to preserve formatting
> 6. Return the PR URL and number

**Sub-agent allowed tools:** `Bash(git *), Bash(gh *), mcp__linear-server__get_issue, Read, Glob`

7. **If PR already exists**: just note the PR URL and number from the `gh pr view` output.

Store the results (PR URL and number, plus `PUSHED_SHA` and `COMMIT_URL`) for the final summary.

Mark the todo `completed`.

### Step 9: Final Summary

Mark `✅ Final summary` as `in_progress` via your tracking tool.

Show what was implemented:
```
Work completed: {TICKET_ID}
Phase: Fresh start / Continuation
Change: [brief description of what was done]
Files modified: [count]
Worktree: {WT} → removed / kept (fold-back blocked)
Fold-back: clean / conflict resolved / blocked
Committed: {PUSHED_SHA} — {COMMIT_URL}  /  {SHA} (worktree, not pushed — fold-back blocked)
Ticket context updated: yes/no
PR: created #N <url> (draft) / pushed to existing #N <url> / not pushed (fold-back blocked)
```

Mark the todo `completed`.

Suggest next steps:
- `/ds:work-on2 <next change>` if more work needed

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches
- This command leaves the feature branch `F` with exactly one new commit and no leftover worktree — the isolation is invisible once it's done
