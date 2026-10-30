---
name: polish-triage
description: How to decide one finding or review comment on its merit — assess it, price the fix, print the decision card, take the decision from the user (interactive) or from the routing table (auto), and commit each applied fix on its own. Source-agnostic: the caller owns where findings come from and where decisions are written. Use whenever a procedure addresses findings one by one, including `polish-findings`.
---

# Deciding a finding on its merit

The caller hands over one finding with its code context. This skill returns a decision. It reads no
tracker and writes no file; the caller stores the decision.

## Assess

Read the code at the finding's location as it is now, not as it was when the finding was written.

- **Merit**: does the finding identify a real improvement, or is it a style preference, already
  handled, or not worth doing? A `smell` may have no clean fix; a `question` may need no code change.
- **Price the fix**: name what it adds (a concept, a cache, a memo, an indirection, a new invariant
  someone has to keep) set against what it removes. A fix that strictly removes code or work is free:
  say so and move on. A fix that adds a concept has to buy something you can size, so a multiplier
  ("once per row", "N times per render") is not a size; work out what the operation already costs
  before agreeing. Check that every branch of the fix can execute; a fallback that can never run is
  complexity bought for nothing.
- **Flag disagreement** with reasoning when the finding is wrong or the current code is correct.
- **Propose a concrete fix**, which may differ from the finding's own. For a `question` with no
  implied action, propose marking it answered.
- **Stance**, exactly one of: `strong agree`, `agree with modifications`, `minor/style preference`,
  `not worth it — the problem is real, the fix costs more than it buys`, `disagree — here's why`.
  `minor/style preference` is for a fix that costs nothing; a fix that adds code or a concept for a
  matter of taste is `not worth it`.

## The decision card

Print the card as chat text before every question. The user decides from the card alone: an assessment
that stays in your reasoning is invisible to them. Never ask about a finding whose card is not on
screen.

````
### Finding {n} of {total} — {path}:{line}

**Original**
> {the finding's text, verbatim — every line quoted}

```{lang}
{the code at the location, with a few lines of context}
```

**Analysis** — {merit; what the fix adds set against what it removes; any disagreement or better
alternative}
Stance: {stance}

**Recommendation** — {the concrete fix: what changes, in which files, how it is tested. For a
`not worth it` or `disagree` stance: why no change, and what you would do if asked}
````

A finding already carrying an earlier assessment (status `escalated`) also shows that assessment, quoted
under the original, so the user sees what the agent concluded before it asked.

## Interactive decision

`AskUserQuestion`, one finding at a time, question text `Finding {n} of {total} — {path}:{line}:
decision?`. The tool takes four options and appends "Other", so offer exactly:

- **Approve fix**: implement as proposed.
- **Discuss**: ask a question or push back. No decision is recorded; answer in chat, stay read-only,
  re-print the Recommendation if the fix changed, and ask again. Never advance on a Discuss.
- **Skip**: defer to a later run; ask for a one-line rationale.
- **Dismiss**: considered, no change warranted; the assessment is the rationale.

"Other" is the modification: the typed text is the new intent, so restate the revised fix and ask this
finding again.

After an Approve, when the same fix pattern repeats across the remaining findings, ask once whether to
apply it to all N. Each batched fix is still its own commit.

## Auto decision

Auto mode asks nothing and prints no card. The finding is routed by this table, evaluated top to
bottom; the first match wins.

| # | Finding | Decision |
|---|---|---|
| 1 | category `question` | escalated |
| 2 | `Location` lies on lines last changed by a fix the finding's own review already contained (overlap rule below) | escalated |
| 3 | `Impact: user-facing`, stance strong agree, agree with modifications or minor | applied |
| 4 | `Impact: user-facing`, any other stance | escalated |
| 5 | `confident`, stance strong agree, agree with modifications or minor | applied |
| 6 | `confident`, `Severity: high` or absent, stance not worth it or disagree | escalated |
| 7 | `confident`, any other case | dismissed, the assessment is the reason |
| 8 | `smell`, `Severity: medium`, `high` or absent | escalated |
| 9 | `smell`, `Severity: low` | dismissed, reason `low-severity smell, not surfaced` |

- A missing `Severity` counts as `high`, so a finding written by hand is never silently dropped.
- An applied fix under `agree with modifications` is recorded `modified`; the other applied stances are
  recorded `applied`.
- An escalated finding keeps its assessment (stance, reason and, when there is one, the fix it would
  take) so the interactive card can show it.

**Overlap rule.** The caller passes the finding's **reviewed head**, the commit its review ran
against, and the commit SHAs in the file's `applied (<sha>)` and `modified (<sha>)` statuses. Before
editing for the finding, run `git blame --porcelain -L <first>,<last> -- <path>` on its `Location`.
When a blamed commit is one of those SHAs and an ancestor of the reviewed head
(`git merge-base --is-ancestor <blamed> <reviewed head>`), the review already saw that fix and still
found something on the same lines: the loop is circling, so escalate. A fix committed after the
reviewed head is not what the review saw, so it is no overlap; the assessment reads the code as it is
now. A finding with no reviewed head compares against the SHAs recorded when the run starts. A
`Location` that lists several lines or ranges is blamed range by range, and any hit escalates. A
finding with no line number, or on a path that does not exist, has no overlap.

## Commit rule

One commit per applied fix, staging only that fix's files:

```bash
git add <files>
git commit -m "$(cat <<'EOF'
Polish: <brief description>

- <what changed>
- Addresses finding <id> (<source>)
EOF
)"
```

End the message with the `Co-Authored-By` trailer the session specifies. Capture the short SHA for the
caller. Never push.

Honor the conventions files nearest each edited file (every `CLAUDE.md` and `AGENTS.md` from its
directory to the repo root) and the global style rules.
