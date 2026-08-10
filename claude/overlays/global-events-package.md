# Steering overlay — global-events-package

Personal user-level steering for this repo. Maintained by /ds:distill;
consumed by /ds:work-on2 (Step 2.7 → Plan directives, Step 3.5 → Enforced).

## Enforced (post-gen check)
<!-- Mechanical, recurring rules the Step 3.5 post-gen check enforces hard. -->
- When you rename or remove something, grep the whole repo and fix every reference in the same change — source, tests, comments, log message strings, docstrings and the README, not just the call sites the type checker finds.            (src: 5b5477a existed only to finish fc789dd's sweep; e15f90e left a stale log message)
- For every name in `__all__`, the types naming its parameters must be exported too — a consumer following a documented construction path has to be able to name every type on it.            (src: pr#32-comment:3735502255 → 5908aad)

## Plan directives (plan self-check)
<!-- Structural rules folded into the Step 2.7 plan self-check. -->
- When three or more fields and the methods that mutate them form one concept, give the concept its own type; the host class keeps one field and its constructor signature is unchanged.            (src: 3 of 12 PR comments converged on it → 3814be8 dropped 5 attributes and 3 methods)
- Don't add a parameter, callable indirection or closure whose argument never varies across calls; if the value is fixed at construction, read it from the field at the point of use.            (src: ef30f46 dropped `Callable[[float], …]` for a zero-arg thunk)

## Distill ledger
<!-- /ds:distill bookkeeping for re-run dedup. No consumer reads this section. -->
### Harvested sources
- 29476f984ef9223271a46ae0407049cca0195234
- 3814be8c4c1c0d83dc735423834efd1b28f522e7
- fe2bf088af9e02ad5a4c7663c5a945149d0a7700
- 5908aada75d2cd113f0479eb40d67e3e784d8b7e
- f7a9eaf1443ce7f48c97b3d3c6db25672bb7ceb2
- c3e96cd118ebc6bb21a6dd205e638c6d52a2160b
- c749a89547c151d3643188cff5cda8b6b59ef91f
- ac3f706cb55a2490996efb0c91130c8e24de691b
- ea884771e1e79340de1fac0c662be01554b7fe52
- 3a3110f434eecf8b2df6e9aa8e64113ba9955b3c
- fc789dde599e1dc88e55e126c456f795298d0a3d
- 5b5477a998b05c0f8eff3628f62c17b76ed8845f
- e15f90e6741628cb71d42eb3b8498555a1e15264
- ef30f4676735460b9a81f19eac90be8206ea323a
- pr#32-comment:3735472912
- pr#32-comment:3735502255
- pr#32-comment:3735539205
- pr#32-comment:3735551445
- pr#32-comment:3735568586
- pr#32-comment:3735572702
- pr#32-comment:3735581255
- pr#32-comment:3735590835
- pr#32-comment:3735625977
- pr#32-comment:3735639564
- pr#32-comment:3735646255
- pr#32-comment:3735666550
- pr#32-comment:3735673194
- ticketctx:INT-601@2026-08-06 15:30
- ticketctx:INT-601@2026-08-06 16:05
- ticketctx:INT-601@2026-08-07 10:15
- ticketctx:INT-601@2026-08-07 14:20
- ticketctx:INT-601@2026-08-10 make-the-two-level-enqueue-timeout-readable
- ticketctx:INT-601@2026-08-10 sweep-the-remaining-deadline-prose
- ticketctx:INT-601@2026-08-10 remove-the-dropped-event-running-total
- ticketctx:INT-601@2026-08-10 simplify-how-the-producers-bound-reaches-the-send
### Dismissed rules
- Name a test for the assertion it actually makes / rename when the named behaviour isn't observable at the seam — redundant with the approved vacuous-assertion rule plus the existing global test-naming rule.
- Prefer placement that makes an invariant structural over a guard clause that re-establishes it — single instance, downstream of a scope change, too vague for a plan self-check to act on.
