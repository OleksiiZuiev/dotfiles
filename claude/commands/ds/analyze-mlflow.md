---
description: Fetch and analyze MLflow traces for a session or trace, in any environment. Usage: /ds:analyze-mlflow <id> <env> <analysis prompt>
allowed-tools: Bash, Read
argument-hint: "<session-uuid|trace-id|url> <env> <analysis prompt>"
---

You are analyzing MLflow telemetry. The user provided:

**Arguments:** `{{$ARGUMENTS}}`

The trace payloads on this server routinely exceed 10 MB and the chat-session UUID is stored in `request_metadata.mlflow.trace.session` (not in `tags`). Do **not** use `WebFetch`. Use the local `mlflow_dump.py` helper which writes compact projections to `~/.cache/mlflow-dump/` and only emits full span payloads on demand. All `*.devds.net` hosts require the corporate VPN.

## Step 1 — Parse identifier + environment

Tokenize `$ARGUMENTS`:
- **First token** = the identifier.
- **Second token**, if it looks like an env (`dev`, `stg`, `prd`/`prod`, or an explicit `devweu|deveus|stgweu|stgeus|prdweu|prdeus`), = the environment. Otherwise there is no env token — default to `dev` and treat the second token onward as the analysis prompt.
- **Remaining tokens** = the analysis prompt.

Classify the identifier:
- Starts with `tr-` → **trace id** → use the `trace` subcommand.
- Starts with `http` → **URL**: extract the session UUID from the `#/experiments/{exp}/chat-sessions/{uuid}` fragment, and infer the env from the hostname (`mlflow-<env>.devds.net`). An explicit env token still overrides the inferred one.
- Otherwise → **session UUID** → use the `session` subcommand.

You do not need to resolve URIs or experiment ids yourself — `mlflow_dump.py --env` does that.

## Step 2 — Dump

Run via Bash, passing `--env`:

```
python ~/.claude/scripts/mlflow_dump.py session <uuid> --env <env>
# or, for a trace id:
python ~/.claude/scripts/mlflow_dump.py trace <trace_id> --env <env>
```

The script prints one absolute path per line on stdout. **Do not** read every file eagerly.

- **Connectivity:** if the script prints `Cannot resolve '<host>'. … connect the corporate VPN`, relay that to the user and stop — the VPN is off (or a transient DNS blip; one retry is reasonable).
- **Unknown experiment id:** if it reports the experiment id for the env is unknown (staging/eus are unverified), re-run adding `--experiment <id>` — it's the experiment named `agent-server` for that server.

## Step 3 — Read the right projection

**Session** (`session` subcommand): `Read` `index.md` first — a markdown table (trace_id, started_at, agent, duration_s, status, num_spans, input_tokens, output_tokens, cost_usd, prompt_preview), usually a few KB. Then decide which traces to drill into:
- Any trace with `status != OK` → always read.
- The trace whose `prompt_preview` matches the analysis prompt (or the most recent if vague) → read.
- Long-duration outliers when the prompt is about latency → read.

For each, `Read` `<trace_id>.tree.txt`: the span hierarchy with name, type (AGENT/LLM/TOOL/UNKNOWN), status, duration_ms, token counts on LLM spans, result previews on TOOL spans.

**Trace** (`trace` subcommand): there is no `index.md`; `Read` the single `<trace_id>.tree.txt` directly. `Read` `<trace_id>.meta.json` for full token usage, cost, branch, user, environment.

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

- **`status: OK` ≠ success.** A trace can be `state=OK` yet a user-facing failure (the error was caught and returned as a tool message). Scan **TOOL span outputs / result previews** for failure strings — `HTTP 4xx/5xx`, `Failed`, `Imported 0`, `error`, `timeout` — not just the span status. This is the most important heuristic.
- **Tolerate unusable inputs.** Request content is often redacted (`[Request content hidden for privacy]`) and some tool inputs are garbage (`<unserializable dict: Circular reference detected>`). Reconstruct intent from the *tool calls + their outputs + the final assistant message*, not from inputs alone.
- **Cache-aware tokens.** A large `input_tokens` total usually includes big `cache_read` + `cache_creation` components; the agent loop re-sends a large base context across its LLM calls. Report the cache read/creation split and the re-send pattern, not just the raw input total. `cost` is often empty (`{}`) — report tokens + cache split rather than inventing a cost.
- **Precise language.** Distinguish **conversation turns** (one turn ≈ one trace here) from **traces** from **LLM calls** (the agent-loop steps within a trace — one trace can make many). Say which you mean.

All citations should reference the on-disk file paths (`<trace_id>.tree.txt`, span json) so the user can verify.
