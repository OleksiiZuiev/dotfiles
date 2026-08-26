# Steering overlay — agents-and-tools

Personal user-level steering for this repo. Maintained by /ds:distill;
consumed by /ds:work-on (Step 2.7 → Plan directives, Step 3.5 → Enforced).

## Enforced (post-gen check)
<!-- Mechanical, recurring rules the Step 3.5 post-gen check enforces hard. -->
- Gate and branch on typed constants (an enum value, a command's `.id`), never on bare string literals.            (src: eacb2e67, b542ffdc; AGENTS.md-backed)
- Never log user-identifiable data (PII). Application logs flow to Grafana and are retained beyond our policy window; MLflow trace data is fine (kept ~1 day). The risk is the Grafana sink, not MLflow.            (src: 75ce56ca, 265f961d; PR #645 retention correction)

## Plan directives (plan self-check)
<!-- Structural rules folded into the Step 2.7 plan self-check. -->
- Model contracts tightly: return a concrete type and raise on a genuine miss rather than handing back `Optional` or an empty sentinel; make a parameter required when the contract guarantees its presence — then delete the now-dead defensive branches at the call sites.            (src: 938c722f, 395e011d, ba6f932c)
- Define a shared pattern, regex, constant, or helper once in its owning module and import it; never redefine it per consumer — copies drift. Keep an extracted helper's contract narrow (it takes pre-built domain types; callers keep their own adapter/build logic).            (src: 4c958389, 1ccf104f)
- Keep LLM guidance / system prompts lean: state the gist; drop MANDATORY/FORBIDDEN scaffolding and defensive "ignore your heuristic" paragraphs; don't dictate narration the tool's own instructions already govern.            (src: 40ec3a11; PR #645)

## Distill ledger
<!-- /ds:distill bookkeeping for re-run dedup. No consumer reads this section. -->
### Harvested sources
- branch `feat/int-491-import-command` @ HEAD `7a26b819` — all of `origin/main..HEAD` consumed 2026-06-30. On re-run, treat every commit reachable from `7a26b819` as already-harvested; only newer commits are fresh.
- pr#645 — all inline review comments authored by `oleksii-zuiev_dasn` (consumed 2026-06-30).
- ticketctx:INT-491 — all sessions through 2026-06-25 (Key Decisions consumed 2026-06-30).
- Key evidence SHAs (belt-and-suspenders for SHA-match dedup): b6fb1e1c, 971ef59f, 57723017, 4bcb430b, cc9985fe, dc805bfb, c7186c4a, e94533b5, a589a6bd, 21122645, efc4d42b, 15310168, d786a286, 0e5da482, b5af6b94, 40ec3a11, be5d3fc7, 938c722f, 395e011d, ba6f932c, 21a256ff, eacb2e67, b542ffdc, c153674f, 4c958389, 1ccf104f, 75ce56ca, 265f961d, 9101a69c, f463da23, 265fe464, ced7b252, b03416c5, c5222497, d023e44d.
### Dismissed rules
<!-- Skipped/deferred candidates are NOT listed here — they re-surface next run. Only true dismissals. -->
- (none)
