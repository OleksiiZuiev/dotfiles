---
description: Distill steering corrections from a branch's artifacts into reusable rules — routed to global CLAUDE.md or the repo-keyed overlay. Human-gated triage, nothing auto-applied.
allowed-tools: Bash(git *), Bash(gh *), Read, Write, Edit, Grep, Glob, Agent, TaskCreate, TaskGet, TaskList, TaskUpdate, AskUserQuestion, mcp__claude_ai_Linear__get_issue
argument-hint: [PR-number | ticket-id]   (default: current branch)
---

You are running the steering **learning loop**: harvest the corrections you made while working a
branch, distill them into reusable rules, and — after one-by-one human triage — promote the approved
ones into your conventions. The point is that hand-steering a repo you don't own is otherwise lost
work: the same corrections get re-spent next session.

**Two destinations, by lever:**
- **Global `~/.claude/CLAUDE.md`** — rules that generalize across every repo.
- **Repo-keyed overlay `~/.claude/overlays/{repo-key}.md`** — your personal, user-level rules for
  *this* repo (no need to generalize repo-wide; they're your lens on someone else's codebase). The
  overlay has two consumer sections, each read by a different `/ds:work-on` step:
  - `## Enforced (post-gen check)` — mechanical, recurring rules the Step 3.5 post-gen check enforces
    hard. **This is the main output:** the steering thinkie proved that *stated* guidance loses to
    surrounding code at codegen time (the "trim comments" rule was in global CLAUDE.md **and** the
    repo AGENTS.md and still ignored ~20×), so a recurring mechanical rule needs a *check*, not
    another doc.
  - `## Plan directives (plan self-check)` — structural rules folded into the Step 2.7 plan self-check.

**Hard rules:**
- **Never auto-apply.** Every candidate goes through the one-by-one triage gate (the `/ds:polish`
  posture). The user decides Approve / Modify / Skip / Dismiss and confirms the destination.
- **Distill rules, not requirements.** Drop anything that's a one-off scope/requirement change; keep
  only generalizable *how-to-build* corrections.
- **Re-runnable.** A ledger in the overlay records what's already been harvested/dismissed so a
  re-run on the same branch doesn't re-propose it.

## The overlay file format

```markdown
# Steering overlay — {repo-key}

Personal user-level steering for this repo. Maintained by /ds:distill;
consumed by /ds:work-on (Step 2.7 → Plan directives, Step 3.5 → Enforced).

## Enforced (post-gen check)
<!-- Mechanical, recurring rules the Step 3.5 post-gen check enforces hard. -->
- <imperative bullet>            (src: <short evidence>)

## Plan directives (plan self-check)
<!-- Structural rules folded into the Step 2.7 plan self-check. -->
- <imperative bullet>            (src: <short evidence>)

## Distill ledger
<!-- /ds:distill bookkeeping for re-run dedup. No consumer reads this section. -->
### Harvested sources
- <commit-sha | pr#<n>-comment:<id> | ticketctx:<TICKET-ID>@<session-ts>>
### Dismissed rules
- <short fingerprint of a dismissed candidate>
```

`/ds:work-on` only reads `## Enforced` and `## Plan directives`; the `## Distill ledger` is private
bookkeeping. Create the file from this template the first time anything routes to the overlay (or the
ledger needs an entry).

## Your Task

### Step 0: Resolve repo-key and scope

1. **Repo-key** (worktree-stable — the same trick the statusline and `/ds:work-on` Step 2.9 use):
   ```bash
   repo_key=$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")
   ```
   `--git-common-dir` always points at the **main** repo's `.git`, so this is identical from the main
   repo and any of its worktrees. (If leaf names ever collide across orgs, fall back to
   `{org}-{repo}` — note it and ask the user.)

2. **Dotfiles repo root** — where the rules are *written* and committed. Don't assume `~/dotfiles`
   (it isn't a real path); resolve it from the symlinked global CLAUDE.md so it works on any machine:
   ```bash
   dotfiles=$(dirname "$(dirname "$(readlink -f ~/.claude/CLAUDE.md)")")   # e.g. /c/work/github/OleksiiZuiev/dotfiles
   ```
   Path roles:
   - **Consume paths** (symlinks under the real `~/.claude`, what `/ds:work-on` reads):
     `~/.claude/overlays/{repo-key}.md`, `~/.claude/CLAUDE.md`.
   - **Write paths** (the dotfiles source, what you Edit/commit): `{dotfiles}/claude/overlays/{repo-key}.md`,
     `{dotfiles}/claude/CLAUDE.md`. Edit the write paths, never the symlink targets directly.

3. **Scope:**
   - **No argument** → current branch. Diff base is `origin/main..HEAD`; PR is the current branch's PR
     (`gh pr view`); ticket id is extracted from the branch name (strip up to the first `/`, take the
     first two hyphen-separated segments, uppercase — e.g. `feature/int-435-foo` → `INT-435`).
   - **Argument is a number** → that PR. Resolve its branch/diff via `gh pr view <n>`.
   - **Argument looks like a ticket id** (`ABC-123`) → use it for the ticket-context source; scope the
     diff/PR to the branch matching it if one is checked out.
   - Sources that don't resolve (no PR, no ticket) are simply **skipped** — `/ds:distill` works in any
     repo, degrading to whatever signals exist.

### Step 0.5: Pre-seed the progress checklist

When the `Task*` tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`) are available,
mirror the checklist into them so it stays visible to the user; otherwise keep it in your
own messages. Never narrate which tracking tools this build has. Seed:
1. `📥 Gather corrections (commits + PR comments + ticket context)`
2. `⚗️ Distill candidate rules (opus sub-agent)`
3. `⚖️ Triage one-by-one`
4. `📤 Route approved rules (global / overlay)`
5. `🧾 Record ledger + commit dotfiles`
6. `✅ Final summary`

### Step 1: GATHER (your-authored corrections only)

Mark `📥 Gather` `in_progress`.

First read the overlay's `## Distill ledger → Harvested sources` (if the overlay exists) and build a
skip-set of already-harvested signatures. Then collect, **excluding anything in the skip-set**:

1. **Your correction commits** — the richest source (e.g. diffs that *delete* AI-added prose):
   ```bash
   git log --reverse -p --author="$(git config user.email)" origin/main..HEAD
   ```
   Weight commits whose subject signals a correction: `Address review:`, `Polish:`, `fix`, `cleanup`.
   Record each commit's SHA for the ledger.
2. **Your PR comments** (if a PR exists) — steering you wrote on the PR:
   ```bash
   gh pr view <n> --json number,comments,reviews
   gh api repos/{owner}/{repo}/pulls/<n>/comments      # inline review comments
   ```
   Keep comments **authored by you**; record each comment id (`pr#<n>-comment:<id>`).
3. **Ticket-context decisions** (if a ticket id resolved) — the `#### Key Decisions` rationale you
   recorded in `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md`. Record each
   harvested session as `ticketctx:{TICKET_ID}@{session-ts}`.

If every source is empty or fully covered by the ledger, report "nothing new to distill" and stop.

### Step 2: DISTILL (opus sub-agent — frozen probe logic)

Mark `⚗️ Distill` `in_progress`. Launch an `Agent` sub-agent with `model: "opus"`. Pass it the gathered
raw material (commit diffs, comments, decisions) and the dedup targets. This extraction prompt is
**frozen** — keep it stable so re-runs are reproducible.

**Sub-agent prompt:**
> You are extracting reusable *steering rules* from a developer's corrections on one branch. You are
> given correction commits (with diffs), the developer's PR comments, and ticket-context decisions.
>
> 1. Read the dedup targets: `~/.claude/overlays/{repo-key}.md` (its `## Enforced` and
>    `## Plan directives`) and `~/.claude/CLAUDE.md`.
> 2. From the raw material, extract **corrections** — places where the developer changed
>    AI-generated work to match how they want code built. **Drop** one-off requirement/scope changes
>    (feature behavior, bug specifics); keep only generalizable how-to-build rules.
> 3. Emit each candidate rule as an imperative bullet plus metadata:
>    - **axis:** `mechanical` (cheap to fix in a finished diff — comments, naming, formatting, logs)
>      or `structural` (expensive after the fact — decomposition, component placement, method scope).
>    - **bucket:** `personal-lens` (your preference for someone else's repo) or `upstream` (a genuine
>      team convention worth upstreaming to their AGENTS.md).
>    - **already-stated?:** is this rule already present in the overlay or global CLAUDE.md? If stated
>      but **not** in `## Enforced`, flag it `promote-to-enforced` (stated guidance is being ignored —
>      it needs the check, not another mention).
>    - **suggested home:** `global CLAUDE.md` | overlay `## Enforced` | overlay `## Plan directives`.
>      Default mechanical → `## Enforced`; structural → `## Plan directives`; broadly-applicable → global.
>    - **evidence:** one-line pointer (commit SHA / comment id) and rough frequency.
>    - **confidence:** high / medium / low.
> 4. **Dedup:** drop any candidate already covered by the dedup targets (unless it qualifies as
>    `promote-to-enforced`). Do not re-propose existing rules verbatim.
> 5. Return a numbered list of candidates with their metadata, most-frequent/highest-confidence first.
> Make no edits and apply nothing — you only propose.

If it returns zero candidates, report "no new rules distilled" and skip to the summary.

### Step 3: TRIAGE (one-by-one — the `/ds:polish` gate)

Mark `⚖️ Triage` `in_progress`. Process candidates **ONE AT A TIME**. For each:

a. **Display** the candidate: the rule, its axis/bucket/already-stated flag, evidence, confidence, and
   suggested home.

b. **Your assessment** (thinking-buddy posture): is it a real, generalizable rule, or a style nit /
   one-off / already-handled? Flag disagreement with reasoning. For a `promote-to-enforced` candidate,
   note that it's already stated but ignored, so the value is the *check*.

c. **Get the user's decision** via `AskUserQuestion`:
   - **Approve** — promote as proposed.
   - **Modify** — user rewrites the rule's wording.
   - **Skip (defer)** — leave for a later run (not recorded as dismissed; re-surfaces next run).
   - **Dismiss** — not a rule; record a fingerprint in the ledger so it doesn't re-surface.
   And **confirm or override the destination**: `global CLAUDE.md` | overlay `## Enforced` | overlay
   `## Plan directives`. For a `global` destination, also name the **best-fit existing
   `#Commandments for …` block** the rule will be appended to (the user confirms the block).
   Offer **"Approve all similar"** when several candidates share one mechanical pattern.

   Wait for each decision before the next candidate.

Mark `⚖️ Triage` `completed` once every candidate has a decision.

### Step 4: ROUTE the approved rules

Mark `📤 Route` `in_progress`. Apply only approved/modified rules; nothing else.

- **Global** → `Edit {dotfiles}/claude/CLAUDE.md`: append the imperative bullet to the **best-fit
  existing `#Commandments for …` block** named in triage (inline, in that block's voice — do **not**
  create a separate "distilled" section). Match the surrounding bullet style.
- **Overlay** `## Enforced` / `## Plan directives` → append the bullet (with a short `(src: …)` note)
  under the chosen section in `{dotfiles}/claude/overlays/{repo-key}.md`. If the overlay file doesn't
  exist yet, create it from the template above.

### Step 5: RECORD the ledger + commit

Mark `🧾 Record` `in_progress`.

1. Update the overlay's `## Distill ledger` (creating the overlay file from the template if it doesn't
   exist yet — needed even when all rules went to global, so re-runs skip these sources):
   - `### Harvested sources`: append every commit SHA / PR-comment id / ticket-context session this run
     consumed.
   - `### Dismissed rules`: append a short fingerprint for each **dismissed** candidate.
2. **Commit the dotfiles repo** (separate git repo; commit without prompting — the user has standing
   approval for dotfiles commits during this work). Stage only the files this run changed
   (`{dotfiles}/claude/CLAUDE.md` and/or `{dotfiles}/claude/overlays/{repo-key}.md`):
   ```bash
   git -C "$dotfiles" add claude/CLAUDE.md "claude/overlays/{repo-key}.md"
   git -C "$dotfiles" commit -m "$(cat <<'EOF'
   distill: promote steering rules from <repo-key>/<scope>

   <one line per promoted rule: destination + summary>
   EOF
   )"
   ```
   End the message with the environment's `Co-Authored-By` trailer.
3. **If a *new* overlay file was created**, the symlink doesn't exist yet — run
   `powershell.exe -File "$dotfiles/install-admin.ps1"` once so `/ds:work-on` can read it from
   `~/.claude/overlays/`. Editing an **existing** overlay or global CLAUDE.md flows through the
   existing symlink — **skip** the install in that case.

Mark `🧾 Record` `completed`.

### Step 6: Final summary

Mark `✅ Final summary` `in_progress`. Print:

```
/ds:distill — {repo-key} ({scope})
Gathered:  C commits · P PR comments · T ticket decisions  (S skipped via ledger)
Distilled: N candidates
Promoted:  G → global CLAUDE.md · E → overlay ## Enforced · D → overlay ## Plan directives
Skipped:   K   Dismissed: M
Committed: <sha>     Install re-run: yes (new overlay) / no
```

List the promoted rules with their destinations. Suggest next steps:
- The newly enforced rules take effect on the next `/ds:work-on` run in this repo (Step 3.5 reads
  `## Enforced`, Step 2.7 reads `## Plan directives`).
- Re-run `/ds:distill` after more corrections; the ledger keeps it from re-proposing.

## Important Notes
- **Thinking-buddy posture:** assess each candidate on merit; a candidate can be a nit, a one-off, or
  already-handled — say so. The user decides.
- **Two outputs, two homes:** the bulk is already-stated-but-ignored mechanical rules → `## Enforced`
  (for the check); genuinely new structural/global rules → `## Plan directives` / global CLAUDE.md.
- **Distill only pays off because the consumer exists** — `/ds:work-on` Step 3.5 enforces `## Enforced`
  and Step 2.7 folds in `## Plan directives`.
- **Deferred (not v1):** drafting an upstream PR to a repo's `AGENTS.md`; report-only mode; ingesting
  accumulated `*.findings.md`.
