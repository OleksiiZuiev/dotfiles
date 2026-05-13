---
description: Fetch and analyze MLflow traces for a chat session. Usage: /ds:analyze-mlflow <url-or-session-uuid> <analysis prompt>
allowed-tools: Bash, Read
argument-hint: "<url-or-session-uuid> <analysis prompt>"
---

You are analyzing MLflow telemetry. The user provided:

**Arguments:** `{{$ARGUMENTS}}`

The trace payloads on this server routinely exceed 10 MB and the chat-session UUID is stored in `request_metadata.mlflow.trace.session` (not in `tags`). Do **not** use `WebFetch`. Use the local `mlflow_dump.py` helper which writes compact projections to `~/.cache/mlflow-dump/` and only emits full span payloads on demand.

## Step 1 — Parse the identifier

Take the first whitespace-delimited token from `$ARGUMENTS` as the identifier; everything after it is the analysis prompt.

- If the identifier starts with `http`, extract the session UUID and experiment id from the URL fragment: `#/experiments/{exp_id}/chat-sessions/{uuid}`.
- Otherwise, treat the identifier directly as a session UUID and default the experiment id to `9`.

## Step 2 — Dump the session

Run via Bash:

```
python ~/.claude/scripts/mlflow_dump.py session <uuid> --experiment <exp_id>
```

The script prints one absolute path per line on stdout — one for `index.md`, one for `summary.json`, and one `<trace_id>.tree.txt` per trace in the session. **Do not** read every tree file eagerly.

`Read` `index.md` first. It is a markdown table: trace_id, started_at, agent, duration_s, status, num_spans, input_tokens, output_tokens, cost_usd, prompt_preview. The whole file is typically a few KB.

## Step 3 — Drill into interesting traces

Decide which traces to read trees for based on the user's analysis prompt and the index. Heuristics:
- Any trace with `status != OK` → always read.
- The trace whose `prompt_preview` matches the user's analysis prompt (or the most recent trace if the prompt is vague) → read.
- Long-duration outliers when the user is asking about latency → read.

For each, `Read` `<trace_id>.tree.txt`. Each tree file shows the span hierarchy with name, type (AGENT / LLM / TOOL / UNKNOWN), status, duration_ms, plus token counts on LLM spans and result previews on TOOL spans.

If you need trace-level metadata (full token usage, cost breakdown, branch, user, environment), `Read` `<trace_id>.meta.json` — also tiny.

## Step 4 — Drill into a span (only if necessary)

If the tree points at a single suspicious span (the failing tool call, the unexpectedly large LLM response, etc.) and you need the actual payload, look up the `span_id` from `<trace_id>.spans.json` (the indexed list) and run:

```
python ~/.claude/scripts/mlflow_dump.py span <trace_id> <span_id>
```

It prints the path to a single-span JSON containing `inputs`, `outputs`, `attributes`, `events`. `Read` that file. This is the only intentionally large read in the whole flow — skip it unless a specific span needs it.

## Step 5 — Synthesize the analysis

Apply the user's prompt to the on-disk data. Structure the response as:

1. **Session summary** — how many traces, agents involved, overall status, time range, total tokens/cost.
2. **Analysis** — answer the user's prompt directly, citing trace ids and span indexes where evidence lives.
3. **Notable details** — errors, outliers, or interesting patterns worth flagging even if not asked about.

All citations should reference the file paths on disk (`<trace_id>.tree.txt`, span json) so the user can verify.
