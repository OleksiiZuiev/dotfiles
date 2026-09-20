---
name: mutation-testing-triage
description: How to triage surviving mutants from a mutation-testing run — judge each survivor on whether it maps to a realistic harmful regression rather than on whether a test could kill it, test only the plausible-harm ones, and document the rest. Use whenever a mutation-testing report is being reviewed or acted on, a mutation score is being raised, or Stryker, mutmut, Pitest, Cosmic Ray or a similar tool has produced surviving mutants.
---

# Triaging mutation-testing survivors

A mutation-testing tool injects small deliberate defects (flip `>` to `>=`, delete a statement,
invert a boolean, swap a return value) and re-runs the suite. A mutant that **survives** means no
test noticed that behaviour change.

A survivor is a hint, not a defect. The tool cannot tell whether the change it made matters.

## The rule

Judge each survivor on whether the injected change maps to a **realistic, harmful regression** — not
on whether a test could be written to kill it. A test can always be written; that is not the question.

Chasing a 100% mutation score produces tests that exist to satisfy the tool, which then have to be
maintained by people who cannot tell what behaviour they protect.

## Procedure

1. **Read each survivor as a bug report.** Ask: if a teammate made exactly this change, would anything
   a caller depends on break? Would you catch it in review? Would a user notice?
2. **Write a test only for the plausible-harm survivors.**
3. **Prove the new test works.** Re-inject that mutant, confirm the test fails, then revert the mutant.
   A test that passes against the injected mutant has not killed it, whatever the score says.
4. **Document the survivors you leave**, each under the reason it was left.

## The survivors worth leaving

- **Equivalent** — the mutant does not change observable behaviour at all, so no test can kill it.
  A changed constant that is multiplied by zero downstream; a reordering with no dependency between
  the lines.
- **Redundant** — a different test already covers the behaviour through another path, and killing
  this mutant specifically would only duplicate that coverage.
- **Un-killable in practice** — killing it would need a test that reaches past your own contract into
  a dependency's internals, or that pins an implementation detail you want free to change.

Record which category each left-behind survivor falls into. The record is what stops the next run
from re-litigating the same triage.
