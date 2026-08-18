---
name: datasnipper-mlflow
description: DataSnipper's MLflow tracking servers on *.devds.net — the environment matrix (devweu, prdweu, prdeus, stgweu, stgeus), VPN requirement, session-UUID filter syntax, the prdeus legacy-API quirk, and the mlflow_dump.py helper. Use whenever fetching or debugging MLflow traces, sessions or spans for the agents-and-tools stack, when a *.devds.net host or an env alias like devweu/prdweu/prdeus is named, or when an MLflow host fails to resolve.
---

# DataSnipper MLflow telemetry

- **VPN required.** All `*.devds.net` hosts only resolve over the corporate VPN;
  off-VPN you get `getaddrinfo failed` (DNS), not an HTTP error. `mlflow_dump.py`
  turns that into a "connect the corporate VPN" message. Transient DNS blips can
  also happen on-VPN — one retry is reasonable.
- **Environment matrix** (DataSnipper agents-and-tools). Source: infra
  `agentserver-<env>.tfvars` key `mlflow_tracking_uri`.

  | env alias | tracking URI | notes |
  |---|---|---|
  | `dev` / `devweu` | `https://mlflow-devweu.devds.net` | auto-swept |
  | `prd` / `prod` / `prdweu` | `https://mlflow-prdweu.devds.net` | auto-swept; default for plain `prd`/`prod` |
  | `prdeus` | `https://mlflow-prdeus.devds.net` | auto-swept; older MLflow (see per-trace note) |
  | `stg` / `stgweu`, `stgeus` | `https://mlflow-<env>.devds.net` | reachable via explicit `--env`; not auto-swept |
  | `deveus` | `https://mlflow-deveus.devds.net` | unreachable — TLS hostname mismatch; skip it |

  **Experiment ids are resolved at runtime, not hardcoded.** For `session`,
  `mlflow_dump.py` lists each env's experiments and searches those named `agent-server*`
  (e.g. `agent-server`, `agent-server-local-dev`) first, then sweeps the rest — so a
  renamed/renumbered experiment is still found. (This replaced a stale baked-in map:
  `devweu` was pinned to experiment `9`, but `9` is now a `disclosure-accuracy` experiment
  and the agent-server traces had moved to `1` (`agent-server-local-dev`), so a valid UUID
  falsely read as "no traces matched".) Pin one explicitly with `--experiment <id>` (one
  env, no sweep). With no `--env`, `session` auto-sweeps `devweu`→`prdweu`→`prdeus` and
  prints which matched; a "no traces matched" message now separates *reachable, 0 matches*
  from *couldn't reach* (the latter usually the VPN). To list an env's experiments by hand:
  `POST {uri}/api/2.0/mlflow/experiments/search {"max_results":1000}`.
- Chat-session UUID lives in trace `request_metadata` under `mlflow.trace.session`.
  Search filter: `metadata.\`mlflow.trace.session\` = '<uuid>'` (NOT `tags.`).
- For full per-trace span data, use `GET /api/3.0/mlflow/traces/get?trace_id=…` on
  the current weu servers. On the older `prdeus` server that endpoint 404s; the
  pre-3.3.0 path `GET /ajax-api/2.0/mlflow/get-trace-artifact?request_id=<tr-id>`
  (note the param is `request_id`, not `trace_id`) is the working one — it returns
  only a UI subset of spans (no TOOL/LLM spans; the full pydantic-ai history lives
  in each span's `mlflow.spanOutputs`). `mlflow_dump.py` falls back to it
  automatically, and its `messages <tr-id>` subcommand renders that history.
- Responses regularly exceed 10 MB (a single span can be ~14 MB). **Do not pull
  traces through `WebFetch`.** Use `~/.claude/scripts/mlflow_dump.py` instead — it
  writes compact projections to `~/.cache/mlflow-dump/` and only emits full span
  payloads on demand. Pick the env with `--env`:
  `mlflow_dump.py session <uuid> --env prd` / `trace <tr-id> --env prd` /
  `span <tr-id> <span-id> --env prd` / `messages <tr-id> --env prd` (`--env`
  overrides `MLFLOW_TRACKING_URI`; omit it on `session` to auto-sweep envs).
  The `/ds:analyze-mlflow <id> <env> <prompt>` slash command wraps this end-to-end.
