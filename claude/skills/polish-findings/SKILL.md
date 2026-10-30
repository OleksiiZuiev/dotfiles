---
name: polish-findings
description: Address the findings in a local findings file — decide each on merit through `polish-triage`, implement the approved fixes one commit each, and write every resolution back into the file. `+auto` decides without asking and escalates what needs the user; with no file argument the file is the branch task's `{ID}.findings.md`. Also owns the findings-file format that `/ds:review --to` and `/ds:analyze-pr` write into. Usage /polish-findings [+auto] [<file>].
---

# Polishing a findings file

Addresses findings recorded in a local findings file, produced by `/ds:review --to <file>`,
`/ds:analyze-pr <file>` or written by hand. Each finding is decided through the `polish-triage` skill;
approved fixes are committed locally, and each resolution is written back into the file. Nothing is
pushed and no GitHub call is made.

Review comments from a human on a pull request are `/ds:polish-pr`'s job, not this skill's.

## The findings file format

**Two zones, split by the first `---`:**
- **Inbox** (above it): free bullets the user writes (questions for `/ds:analyze-pr`, notes). This skill
  never touches the Inbox.
- **Thread** (below it): item blocks, usually grouped under dated producer headings
  (`## /ds:review — DATE · BASE..HEAD`, which records the reviewed range, and `## /ds:analyze-pr — DATE`). This is what the skill reads and updates.

**Item block:**
```
### F<n> · <source> · <category>
- **Status:** open
- **Item:** <one-line summary — the finding or the question>
- **Impact:** user-facing | efficacy | maintenance   (optional)
- **Severity:** high | medium | low                   (optional)
- **Location:** `path:line`            (optional)
- **Detail:** <why / answer / prose>   (optional)
- **Counter-argument:** <…>            (optional)
- **Proposed change:** <… | (needs unpacking)>   (optional)
- **Resolution:** —
```
An optional fenced code or diff block may follow the fields.

- `<source>`: `note` | `analyze-pr` | `review:<dimension>` (for example `review:performance`)
- `<category>`, owned by the producer and never changed here: `confident` | `smell` | `question`
- `F<n>`: stable id (for example `F3`)

**Status**, owned by this skill:

| Status | Meaning | Actionable on a run? |
|---|---|---|
| `open` | awaiting a decision (the producer's default) | yes |
| `skipped` | deferred to a later run; `Resolution` says why | yes |
| `escalated` | auto mode left it for the user; `Resolution` holds the assessment | yes |
| `applied (<sha>)` | fix implemented and committed | no |
| `modified (<sha>)` | implemented with an altered approach | no |
| `dismissed` | considered, no change warranted; `Resolution` holds the reasoning | no |
| `answered` | a `question` that needs no action | no |

**Parse contract:** an item is any block whose heading matches `^### F\d+ · <source> · <category>`.
The fields read are the heading, `Status`, `Impact`, `Severity` and `Location`; the only fields written
back are `Status` and `Resolution`. Every other field is free-form passthrough: display it, never
depend on its shape. A producer's narrative headings (for example `## 1. <title>`) do not match the
item signature and are ignored.

## Load

1. **Arguments.** `+auto` anywhere in the arguments switches on auto mode; strip it. What remains is
   the file path.
2. **No path.** Take the task ID from `git branch --show-current`: strip everything up to and including
   the first `/`, take the first two hyphen-separated segments and upper-case them
   (`feat/ve-46-polish-auto` → `VE-46`). The file is
   `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{ID}.findings.md`. A branch that yields no ID,
   or a file missing there, ends the run with one line naming what was looked for.
3. **A path that does not exist** ends the run with one line saying so.
4. **Parse** every item block below the first `---`, capturing id, source, category, `Status`,
   `Impact`, `Severity`, `Location` and the full block text.
5. **Queue** the items whose `Status` is `open`, `skipped` or `escalated`, in file order; under `+auto`
   only the `open` ones, since a `skipped` item is the user's deferral and an `escalated` one is already
   decided as far as auto mode goes. With an empty queue, print the resolved items (id, source, status) and stop: `Nothing to polish — all N findings in
   <file> are resolved. (Set a finding's Status back to open to re-address it.)`

Mirror this checklist into the `Task*` tools when they are available, otherwise keep it in your
messages: decide each actionable finding, implement the approved fixes, write the resolutions back,
final summary.

## Decide

Process the queue one finding at a time, in order, because an earlier fix can make a later finding
stale. For each, apply `polish-triage`:

- **Interactive**: the card, then the question.
- **`+auto`**: the routing table. `AskUserQuestion` is never called. Record the decision and the
  assessment, then implement before the next finding, so the overlap rule sees every fix this run has
  committed.

## Implement

Each applied fix is implemented and committed by the commit rule of `polish-triage`. In an interactive
run, every decision is collected first and the fixes are implemented afterwards.

## Write back

`Read` the current file, then `Write` it back with each processed item's `Status` and `Resolution`
updated and everything else (Inbox, other items, every other field) verbatim.

| Decision | New Status | Resolution |
|---|---|---|
| Approved, implemented as proposed | `applied (<sha>)` | one line: what changed |
| Approved with a changed approach | `modified (<sha>)` | one line: what was done and how it differs |
| Skipped | `skipped` | the user's one-line rationale |
| Escalated | `escalated` | the assessment: stance, reason and, when there is one, the fix it would take |
| Dismissed (finding) | `dismissed` | the assessment's reasoning, or `low-severity smell, not surfaced` |
| Dismissed (`question`, no action) | `answered` | the answer, or why no action |

## Summary

```
polish-findings — <file>
Applied: <A> (commits: <sha>, <sha>, …)
Skipped: <S>  (still actionable on the next run)
Escalated: <E>
Dismissed/answered: <D>
Resolutions written back to <file>. Nothing was pushed.
```

Under `+auto`, the summary ends with each escalated finding as its id, `Item`, `Location` and
`Resolution`, so a caller can pass them on without reading the file back.

## Notes

- **The file is the source of truth.** The skill never invents findings and never edits the Inbox.
- **No implementation without a decision.** Interactive: the user's approval. `+auto`: the routing
  table; a finding the table does not mark applied is never implemented.
- **Re-runnable.** `open`, `skipped` and `escalated` items are processed on every interactive run, `open`
  ones on every `+auto` run; resolved items are left alone. Setting a resolved finding's `Status` back to `open` re-addresses it.
