# Plan home: Linear document

Read by `/plan-new`, `/plan-update`, `/plan-close` and `/plan-next` for a plan whose `home` in `plan list --json` is `linear-doc`. The `plan` CLI reads such a plan (`plan --help`); this file says how to write one. Every write here is outward-facing: run it only after the command's diff is confirmed, exactly as shown there.

## Shape

- **The document** is the plan. Its `locator` is the document's URL. Its content follows the vault plan note's sections (`## Context`, `## Design`, `## Tasks`, `## Open questions`), written for org readers by the stand-alone rule of the `linear-tickets` skill. `## Tasks` lists the member tickets, one per line, as `- [INT-12](<ticket URL>)`: IDs only, never statuses. A ticket ID anywhere in that section counts as a member.
- **Each member ticket** ends its body with the `Workspace:` and `Plan:` lines of the `linear-tickets` skill. `Plan:` carries the document's URL.
- **Blockers** are Linear's own "blocks" relations, not the order of `## Tasks`.

## Writes

Each write is one MCP call; the diff shows the call with its arguments.

| Change | Call |
| --- | --- |
| Create the document | `save_document` with `title`, `content` and one parent: `team` or `project` |
| Create a ticket | `save_issue` with `team`, `title`, `description` ending in the two lines, and `blockedBy` |
| List a ticket in the plan | `save_document` with `id` and a `patch` that inserts its line into `## Tasks` |
| Change a ticket's blockers | `save_issue` with `id` and `blockedBy` or `removeBlockedBy` |
| Cancel a ticket | `save_issue` with `id` and `state: "canceled"`; it stays listed |
| Detach a ticket | `save_issue` with `id` and a `patch` removing its `Plan:` line, then `save_document` with a `patch` removing its `## Tasks` line |
| Edit the document's prose | `save_document` with `id` and a `patch` |

A ticket is created after the document, because its `Plan:` line needs the document's URL. The real IDs go into `## Tasks` after the tickets exist. A blocker is created before the tickets it blocks, so `blockedBy` can name it.

## After writing

Run `plan status <slug>`; it reads Linear live. Drift it prints names the side to fix: the document's `## Tasks` list or the ticket's `Plan:` line.
