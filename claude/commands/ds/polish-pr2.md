---
description: Address review comments on a PR in an isolated worktree, then fold the commits back onto the feature branch — lets multiple sessions share one branch without colliding.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite, AskUserQuestion
argument-hint: [<pr-number>]
---

You are addressing human review comments on a pull request. This is the **v2** of
`/ds:polish-pr`: the implementation (file edits + commits) happens in a **private throwaway
worktree** off the feature branch, and the resulting commits are **folded back** onto the live
feature tip. This lets several independent sessions polish the same feature branch at once
without trampling each other's working tree, and tolerates another session committing in the
meantime.

It is otherwise the same workflow as `/ds:polish-pr`: fetch comments, assess each on merit
(thinking-buddy posture), implement approved fixes, reply to threads, push, and optionally
update the PR description.

## The Central Adaptation (read this first)

In `/ds:polish-pr` (v1) each comment is handled as **edit → commit → reply** in one loop, and
the push happens at the end. In v2 the fold-back's **cherry-pick** (and any push-time
**rebase**) **rewrites the commit SHAs**, so a reply posted against a worktree SHA would point
at a commit that no longer exists on the branch. Therefore v2 **defers ALL GitHub replies**
(fixed / skipped / dismissed) until **after fold-back + push**, when the final SHAs are known.

The flow is split into three zones:
- **Before the worktree (current dir, read-only):** detect PR, fetch comments + thread IDs,
  display summary, scope assessment, triage, per-comment plan + approval. No edits.
- **Inside the worktree:** implement each approved fix, one commit per fix. No replies, no push.
- **After the worktree (current dir):** fold-back → remove worktree → push → post all replies
  → update PR description → summary.

## Critical Rules

- **The implementation worktree is sacred.** From Step 6 (worktree creation) onward, ALL file
  changes (`Edit`/`Write`) use absolute paths **under the worktree `WT`**, and ALL git runs as
  `git -C "$WT" …`. **Never modify files under the current working directory** during
  implementation — that is the feature branch's own worktree and a concurrent session may be
  relying on it. The only things done in the current directory are the fold-back (Step 8),
  cleanup (Step 9), push (Step 10), and GitHub replies / PR-description (Steps 11–12).
- **Defer replies.** Do not post any GitHub reply (fixed/skipped/dismissed) until the final
  SHAs are settled in Step 10. Replies in Step 11 must reference `FINAL_SHA`, never a worktree
  SHA.
- **A fresh worktree has no deps.** A newly created worktree shares no `.venv` / `node_modules`
  / build outputs with the main checkout. If a fix needs a build or test, install/sync deps
  *in the worktree* first (see Step 7). Mass unresolved-import / module-not-found errors after
  a fresh worktree mean the missing install — **not** a code defect.
- **Never `--force`.** Push hardening uses fetch → rebase → retry, never a force-push.

## Your Task

### Step 0: Pre-Seed Progress Checklist

**Before doing anything else**, pre-seed this fixed checklist using whatever progress-tracking
tool this build exposes — `TodoWrite` if available, otherwise track it inline in your messages.
Either way these steps are mandatory and run in order; the tool is only for visibility.

Create these items (all `pending`):
1. `📥 Fetch review comments + thread IDs` — Steps 0.1–2
2. `🧭 Scope assessment + triage` — Steps 3–4
3. `📝 Plan phase: per-comment assessment + approval` — Step 5
4. `🌳 Create isolated worktree` — Step 6
5. `🔧 Implement approved fixes (one commit per fix, in worktree)` — Step 7
6. `🔀 Fold-back onto feature branch` — Step 8
7. `🧹 Remove throwaway worktree` — Step 9
8. `🚀 Push (fetch → rebase → push)` — Step 10
9. `💬 Post all replies (fixed / skipped / dismissed)` — Step 11
10. `📄 Update PR description` — Step 12
11. `✅ Final summary` — Step 13

### Step 0.1: Detect PR and Feature Branch

1. **Determine the PR number** (`PR_NUMBER`):
   - If `$1` is provided and non-empty, use it.
   - Otherwise auto-detect from the current branch:
     ```bash
     gh pr view --json number --jq '.number'
     ```
     - **If it fails** (no PR for current branch), inform the user and exit:
       - "No PR found for branch `<branch-name>`"
       - Suggestions: run `gh pr create` to create a PR first, or specify the number directly
         with `/ds:polish-pr2 <pr-number>`.
2. **Capture the feature branch** `F = git branch --show-current`. This is the branch
   everything folds back onto. (For a teammate's PR checked out elsewhere this still works —
   you fold onto whatever branch you're on.)
3. **Capture the base branch**: `gh pr view {PR_NUMBER} --json baseRefName --jq '.baseRefName'`.

Store `PR_NUMBER`, `F`, and the base branch for the rest of the session.

### Step 1: Fetch PR Review Comments

- Use `gh pr view {PR_NUMBER} --json comments,reviews` to get all comments and reviews.
- Parse the JSON to identify unresolved review comments.
- Use `gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments` for detailed review comments if needed.
- **IMPORTANT**: Fetch review threads with thread IDs (required for replying via GraphQL):
  ```bash
  gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {PR_NUMBER}) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 10) {
              nodes {
                id
                databaseId
                body
                author { login }
                path
                line
              }
            }
          }
        }
      }
    }
  }'
  ```
- Filter for comments that need action (not resolved, not outdated).

### Step 2: Display Comments Summary

- Show the total number of unresolved comments.
- Group comments by file/location for better context.
- Note how many threads have existing replies (candidates for auto-skip triage).
- Prepare to process each comment one-by-one.

### Step 3: Scope Assessment

Assess the overall effort of unresolved comments to determine whether to process all at once
or split into rounds.

a. **Classify each comment** by effort level:
   - **Low** (1 point): typo, naming, style, simple one-liner fix
   - **Medium** (2 points): logic change in a single function, add validation, adjust error handling
   - **High** (3 points): refactoring across files, architectural change, new abstraction needed

b. **Calculate total effort**: sum effort points across all unresolved comments.

c. **Display effort summary**: a table of comments with file, reviewer summary, and effort
   classification.

d. **Evaluate scope**:
   - **If total effort > 8 OR (any single comment is High AND there are >3 comments total)**:
     - Suggest splitting into rounds; recommend which comments to address now (prioritize
       Low/Medium first, or group by file).
     - Use `AskUserQuestion` with options:
       - **"Address all"** — proceed with everything
       - **"Address recommended batch"** — process only the suggested subset
       - **"Let me pick"** — user selects which comments to handle
     - Comments not selected for this round are recorded as **deferred** (not processed, not
       replied to).
   - **If scope is manageable**: proceed with all comments.

### Step 4: Triage Already-Addressed Threads

Before the Plan Phase, triage unresolved threads that already have replies (more than just the
original review comment). Only triage threads that are **in scope** (not deferred). This step
is silent — no user interaction.

For each in-scope unresolved thread with replies:
1. Read the full thread conversation (original comment + all replies).
2. Check the current state of the code at the commented location (read in the **current dir**
   — these are read-only checks before the worktree exists).
3. Assess whether the reviewer's concern is already addressed — by a code change, an
   explanatory reply, or both.
4. **If addressed**: exclude from processing; record the thread and the reason (e.g., "code
   changed in commit abc123", "explanatory reply given").
5. **If NOT addressed**: keep it in the queue (e.g., reply was a question back, code wasn't
   actually changed, reply acknowledged but didn't fix).

After triage, display how many threads were auto-skipped and why.

### Step 5: Plan Phase — For Each Remaining Unresolved Comment (One-by-One)

**IMPORTANT**: Process comments ONE AT A TIME. Only process threads that are **in scope** and
were NOT auto-skipped in triage. **This phase records decisions but makes NO edits and creates
NO commits** — all reads are against the current dir.

For each comment:

a. **Display Comment Context**
   - File path and line number, the code snippet being reviewed, the reviewer's comment, and
     surrounding code if helpful.

b. **Assess Comment & Propose Fix**

   **Part 1 — Thinking Buddy Assessment:**
   - **Evaluate merit**: does the suggestion actually improve the code? Valid concern or style
     preference? Real problem?
   - **Flag disagreements**: if the suggested approach has downsides or the existing code was
     correct, say so with reasoning.
   - **Suggest alternatives**: if there's a better way to address the underlying concern, propose it.
   - **Categorize**: "strong agree", "agree with modifications", "minor/style preference", or
     "disagree — here's why".

   **Part 2 — Proposed Fix:**
   - Propose a specific fix (may differ from what the reviewer suggested if you have a better idea).
   - Explain what changes will be made and why.
   - If you disagree, still propose what you would do if asked, but communicate the disagreement.

c. **Get User Approval** — use `AskUserQuestion`:
   - **"Approve fix"** — proceed with this specific fix
   - **"Approve all similar"** — if a pattern is detected, batch similar fixes
   - **"Modify approach"** — user changes the proposed fix
   - **"Skip this comment"** — don't address now (deal with later)
   - **"Dismiss comment"** — agree with your assessment that no change is warranted
   - Wait for the decision before the next comment.

d. **Handle Skipped Comments** — if "Skip", ask for rationale via `AskUserQuestion`
   ("Not applicable" / "Will address later" / "Disagree with suggestion" / "Custom
   explanation"). Record the skipped comment + rationale for the reply phase.

e. **Handle Dismissed Comments** — if "Dismiss", use your thinking-buddy assessment as the
   rationale automatically (no extra prompt). Record it for the reply phase.

**Output of this phase** (carry into the worktree):
- **Approved fixes** — an ordered list; each entry records its **thread ID**, target file(s),
  and the intended change.
- **Skipped** comments (+ rationale).
- **Dismissed** comments (+ rationale).

**Zero-fix guard:** if there are **no approved code fixes** (everything was skipped/dismissed),
skip Steps 6–10 entirely (no worktree, no fold-back, no push) and jump straight to **Step 11**
to post the skip/dismiss replies, then Step 13. Mark the worktree/fold-back/push todos as not
applicable.

### Step 6: Create the Isolated Worktree

Mark `🌳 Create isolated worktree` as `in_progress`. Do this AFTER all approvals and BEFORE any
file changes.

**Pre-flight (in the current directory — the feature branch's worktree):**
- Confirm you are on the feature branch `F`.
- Confirm the working tree is clean: `git status --porcelain`. If there is any output, **stop**
  and tell the user to commit or stash first — the fold-back in Step 8 cherry-picks onto this
  worktree and requires it clean.

**Create the throwaway worktree:**
1. Generate a short random suffix: `openssl rand -hex 3` (fall back to `echo $RANDOM`). Call it `SUFFIX`.
2. Temp branch `T = "{F}-{SUFFIX}"` (e.g. `feature/eng-123-add-auth-a1b2c3`). Two concurrent
   sessions get different suffixes, so they never collide on branch name or path.
3. Compute the worktree path `WT`:
   - Run `git rev-parse --path-format=absolute --git-common-dir`. Its parent directory is the
     **main repo root** (works whether you are in the main repo or a worktree).
   - `WT = "{parent-of-main-repo-root}/{main-repo-name}-worktrees/{T-without-its-type-prefix}"`,
     i.e. strip everything up to and including the first `/` of `T` for the directory name.
     This matches the `start-worktree` convention.
4. Create it off the current feature tip: `git worktree add -b "{T}" "{WT}" HEAD`.
   - Do **not** record this worktree in the cd-repo / lclaude picker — it is transparent
     plumbing removed in Step 9.
5. If creation fails, inform the user and exit.

Remember `F`, `T`, and `WT` for the rest of the session. Mark the todo `completed`.

### Step 7: Implement Approved Fixes (in the worktree, one commit per fix)

Mark `🔧 Implement approved fixes` as `in_progress`.

Work the **approved fixes in order**, **entirely inside the worktree `WT`**:
- File edits: absolute paths under `WT`. **Read each file at its `{WT}` path before editing** —
  the plan-phase reads were against the current dir, so the Edit tool needs a fresh Read of the
  `{WT}` copy.
- Git: `git -C "$WT" …`.
- **Install deps first if you will build/test** — a fresh worktree has none:
  - Python / uv workspace: `uv sync --all-packages --directory "{WT}/<subdir>"` (a plain
    `uv run` builds a venv missing the workspace-member editables → `ModuleNotFoundError`).
  - Node: `npm --prefix "{WT}" install`.  .NET: `dotnet restore "{WT}/..."`.
- Build/test: invoke the tool with its directory flag pointed at `WT`
  (`uv run --directory "{WT}/<subdir>" pytest …`, `dotnet test "{WT}/..."`,
  `npm --prefix "{WT}" test`, `go test -C "{WT}" ./...`). Do not `cd`.

For **each** approved fix:
1. Read the relevant file(s) at their `{WT}` path; make the change with Edit/Write under `WT`.
2. Test if applicable (against `WT`).
3. **One commit per fix** — stage only that fix's files and commit with a HEREDOC (use the
   `Co-Authored-By` trailer your environment specifies; the line below is the default):
   ```bash
   git -C "{WT}" add <files for this fix>
   git -C "{WT}" commit -m "$(cat <<'EOF'
   Address review: <brief description>

   - <what was changed>
   - Resolves comment by @reviewer

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
4. Capture the worktree SHA: `git -C "{WT}" rev-parse HEAD` → record `WT_SHA[thread]` for this fix.
5. **Do NOT reply. Do NOT push.**

Keep the ordered mapping `thread → WT_SHA` (and the commit order) for fold-back. For an
"Approve all similar" batch, keep v1's behavior — each fix is still its own commit (so each
thread maps to its own SHA). Mark the todo `completed` when all fixes are committed.

### Step 8: Fold-Back onto the Feature Branch

Mark `🔀 Fold-back onto feature branch` as `in_progress`.

This runs in the **current directory** (the feature branch `F`). Cherry-pick each worktree
fix-commit onto the *live* feature tip, **in commit order (oldest → newest)**, so if another
session committed since this session started you land on top of their commit.

For each fix-commit (in order):
1. Cherry-pick: `git cherry-pick "{WT_SHA[thread]}"`.
   - **Index-lock contention** (output mentions `index.lock` / "another git process"): another
     session is folding back right now. Wait briefly and retry — up to ~5 attempts. Do not
     force-remove the lock.
   - **Clean success**: record the new SHA — `git rev-parse HEAD` → `FOLDED_SHA[thread]`.
     Continue to the next fix.
   - **Conflict**: resolve **inline** honoring the intent of BOTH sides (your change and
     whatever the other session landed):
     - `git diff --name-only --diff-filter=U` → for each, read, resolve markers, `git add <file>`.
     - Finalize: `git cherry-pick --continue` (HEREDOC message if an editor would open), then
       record `FOLDED_SHA[thread]`.
   - **Unresolvable conflict**: `git cherry-pick --abort`, then **STOP without removing the
     worktree**. Report a recovery handle:
     ```
     Fold-back blocked by an unresolvable conflict.
     Pending fix commits (worktree SHAs, in order): {remaining WT_SHA list}
     Temp branch: {T}
     Worktree:    {WT}
     Resolve manually (e.g. cherry-pick the pending commits and fix), or rebase {T} onto {F}.
     ```
     Skip Steps 9–12; go to Step 13 and report the partial outcome. **No replies are posted**
     (the commits are not integrated).

Mark the todo `completed` once all fix-commits are on `F`.

### Step 9: Remove the Throwaway Worktree

Mark `🧹 Remove throwaway worktree` as `in_progress`. Only run after a fully successful fold-back.

1. Remove the worktree (long-path aware, force fallback):
   - `git -c core.longpaths=true worktree remove "{WT}"`
   - if that fails: `git -c core.longpaths=true worktree remove --force "{WT}"`
2. Delete the temp branch: `git branch -D "{T}"`.
3. Prune stale references: `git worktree prune`.

Mark the todo `completed`.

### Step 10: Push (and settle the final SHAs)

Mark `🚀 Push` as `in_progress`. The fold-back put your commits on the *local* feature tip, but
another session may have **pushed** to the remote `{F}` in the meantime. Decide whether to
push, then integrate the remote.

- **If there ARE deferred comments** (from Step 3): every push triggers a CI review round, so
  pushing partial work wastes CI cycles. Show "Addressed X of Y comments. Z deferred to next
  round." with the deferred list, then `AskUserQuestion`:
  - **"Don't push yet (Recommended)"** — keep changes local; run `/ds:polish-pr2` again to
    continue. **No push, no rebase happens**, so the **final SHAs are the `FOLDED_SHA` map**.
    Set `FINAL_SHA = FOLDED_SHA` and continue to Step 11 (replies will reference local-only
    commits — note this in the summary).
  - **"Push now"** — proceed with the push below.
- **If there are NO deferred comments**: proceed with the push below.

**Push:**
1. Fetch the remote tip: `git fetch origin "{F}"`.
2. If local has diverged from `origin/{F}`, rebase your folded-back commits on top:
   `git rebase "origin/{F}"`.
   - **Clean** → continue.
   - **Conflict** → resolve inline honoring BOTH sides (same approach as Step 8), then
     `git rebase --continue`. If unresolvable, `git rebase --abort` and STOP with a recovery
     handle (the `FOLDED_SHA` list, branch `{F}`); skip to Step 13 and report.
3. Push: `git push -u origin "{F}"`.
   - If **rejected (non-fast-forward)** — a session pushed inside the race window — repeat
     fetch → rebase → push (up to ~3 attempts). **Never** use `--force`.
4. **Settle `FINAL_SHA`:**
   - **If no rebase occurred** in step 2, the cherry-pick SHAs are final: `FINAL_SHA = FOLDED_SHA`.
   - **If a rebase occurred** (it rewrote every folded commit), recompute the mapping. The
     commits you added are exactly those ahead of the remote base; list them in order:
     ```bash
     git log --reverse --format=%H "origin/{F}..HEAD"
     ```
     taken **after** the successful rebase. These are your N fix-commits in the same order you
     committed them — map them positionally onto the ordered approved-fix list to rebuild
     `FINAL_SHA[thread]`. (A clean `git push` is a fast-forward and does not change SHAs, so
     these are final.)

Mark the todo `completed`.

### Step 11: Post All Replies

Mark `💬 Post all replies` as `in_progress`. Now that `FINAL_SHA` is settled, post every reply
(this is the deferred batch from v1's mid-loop). Use the **thread ID** (`PRRT_*`), never the
comment ID (`PRRC_*`).

a. **Addressed fixes** — for each, reference its `FINAL_SHA[thread]`:
   ```bash
   gh api graphql -f query='
   mutation {
     addPullRequestReviewThreadReply(input: {
       pullRequestReviewThreadId: "<thread_id>"
       body: "Fixed in <FINAL_SHA>.\n\n<description of change>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
     }) {
       comment { id body }
     }
   }'
   ```

b. **Skipped comments** — "Won't address in this PR. **Reason:** <rationale from user>" + attribution.

c. **Dismissed comments** — "Won't be changing this. **Reason:** <rationale>" + attribution.

Mark the todo `completed`. (Skipped entirely if fold-back was blocked.)

### Step 12: Update PR Description

Mark `📄 Update PR description` as `in_progress`.

- **Always run this step** — never auto-skip — **unless no push was made** (deferred → "Don't
  push yet", or fold-back blocked). If nothing was pushed, skip entirely; description updates
  only make sense after pushing.
- **Detect staleness** (any "yes" means it needs updating):
  - Current description: `gh pr view {PR_NUMBER} --json body --jq '.body'`.
  - Diff stat against base: `git diff origin/<base-branch>...HEAD --stat`.
  - New files not mentioned? Files removed / significantly changed? Tests added/removed (stale
    counts)? Docs (README, CLAUDE.md) added/updated? Approach changed from the summary? New
    dependencies/helpers introduced?
- **Present findings** — show stale vs current, then `AskUserQuestion`:
  - **"Update description"** — revise to match current state
  - **"Skip"** — keep as-is
- **If approved, revise in-place** — keep the existing structure (Summary, Verification, Closes
  link), update Summary and Verification, preserve the `Closes <ticket>` link, then:
  ```bash
  gh pr edit {PR_NUMBER} --body "$(cat <<'EOF'
  <updated PR body>
  EOF
  )"
  ```

Mark the todo `completed`.

### Step 13: Final Summary

Mark `✅ Final summary` as `in_progress`. Show:

```
PR: #{PR_NUMBER}
Addressed: N comments
  - <file>:<line> — Fixed in {FINAL_SHA}   (or "local only — not pushed" when push was deferred)
Auto-skipped (already addressed): <list with reasons>
Skipped (reply posted): <list with rationale>
Dismissed (reply posted): <list with rationale>
Deferred to next round: <list with effort> — run /ds:polish-pr2 again
Worktree: {WT} → removed / kept (fold-back blocked)
Fold-back: clean / conflict resolved / blocked
Pushed: yes ({F}) / no (deferred) / no (fold-back blocked)
PR description: updated / skipped / n-a (not pushed)
```

Remind the user to **manually resolve** the conversations after reviewing the changes
(threads are not auto-resolved). Mark the todo `completed`.

### Important Notes

**From v1 (`/ds:polish-pr`) — unchanged:**
- **Be Opinionated (Thinking Buddy)**: if a review comment is a style preference disguised as a
  bug, or the existing code was actually correct, say so with reasoning and let the user decide.
- **Reviewer Comments Are Suggestions, Not Mandates**: evaluate each on merit; some may be
  wrong or have better alternatives.
- **Scope Management**: when many comments exist or some imply significant refactoring, assess
  effort and offer to split into rounds.
- **Already-Addressed Detection**: threads with existing replies are triaged silently; if the
  concern is already addressed, the thread is skipped entirely (no assessment, no prompt, no
  reply) and listed in the summary.
- **Two-Phase Approach**: complete the Plan Phase (approval for ALL comments) before any
  implementation.
- **One-by-One Planning**: process each comment individually, getting approval before the next.
- **Batch Approval**: offer "Approve all similar" when a pattern is detected (still one commit
  per fix).
- **No Auto-Implementation**: NEVER implement fixes without explicit approval via AskUserQuestion.
- **Thread IDs vs Comment IDs**: reply with the **thread ID** (`PRRT_*`), NOT the comment ID
  (`PRRC_*`). The REST `/pulls/comments/{id}/replies` endpoint 404s — use the GraphQL
  `addPullRequestReviewThreadReply` mutation.
- **Always include attribution**: every GitHub reply includes the Claude Code attribution line.
- **Skipped vs Dismissed**: "Skip" = "deal with later"; "Dismiss" = "considered and chose not
  to change". Use the matching reply template.
- **Manual Resolution**: conversations are NOT auto-resolved — humans resolve them after review.
- **PR Description Updates**: always run the check (unless nothing was pushed); present what's
  stale and let the user decide.

**New in v2:**
- **Worktree is sacred**: no current-dir `Edit`/`Write`/mutating `git` before Step 8. All
  implementation is `git -C "$WT"` + absolute `WT` paths.
- **Deferred replies**: replies are posted only in Step 11, against `FINAL_SHA` — never a
  worktree SHA — because cherry-pick and rebase rewrite SHAs.
- **Per-fix fold-back + SHA remap**: each fix is cherry-picked onto the live tip in order; a
  push-time rebase re-maps `FINAL_SHA` via `git log --reverse origin/{F}..HEAD`.
- **Fold-back-blocked recovery**: on an unresolvable cherry-pick/rebase conflict, STOP, keep
  the worktree, print a recovery handle, post no replies, and report the partial outcome.
- **Fresh-worktree deps**: install/sync deps in `WT` before building/testing; mass
  unresolved-import errors are the missing install, not a code defect.
- **Never `--force`**: push integrates via fetch → rebase → retry only.
- **Zero-fix guard**: if all comments are skipped/dismissed, skip the worktree/fold-back/push
  and go straight to posting skip/dismiss replies.

### GitHub CLI Commands Reference

- View PR: `gh pr view <pr-number> --json comments,reviews`
- Detailed review comments: `gh api repos/{owner}/{repo}/pulls/<pr-number>/comments`
- Fetch review threads (with thread IDs for replying):
  ```bash
  gh api graphql -f query='query { repository(owner: "{owner}", name: "{repo}") { pullRequest(number: {pr_number}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 10) { nodes { id databaseId body author { login } path line } } } } } } }'
  ```
- Reply to comment (uses thread ID, not comment ID):
  ```bash
  gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "<thread_id>" body: "..." }) { comment { id body } } }'
  ```
- Get repo info: `gh repo view --json owner,name`
- Commit URL for the summary: `"$(gh repo view --json url -q .url)/commit/<FINAL_SHA>"`
