---
name: pr-descriptions
description: How to write a pull request description — the reviewer already has the diff, so the body carries only what the diff cannot tell them: what now works, where to start reading, why the shape is what it is where a reviewer would read it as a mistake, the constraints that fail silently, and what is deliberately left out. Covers the cut test that decides each sentence, the gate a decision must pass to earn a line, the signatures of a body that has become a changelog, the section shape and its budget, the title form, and what to do with a repo PR template. Use whenever writing or revising a PR title or body — including any `gh pr create --body` or `gh pr edit --body` call, and the description steps of `/ds:create-pr` and `/ds:polish-pr`.
---

# Writing pull request descriptions

## The reviewer already has the diff

It is one tab away, it is authoritative, and it is complete. A body that enumerates the change makes
the reviewer read the same thing twice, and goes stale the moment another commit lands.

Five things the diff cannot tell them. The body carries these and little else:

- **What now works, or stopped breaking** — in the terms of whoever is affected, not the mechanism
  that delivers it.
- **Where to start reading**, and in what order.
- **Why the shape is what it is**, wherever a reviewer reading the diff would read it as a mistake —
  the constraint that forced it, not the route you took to find it.
- **A constraint a consumer would otherwise discover by having the flow fail silently.**
- **What is deliberately not here** — the follow-up, the other repo's half, the thing that looks
  missing.

## The cut test

For each sentence you are about to write, ask: **is this in the diff?**

- **No** → keep. Behaviour, motivation, reading order, an exclusion, a consumer constraint.
- **Yes, and a reviewer opening that file draws the same conclusion** → cut.
- **Yes, but a reviewer opening that file alone draws the _wrong_ conclusion** → keep, as one
  sentence in the reading order, stating the correction only — never the route to it.
- **Yes, and a reviewer reading the whole diff would call the shape a mistake** → keep as a decision:
  what holds, then the constraint that forced it. One sentence. The route you took stays cut.

Apply it sentence by sentence, not section by section. A body does not become a changelog a section
at a time; it accretes one sentence per thing the writer noticed while writing.

## Signatures of a body that has become a changelog

Any of these means the diff is being retold. Cut or collapse.

- **A section per touched area** — `## Documentation`, `## Tests`, `## Refactoring`, `## Changes`.
  The diff already groups by path, and better.
- **A bullet per changed file.** A reading order names the three to six files that carry the change.
  Coverage is the diff's job.
- **A paragraph on a mechanical change** — an extraction, a rename, a moved section, a bumped
  version. One clause inside another bullet, or one sentence collapsing all of them.
- **The route to a decision, recounted.** A decision that passes the gate gets one sentence: what
  holds, and the constraint that forced it. The route is what stays cut — the options weighed, the
  order you weighed them in, where you started. The reviewer who wants the route has the ticket, the
  commit messages, and you.
- **Prose that restates a file's diff** — "renamed A to B, added C, removed D".
- **Symmetry-filling** — writing about a mode, case or file only because its sibling got a mention.
  A case with nothing to admit, configure or change is a case with nothing to say.
- **A rejected alternative nobody would reach for.** Name the alternative when it is the one a
  reviewer reaches for and asks about; defending the shape against options they were not considering
  spends their attention to no end.
- **A `## Test plan` that lists what CI runs.** The run is on the PR, green or red.

## The shape

In this order. Only `## Summary` is unconditional.

1. **Stacked-PR notice**, when the branch targets another feature branch — the body's first line,
   before the summary:
   `> ⚡ Stacked on #<parent-pr> (\`<parent-branch>\`) — will retarget to main when that branch merges.`
2. **`## Summary`** — one to three sentences on what now works, plus the single decision when only
   one passes the gate below. Then, when a caller must change, one bolded line on its own:
   `**Breaking:** <what they must now pass, and why the old value was wrong>`.
3. **The Linear line** — the ticket and this PR's Linear review view, as one blockquote line under
   the summary, with no heading:

   ```
   > 🎫 [Linear ticket](<ticket URL>) · 🔍 [Linear review](https://linear.app/review/<owner>/<repo>/pull/<number>)
   ```

   The blockquote sets it apart from the body's prose — it is navigation, not content — and one line
   avoids the blockquote joining consecutive lines into a paragraph. The review URL is built from the
   PR's own path — no API key, no workspace slug — and serves a reviewer without the GitHub → Linear
   browser extension, which puts the same link on the page for everyone who has it. Use the
   `https://` form only: GitHub's markdown sanitizer strips the `linear://` desktop-app scheme, so it
   renders as dead text.
4. **`## Where to start`** — the reading order, once the change spans more than about three files.
   One bullet per file: the path, then the one fact you would get wrong by reading that file alone.
   Three to six bullets, one to two sentences each.
5. **`## Decisions`** — a choice a reviewer reading the diff would call a mistake, or would meet with
   "why not the obvious thing". One bullet each, one sentence: what holds, then the constraint that
   forced it, naming the obvious thing only when it is what the reviewer reaches for. Typically two
   or three bullets; a large change may warrant a few more. A choice that misleads only inside one
   file is a reading-order bullet and does not also appear here.
6. **A contract section, named for the contract** — `## Host contract`, `## Consumer contract`. Only
   for constraints a consumer cannot infer and would meet as a silent failure. Skip it otherwise;
   most PRs have none.
7. **`## Not in this PR`** — the follow-up, the other repo's half, the deliberate omission. This is
   the one heading for the concept; `## Scope`, `## Follow-ups` and `## Before merge, not done here`
   are the same section under other names, and inviting "scope" invites restating what *is* in
   scope, which is the summary's job.
8. **`## Test plan`** — only a check CI does not perform: a manual verification, a device, a
   deployed environment. Omit the section when CI covers it.
9. **The attribution footer**, per the session's attribution rule.

A section with one obligatory sentence in it is not a section. Fold it into the summary.

## The budget

Pull request #386 in `datasnipper-enterprise/integrations-importer-app` — a change spanning source,
environment files and docs — is five sections and about 380 words. **That is the top of the range,
not the middle.** A one-file fix is a summary and the Linear line.

The body grows with the diff far more slowly than the diff does: a change twice the size needs one
or two more bullets in the reading order, not twice the prose. It fits one screen.

## The title

`<type>: <imperative lowercase summary> #<ticket-id>`, where `<type>` is `feat`, `fix` or `chore`
and the ticket ID is lowercase.

The summary names the behaviour, not the mechanism:

- `fix: stop the mounted tree touching the host's URL #int-732` — not "add an `ownsDocumentUrl`
  trait".
- `feat: let the host scope the picker to one entity type #int-788` — not "add an `entityType` prop".
- `feat: read the region from both claim names #int-784`.

## A repo PR template

A template's confirm-checkboxes — "Work item is referenced", "Changes are tested" — are not content
a reviewer acts on. Drop them and use the shape above. Keep a template section only when it asks for
something the shape does not already cover.

## Worked example

Pull request #386 was written long and then compacted; the first two cuts below came out of one
rule. The third is the decisions gate applied to a different change.

**A four-sentence paragraph became one bullet**, and the third case vanished with it:

> `VITE_TRUSTED_OPENER_ORIGINS` admits UpLink's origins on the importer deployment each one opens,
> rather than one origin per lifecycle file: `.env.staging` takes `app-dev` and `app-staging`,
> because UpLink's dev lifecycle has no importer of its own and opens the staging popup;
> `.env.production` takes `app` only; `.env.development` takes neither […]

became

> - `.env.*` — `VITE_TRUSTED_OPENER_ORIGINS` now lists the UpLink origins that open *that*
>   deployment's popup: staging admits `app-dev`, `app-staging` and `localhost:5173` (UpLink's dev
>   lifecycle has no importer of its own); production admits `app` alone, with no localhost entry.

The per-file enumeration is in the diff. What is not: that the list is keyed to the deployment the
opener drives, and that production carries no localhost entry on purpose. `.env.development` admits
nothing, so it is symmetry-filling.

**A whole `## Documentation` section — four paragraphs on a retitling, a moved subsection and a
corrected rationale — became one sentence:**

> The remaining doc changes correct the stated reason for the popup — it is the callback URL above,
> not an identity provider refusing to render embedded — and move the host-mode internals out of the
> download section.

The two host constraints from that section survived in full, in a `## Host contract` section, because
a host meets them as a successful OAuth round trip that produces no connection. Everything else in
it was prose about prose.

**A decision keeps its constraint and loses its route.** From the region reader of `#int-784`:

> We first looked at migrating the older tenants onto the new claim name, but that needs a deploy
> window we do not have this cycle. A mapping table in the gateway was the next candidate and was
> rejected as another hop on every request, so the reader now accepts either name.

became

> - The region reader accepts either claim name rather than one — the older tenants still emit only
>   the legacy name, and migrating them needs a deploy window this cycle does not have.

Migrating the tenants is named because it is what a reviewer reaches for on seeing a reader that
accepts two names for one value. The mapping table is not: nobody was considering it, and neither is
the order the two were weighed in. The constraint is the whole of what a reviewer needs to stop
reading the two-name reader as indecision.

## Related

`linear-tickets` owns the ticket text — what to build, and where its rationale goes. This skill owns
the PR text. Both surfaces carry a why, and they are different whys: the ticket's comment says why
the work is worth doing and why the requirement reads as it does, while a `## Decisions` bullet says
why the implementation took this shape. A body that reads like a ticket has usually imported the
first; link the ticket instead.
