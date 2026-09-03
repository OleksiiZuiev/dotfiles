---
description: Address findings from a local findings file — assess each on merit, implement approved fixes, write resolutions back to the file. Off-PR counterpart to /ds:polish-pr.
allowed-tools: Bash(git *), Read, Write, Edit, Grep, Glob, Task, TaskCreate, TaskGet, TaskList, TaskUpdate
argument-hint: <file>
---

You are addressing findings recorded in a local **findings file** — assessing each on merit, implementing the approved fixes, committing them locally, and writing each finding's resolution back into the file.

This is the off-PR counterpart to `/ds:polish-pr`: the same thinking-buddy posture and one-by-one triage, but the findings come from a **file** (produced by `/ds:review --to`, `/ds:analyze-pr`, or hand-written) instead of GitHub review comments, and resolutions are written **back into the file** instead of posted as PR replies. **Nothing is pushed and no GitHub call is made** — this is solo polishing; you push when you're ready.

**Distinction from siblings:**
- `/ds:polish-pr` — addresses *human* reviewer comments already posted on a GitHub PR (fetches comments, replies, pushes).
- `/ds:polish` (this command) — addresses findings from a local file (private, off-PR), writes resolutions back to the file, no push.
- `/ds:review --to <file>` / `/ds:analyze-pr <file>` — *produce* the findings this command consumes.

## The findings file format

This command is the owner of the shared findings format; `/ds:review` and `/ds:analyze-pr` write into it.

**Two zones, split by the first `---`:**
- **Inbox** (above the first `---`): free bullets the user writes (questions for `/ds:analyze-pr`, notes). This command does **not** touch the Inbox.
- **Thread** (below the first `---`): item blocks, usually grouped under dated producer headings (`## /ds:review — DATE`, `## /ds:analyze-pr — DATE`). This is what `/ds:polish` reads and updates.

**Item block:**
```
### F<n> · <source> · <category>
- **Status:** open
- **Item:** <one-line summary — the finding or the question>
- **Location:** `path:line`            (optional)
- **Detail:** <why / answer / prose>   (optional)
- **Counter-argument:** <…>            (optional)
- **Proposed change:** <… | (needs unpacking)>   (optional)
- **Resolution:** —
```
(an optional fenced code/diff block may follow the fields)

- `<source>`: `note` | `analyze-pr` | `review:<dimension>` (e.g. `review:performance`)
- `<category>` (producer-owned, never changed here): `confident` | `smell` | `question`
- `F<n>`: stable id (e.g. `F3`).

**Status** (this command owns it):

| Status | Meaning | Actionable on a run? |
|---|---|---|
| `open` | awaiting triage (producer default) | **yes** |
| `skipped` | deferred to a later run (`Resolution` says why) | **yes** — re-runs re-surface it |
| `applied (<sha>)` | fix implemented & committed | no (resolved) |
| `modified (<sha>)` | implemented with an altered approach | no (resolved) |
| `dismissed` | considered, no change warranted (`Resolution` holds the reasoning) | no (resolved) |
| `answered` | a `question` item that needs no action | no (resolved) |

**Parse contract (the part this command depends on):** an item is any block whose heading matches `^### F\d+ · <source> · <category>`. The only fields parsed are the heading (id / source / category) and `**Status:**`; the only fields written back are `**Status:**` and `**Resolution:**`. Every other field is free-form passthrough — display it, don't depend on its shape. Producers' narrative `##`/`###` headings (e.g. analyze-pr's `## 1. <title>`) don't match the `### F\d+ · ` signature, so they're ignored.

## Your Task

### Step 0: Load and parse the findings file

1. **Require the argument.** `$1` is the findings file path. If empty, stop:
   > Usage: `/ds:polish <file>` — addresses findings recorded in a local findings file (produced by `/ds:review --to <file>` or `/ds:analyze-pr <file>`).
2. **Verify it exists:**
   ```bash
   test -f "$1" && echo found || echo missing
   ```
   If missing, stop and say so.
3. **Read the file.** Locate the first `---`; everything below it is the **thread**. Parse every item block (`^### F\d+ · `), capturing for each: id, source, category, Status, and the full block text (to display).
4. **Build the actionable queue:** items whose `Status` is `open` or `skipped`. Resolved items (`applied`/`modified`/`dismissed`/`answered`) are excluded.
5. **If the actionable queue is empty:** print a short summary of the resolved items (id, source, status) and stop:
   > Nothing to polish — all N findings in `<file>` are resolved. (Set a finding's `Status` back to `open` to re-address it.)

### Step 0.5: Pre-seed the progress checklist

When the `Task*` tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`) are available, mirror the checklist into them so it stays visible to the user; otherwise keep it in your own messages. Never narrate which tracking tools this build has. Seed:

1. `🔎 Plan: assess each actionable finding`
2. `🛠️ Implement approved fixes (commit per fix)`
3. `✍️ Write resolutions back to <file>`
4. `✅ Final summary`

### Step 1: Load conventions for implementation

You will be editing real code, so honor the repo's documented rules. Collect the conventions files nearest the code the findings touch:

- Gather the `Location` paths from the actionable items. For each, walk its directory and all ancestors up to the repo root collecting every `CLAUDE.md` and `AGENTS.md`; take the union, deduped, ordered most-specific → least-specific:
  ```bash
  printf '%s\n' <location-dirs> | while read -r d; do
    while :; do
      for n in CLAUDE.md AGENTS.md; do [ -f "$d/$n" ] && printf '%s\n' "$d/$n"; done
      [ "$d" = "." ] && break
      d=$(dirname "$d")
    done
  done | sort -u
  ```
- Read each and keep its rules in context. Also honor the user's global style rules. If none are found, infer conventions from neighbouring code.

### Step 2: Plan Phase — assess each actionable finding (one-by-one)

Mark `🔎 Plan` as `in_progress`. Process findings **ONE AT A TIME**. For each:

a. **Display the finding** — its id, source, category, and block (Item, Location, Detail, Proposed change, any code context).

b. **Read current code state** at `Location` (if present) so the assessment reflects the code as it is now, not as it was when the finding was written.

c. **Thinking-buddy assessment:**
   - **Evaluate merit** — does the finding identify a real improvement, or is it a style preference / already-handled / not worth it? A `smell` may have no clean fix; a `question` may need no code change at all.
   - **Flag disagreement** with reasoning if you think the finding is wrong or the current code is already correct.
   - **Propose a concrete fix** (may differ from the finding's `Proposed change` if you have a better one). For a `question` with no implied action, say so and propose marking it `answered`.
   - **Categorize your stance:** "strong agree" / "agree with modifications" / "minor/style preference" / "disagree — here's why".

d. **Get user decision** via `AskUserQuestion`:
   - **Approve fix** — implement as proposed
   - **Approve all similar** — if a repeating pattern is detected, batch the similar fixes
   - **Modify approach** — user adjusts the fix
   - **Skip (defer)** — leave for a later run (stays `skipped`, re-surfaces next time)
   - **Dismiss** — considered, no change warranted (uses your assessment as the rationale; for a `question`, this marks it `answered`)
   Wait for the decision before moving to the next finding. Record each decision (Skip → ask for a one-line rationale; Dismiss → use your assessment's reasoning).

Mark `🔎 Plan` as `completed` once every actionable finding has a decision.

### Step 3: Implementation Phase — for each approved fix

Mark `🛠️ Implement` as `in_progress`.

a. **Implement** the fix with Edit/Write, honoring the conventions from Step 1.

b. **Commit per fix, locally** (one commit per finding, like `/ds:polish-pr`):
   ```bash
   git add <files>
   git commit -m "$(cat <<'EOF'
   Polish: <brief description>

   - <what changed>
   - Addresses finding <F-id> (<source>)
   EOF
   )"
   ```
   End the message with the environment's `Co-Authored-By` trailer (do not hardcode a model). Capture the resulting short SHA.

c. **No push.** This command never pushes and makes no GitHub call.

### Step 3 (write-back): record resolutions in the file

Mark `✍️ Write resolutions` as `in_progress`.

`Read` the current full file, then `Write` it back with each processed item's `**Status:**` and `**Resolution:**` lines updated — preserving everything else (Inbox, other items, all other fields) **verbatim**. Use whole-file Read+Write rather than per-line Edit (robust on multi-line markdown). Updates:

| Decision | New Status | Resolution |
|---|---|---|
| Approved, implemented as proposed | `applied (<sha>)` | one line: what was changed |
| Approved with a changed approach | `modified (<sha>)` | one line: what was done and how it differs |
| Skipped | `skipped` | the user's one-line rationale |
| Dismissed (finding) | `dismissed` | your assessment's reasoning |
| Dismissed (question, no action) | `answered` | the answer / why no action |

Mark `✍️` (and `🛠️`) `completed`.

### Step 4: Final summary

Mark `✅ Final summary` as `in_progress`. Print:

```
/ds:polish — <file>
Addressed: <A> (commits: <sha>, <sha>, …)
Skipped:   <S>  (still actionable on next run)
Dismissed/answered: <D>
Still open: <O>
Resolutions written back to <file>. Nothing was pushed.
```

List the addressed findings with their SHAs, the skipped ones with rationale, and the dismissed/answered ones. Suggest next steps: re-run `/ds:polish <file>` to pick up skipped items, push when ready, or run `/ds:review --to <file>` again after changes to refresh findings.

## Important Notes

- **Thinking-buddy posture:** evaluate each finding on merit. A finding can be wrong, already handled, or not worth doing — say so. The user decides.
- **The file is the source of truth.** This command reads findings from it and writes resolutions back to it. It never invents findings and never edits the Inbox.
- **Commit per fix, locally, no push.** One commit per addressed finding (preserves traceability); the user pushes when ready. No GitHub interaction, no PR replies, no PR description edits — that's `/ds:polish-pr`'s job.
- **Re-runnable:** `open` and `skipped` items are processed on each run; `applied`/`modified`/`dismissed`/`answered` are left alone. To re-address a resolved finding, set its `Status` back to `open`.
- **Tiny parse surface:** only the `### F\d+ · ` heading and `Status` are parsed; only `Status`/`Resolution` are written. Producers can enrich the other fields freely without breaking this command.
- **No auto-implementation:** never implement a fix without explicit user approval via `AskUserQuestion`.
- **Batch approval:** when a repeating pattern is detected, offer "Approve all similar" to avoid per-item prompts for the same mechanical fix.
- **Conventions:** honor the nearest `CLAUDE.md`/`AGENTS.md` to each edited file plus the user's global style rules, the same way `/ds:work-on` resolves conventions per subproject.
