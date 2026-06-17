---
description: Fetch and analyze MLflow traces for a session or trace, in any environment. Usage: /ds:analyze-mlflow <id> <env> <analysis prompt>
allowed-tools: Bash, Read, mcp__grafana__query_loki_logs, mcp__grafana__list_loki_label_values, mcp__grafana__list_datasources
argument-hint: "<session-uuid|trace-id|url> <env> <analysis prompt>"
---

You are analyzing MLflow telemetry. The user provided:

**Arguments:** `{{$ARGUMENTS}}`

The trace payloads on this server routinely exceed 10 MB and the chat-session UUID is stored in `request_metadata.mlflow.trace.session` (not in `tags`). Do **not** use `WebFetch`. Use the local `mlflow_dump.py` helper which writes compact projections to `~/.cache/mlflow-dump/` and only emits full span payloads on demand. All `*.devds.net` hosts require the corporate VPN.

## Step 1 — Parse identifier + environment

Tokenize `$ARGUMENTS`:
- **First token** = the identifier.
- **Second token**, if it looks like an env (`dev`, `stg`, `prd`/`prod`, or an explicit `devweu|deveus|stgweu|stgeus|prdweu|prdeus`), = the environment. Otherwise there is no env token — **omit `--env` entirely** (do *not* substitute `dev`) and treat the second token onward as the analysis prompt. With no `--env`, the `session` subcommand auto-sweeps the envs with known experiment ids (`devweu`→`prdweu`→`prdeus`) and reports which matched.
- **Remaining tokens** = the analysis prompt.

Classify the identifier:
- Starts with `tr-` → **trace id** → use the `trace` subcommand.
- Starts with `http` → **URL**: extract the session UUID from the `#/experiments/{exp}/chat-sessions/{uuid}` fragment, and infer the env from the hostname (`mlflow-<env>.devds.net`). An explicit env token still overrides the inferred one.
- Otherwise → **session UUID** → use the `session` subcommand.

Environment notes (you don't resolve URIs/experiment ids yourself — `mlflow_dump.py --env` does):
- Known experiment ids: `dev`/`devweu` = `9`; `prd`/`prdweu` = `1`; `prdeus` = `1` (all named `agent-server`).
- `prdeus` is a real prod region (US) on an **older MLflow** — fully supported (see Step 2). `prdweu` is the default for plain `prd`/`prod`.
- `deveus` is **unreachable from here** (TLS hostname mismatch on its cert) — skip it.
- `stgweu`/`stgeus` experiment ids are unverified and are **not** auto-swept; target them explicitly with `--env <name> --experiment <id>`.

## Step 2 — Dump

Run via Bash. Pass `--env <env>` when you have one; **omit it** when the user gave no env (the `session` subcommand then auto-sweeps `devweu`→`prdweu`→`prdeus`):

```
python ~/.claude/scripts/mlflow_dump.py session <uuid> [--env <env>]
# or, for a trace id (env is needed here — trace has no sweep):
python ~/.claude/scripts/mlflow_dump.py trace <trace_id> --env <env>
```

The script prints one absolute path per line on stdout. **Do not** read every file eagerly.

- **Which env matched:** on a successful sweep the script prints `matched env: <env> (experiment <id>)` to stderr — note it and use that same `--env` for any follow-up `trace`/`span`/`messages` calls.
- **No match:** if it prints `no traces matched … in any swept env`, the session isn't in the auto-swept envs. For staging/eus, retry with `--env <name> --experiment <id>` (the experiment named `agent-server`). Otherwise re-check the id with the user.
- **Connectivity:** if the script prints `Cannot resolve '<host>'. … connect the corporate VPN`, relay that to the user and stop — the VPN is off (or a transient DNS blip; one retry is reasonable).
- **Legacy server (prdeus) is handled for you.** prdeus runs an older MLflow: the `api/3.0` per-trace endpoint 404s, so the script transparently falls back to the `ajax-api` get-trace-artifact endpoint. You no longer hand-hit it. Those spans are a **UI subset** (no separate TOOL/LLM spans) — see Step 3.5.
- **Transcript projection:** `python ~/.claude/scripts/mlflow_dump.py messages <trace_id> --env <env>` writes `<trace_id>.messages.txt`, the conversation reconstructed from `spanOutputs` — used in Step 3.5 when the span tree is sparse.

## Step 3 — Read the right projection

**Session** (`session` subcommand): `Read` `index.md` first — a markdown table (trace_id, started_at, agent, duration_s, status, num_spans, input_tokens, output_tokens, cost_usd, prompt_preview), usually a few KB. Then decide which traces to drill into:
- Any trace with `status != OK` → always read.
- The trace whose `prompt_preview` matches the analysis prompt (or the most recent if vague) → read.
- Long-duration outliers when the prompt is about latency → read.

For each, `Read` `<trace_id>.tree.txt`: the span hierarchy with name, type (AGENT/LLM/TOOL/UNKNOWN), status, duration_ms, token counts on LLM spans, result previews on TOOL spans.

**Trace** (`trace` subcommand): there is no `index.md`; `Read` the single `<trace_id>.tree.txt` directly. `Read` `<trace_id>.meta.json` for full token usage, cost, branch, user, environment.

## Step 3.5 — Sparse spans / legacy server

If a `tree.txt` has **no TOOL/LLM spans** and only a couple of nodes (typical on the older **prdeus** server, where spans are a UI subset), the conversation is **not** in the span tree — the full pydantic-ai message history lives inside the root / `Agent.run` span's `mlflow.spanOutputs` attribute (a JSON-encoded message list, often double-wrapped as `{"output": "<json string>"}`).

Don't hand-parse it — run:

```
python ~/.claude/scripts/mlflow_dump.py messages <trace_id> --env <env>
```

and `Read` the resulting `<trace_id>.messages.txt`. It's a compact transcript, one line per message part, tagged by `part_kind`:
- `[system]` (system-prompt, hard-truncated), `[user]` (user-prompt), `[assistant]` (text)
- `[tool-call] <name>(<args>)` and `[tool-return] <name> → <content>` — the tool args/returns carry the failure signals (e.g. `service_unavailable`, `error_code`)
- `[retry]` (retry-prompt — pydantic-ai retried the model after a tool error)

Read the tool-call/tool-return pairs the way you'd read TOOL spans in Step 3, and apply the Step 5 heuristics to them.

## Step 4 — Drill into a span (only if necessary)

If the tree points at one suspicious span, look up its `span_id` from `<trace_id>.spans.json` and run:

```
python ~/.claude/scripts/mlflow_dump.py span <trace_id> <span_id> --env <env>
```

It prints the path to a single-span JSON (`inputs`, `outputs`, `attributes`, `events`). **Spans can be huge** (a root span here was ~14 MB — full message history). Do **not** `Read` a large span whole — that blows the token cap. Instead extract the field you need with a tiny `python -c` (e.g. read the JSON and print one key, or its length), and only `Read` small spans directly.

## Step 5 — Synthesize the analysis

Apply the user's prompt to the on-disk data. Structure:

1. **Session/trace summary** — traces, agents involved, overall status, time range, tokens.
2. **Analysis** — answer the prompt directly, citing trace ids and span indexes where evidence lives.
3. **Notable details** — errors, outliers, patterns worth flagging.

Apply these heuristics (each one bit us in a real prod analysis):

- **`status: OK` ≠ success.** A trace can be `state=OK` yet a user-facing failure (the error was caught and returned as a tool message). Scan **TOOL span outputs / result previews** (or the `[tool-return]` lines from Step 3.5) for failure strings — `HTTP 4xx/5xx`, `Failed`, `Imported 0`, `error`, `timeout`, `service_unavailable` — not just the span status. This is the most important heuristic.
- **A tool outage/timeout is a *lead*, not a *conclusion*.** When a tool returns an outage / timeout / "unavailable" / `error_code`, or returns empty after retries, **do not finalize the root cause from MLflow + source code alone** — that exact reasoning produced a *wrong* root cause once (see below). Go to **Step 6** and confirm against cross-service logs first. *Real case:* the agent reported "integration service unavailable" off a `service_unavailable` tool result; logs showed the integration service actually returned **HTTP 200** and the real failure was a **gateway 504** in between.
- **Backend 200 ≠ client success.** A gateway/ingress (~20s timeout) can return **504** to the caller while the backend keeps working and logs **200** seconds later. If a timeout is in play, read **both** sides (Step 6) — one shows 200, the other the 504.
- **Retry inflation.** The agent-server's integrations HTTP client retries (`max_attempts=3`, on 429/502/503/504/529 + transport errors). **One** logical tool call can appear as **3 identical backend requests** (same query/correlation_id) in the logs — don't count them as 3 user actions.
- **`correlation_id` is not in MLflow.** The per-turn `X-Correlation-ID` is generated frontend-side and isn't in trace metadata — you can only read it *out of the logs* (Step 6), never recover it from MLflow.
- **Tolerate unusable inputs.** Request content is often redacted (`[Request content hidden for privacy]`) and some tool inputs are garbage (`<unserializable dict: Circular reference detected>`). Reconstruct intent from the *tool calls + their outputs + the final assistant message*, not from inputs alone.
- **Cache-aware tokens.** A large `input_tokens` total usually includes big `cache_read` + `cache_creation` components; the agent loop re-sends a large base context across its LLM calls. Report the cache read/creation split and the re-send pattern, not just the raw input total. `cost` is often empty (`{}`) — report tokens + cache split rather than inventing a cost.
- **Precise language.** Distinguish **conversation turns** (one turn ≈ one trace here) from **traces** from **LLM calls** (the agent-loop steps within a trace — one trace can make many). Say which you mean.

All citations should reference the on-disk file paths (`<trace_id>.tree.txt`, `<trace_id>.messages.txt`, span json) so the user can verify.

## Step 6 — Cross-service log correlation (when a tool failed/timed out)

**Trigger:** the trace shows a tool-level failure, outage, timeout, a "down"/"unavailable" user-facing message, an `error_code`, or empty results after retries. **MLflow alone is not enough to state root cause in these cases** (§Step 5, "a tool outage is a lead"). **Gate:** requires the Grafana MCP tools + corporate VPN. If the Grafana MCP isn't available, say so and give the analysis as a *hypothesis to confirm with logs*, not a conclusion.

Verify the datasource exists first: `mcp__grafana__list_datasources` → expect Loki **`grafanacloud-logs`** (uid `grafanacloud-logs`). Query with `mcp__grafana__query_loki_logs` (and `mcp__grafana__list_loki_label_values` to discover values).

### 6a. Services (BOTH have decoy streams — the #1 time-sink)

| What | Correct `service_name` | Decoy to AVOID |
|---|---|---|
| Agent-server (Python) | **`excel-agent-server`** (namespace `mm`, team MandM) | `agent-server-eus`/`-weu`/`-eau` — session not there |
| Integration service (.NET) | **`integrations-api`** (namespace `dex`) | `integrations-api-prd-eus` — synthetic health-probes only |
| Frontend RUM | `excel-agent-chat-ui` | — browser events; `page_url` has the chat UUID; gives user region/timing |

A **prdeus** session ⇒ the **eus** instances of both services (`cloud_region="eus"`).

### 6b. Join keys (MLflow → logs)

- **`session_id`** = the MLflow `mlflow.trace.session` UUID. A **structured-metadata field** in both services — filter `| session_id="<uuid>"`, **NOT** `|= "<uuid>"` (substring match fails; the value is in metadata, not the log body). Primary join, spans all turns.
- **`trace_id`** = an MLflow trace id **with the `tr-` prefix stripped** (`tr-eae69eef…` → `trace_id="eae69eef…"`). Cleanest **per-turn** join for the integration-call layer: the integrations sub-agent's trace_id == the `trace_id` field on both the integration-service request logs and the agent-server retry/outage warnings for that turn. (Caveat: the excel-agent *root* trace uses a different trace_id than the agent-server's "Processing user prompt" span — for the top-level turn, join on `session_id`.)
- **`correlation_id`** (`X-Correlation-ID`) is per-turn, frontend-generated, and **not in MLflow** — only readable from the logs (a structured-metadata field on integration-service request lines).

### 6c. Time window + queries

Always pass **explicit RFC3339 start/end** (Loki defaults to the last 1h). Derive the window from the MLflow trace `started_at` + `duration_s`, padded ±1 min.

- **Integration-service request outcomes** (status + duration per call):
  `{service_name="integrations-api"} | session_id="<uuid>" |= "responded"`
  → e.g. `HTTP GET /v1/agent/.../entities/file responded 200 in 22322ms`. The search query param is redacted (`url_query_query=[REDACTED]`); the real query shows as `query=` on the `DataImportService` "Listed N File…" line (same trace_id).
- **Agent-server retry/outage signals** (the smoking gun):
  `{service_name="excel-agent-server"} |~ "Transport retr|service outage|exhausted"`
  → fields `error_type` (e.g. `HTTP504`), `client_name`, plus lines like `list_entity_files service outage: HTTPStatusError: Server error '504 Gateway Time-out' for url '…?query=k-1…'` (this line carries the un-redacted URL incl. query).
- **Agent-server turn boundaries / token usage:**
  `{service_name="excel-agent-server"} | session_id="<uuid>"`
  → `Processing user prompt`, `Recorded message usage` (RunUsage incl. cache split + tool_calls), `WebSocket disconnected` (close_code).

### 6d. Interpreting (see Step 5 for the heuristics)

Read **both** sides before concluding: the integration service may log **200** while the agent-server logs a **504** from the gateway (`api-eastus.datasnipper.com`, ~20s timeout) in between — that gap is the failure. And remember **retry inflation**: one tool call → up to 3 identical backend requests. Only after the logs corroborate (or correct) the MLflow lead do you state the root cause.
