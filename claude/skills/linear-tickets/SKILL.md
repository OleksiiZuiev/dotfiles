---
name: linear-tickets
description: How to write a Linear ticket — the body carries what to build, the context needed to act on it, and the open questions that block it; the rationale behind each of those goes in a comment on the ticket. Covers the routing test, the signatures of a body that has drifted into a document, concision per surface, what to do on a re-refinement, why a ticket must stand alone without the private notes behind it, and the `Workspace:` and `Plan:` lines that end the body. Use whenever creating, refining or updating a Linear issue description or writing a comment on one — including any `save_issue` or `save_comment` call, and the ticket-writing steps of `/ds:refine` and `/ds:quick`.
---

# Writing Linear tickets

## The split

- **The body** — what to build, the context needed to act on it, and the open questions that
  block it.
- **A comment on the ticket** — why each of those says what it says.

Both surfaces stay short. The body is read before every work session on the ticket; the comment
is read once, by whoever asks "why is it like this".

## The routing test

For each sentence you are about to put in the body, ask: **would a builder do anything
differently if this sentence vanished?**

- Yes → body.
- It only explains a choice already made → comment.

Apply it sentence by sentence, not section by section. A body item and its justification usually
arrive glued together in one paragraph, and the whole point is to split that paragraph.

## Signatures of a body that has drifted

Any of these means the body has become a document. Move the material to the comment.

- **A section named** Rationale, Background, Why, Context beyond a line, Decisions made, Summary of
  changes, Notes.
- **Past-tense justification verbs** — "was carved off", "we chose X over Y", "this beat", "the
  reason is", "originally", "after discussion".
- **A rejected alternative.** The builder builds the winner. The loser is comment material.
- **Narration of the refinement itself** — who asked what, what was settled when.
- **A measurement quoted as proof** rather than as something to act on. *"ds-online already sets
  `height: 100%` on `html, body`"* proves a point; *"add `html, body, #root { height: 100% }` to
  `src/index.css`"* is the instruction.

## Open questions stay in the body

They block the build, so the builder has to see them. State the question and its real options
where they will be read. The evidence and argument behind each option go to the comment.

Same for what "done" means — it is verifiable and the builder acts on it, so it belongs in the
body.

## Concision, per surface

**Body.** Imperative. One item per thing to build. Name the file, symbol or line rather than
describing it — `views/import-preview/index.tsx:12` beats a paragraph locating it. Bold the
subject of each item so the body scans in one pass.

**Comment.** One short paragraph per body item, in the body's own order, opening with the item it
explains. Never restate the instruction — the reader has just read it.

**When an item seems to need its argument inline**, the argument is doing the work the instruction
should do. Write the instruction, move the argument to the comment, then re-read the instruction
alone. If it no longer says enough, the instruction was underspecified — fix that instead of
importing the argument back.

## Updating an existing ticket

- **Edit the body in place** so it always reads as current. No changelog inside it, no superseded
  instructions left behind, no annotations about what changed.
- **Append a new dated comment** per refinement pass: what changed in the body, and why.
- **Never edit or delete an earlier rationale comment.** Those are the history of the reasoning.

## A ticket must stand alone

Linear is org-wide; your notes are not. A reader who cannot open your notes must still be able to
act on the ticket.

- No `[[wiki-links]]`, no `§`-references into a private note, no note-only identifiers.
- When a note settles something the ticket needs, **copy the substance onto the ticket**,
  compressed. Leave the long form in the note.
- A follow-up is "tracked as a follow-up outside this ticket", not a private code.
- Links between Linear issues are the exception and are encouraged — every reader can open those.

The link runs one way: notes cite their ticket, the ticket cites nothing private.

## Workspace and plan lines

The body ends with one line per fact, each on its own line, in this order:

```
Workspace: <repo-key>
Plan: <Linear document URL>
```

- **`Workspace:`** — every ticket. The repo the work happens in, as its key in the repo map
  (`dotfiles`, `agents-and-tools`). `/task-run` reads it to check it runs in the right checkout;
  `/plan-next` reads it to dispatch.
- **`Plan:`** — a ticket that belongs to a plan whose home is a Linear document. The document's
  URL. The document lists the ticket under `## Tasks`; `plan status` reports a ticket where the two
  disagree.

Both are org-readable — a repo name and a Linear link — so they keep the ticket standing alone.
Edit them in place like the rest of the body; detaching a ticket from its plan removes its
`Plan:` line.

## Small tickets

The split still applies, and usually resolves to **body only**. A one-line change has no rationale
worth a comment — do not invent one to fill the shape.

## Worked example

INT-721's body carries the instruction:

> **Clear the selection on mount** in the embedded host. `sessionStorage['file-selection']`, and
> `context/entity-selection-context.tsx` is sticky the same way.

Its comment carries why:

> **Why the selection is cleared on mount.** It persists to `sessionStorage['file-selection']` and
> `clearSelection` is called from one kind of place only — a Back navigation — never after a
> successful import or submit. No host has noticed because in all three the tab dies at the end of
> the flow. UpLink's tab never closes, so reopening would show the previous selection still
> checked […]

The body item is actionable without the paragraph. The paragraph explains nothing the body
already said. That is the test passing in both directions.

## Related

`ticket-context` owns the session-history document stored outside the repo. This skill owns the
ticket text itself.
