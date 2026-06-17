#!/usr/bin/env python3
"""Dump compact projections of MLflow traces/sessions to disk.

The goal is to keep Claude's context window small: pull big trace payloads
once, render a skeleton tree + meta JSON to disk, and only emit full
per-span payloads on explicit request.

Four subcommands:
  session  <uuid>          — list all traces of a chat session + tree per trace
  trace    <trace_id>      — full tree + meta + span index for one trace
  span     <trace_id> <id> — single span's full payload (inputs/outputs/attrs)
  messages <trace_id>      — pydantic-ai conversation transcript (from spanOutputs;
                             use when the span tree is sparse, e.g. older servers)

Environment:
  --env dev|stg|prd (or devweu|deveus|stgweu|stgeus|prdweu|prdeus) resolves the
  tracking URI and, for `session`, the experiment id. --env overrides
  MLFLOW_TRACKING_URI. When --env is omitted (or a session isn't found in the
  given env), `session` auto-sweeps the envs with known experiment ids
  (devweu, prdweu, prdeus) and reports which one matched.

Legacy servers:
  prdeus runs an older MLflow where api/3.0 per-trace fetch 404s; the helper
  transparently falls back to the ajax-api get-trace-artifact endpoint. Those
  spans are a UI subset (no TOOL spans) — the full message history lives in the
  spanOutputs attribute; the `messages` subcommand extracts it.

Defaults:
  --out  ~/.cache/mlflow-dump/<session_or_trace_id>/
  MLFLOW_TRACKING_URI env var (default https://mlflow-devweu.devds.net)
  --experiment   resolved from --env; omit both to auto-sweep (session only)

Stdlib only — no mlflow, no requests. Re-runs are cached unless --no-cache.
Every file written or hit-from-cache is printed (absolute path, one per line)
to stdout so the caller can `Read` it directly.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_TRACKING_URI = "https://mlflow-devweu.devds.net"
DEFAULT_CACHE_ROOT = Path.home() / ".cache" / "mlflow-dump"
TREE_FIELD_MAX = 1024
TOOL_OUTPUT_PREVIEW = 80
HTTP_TIMEOUT_SECONDS = 60
# `messages` transcript caps: system prompts are huge and rarely the point; tool
# args/returns carry the failure signals so they get a generous budget.
SYSTEM_PROMPT_MAX = 500
MESSAGE_CONTENT_MAX = 4000

# alias -> (tracking URI, experiment id or None when not yet verified).
# Source: agents-and-tools infrastructure agentserver-<env>.tfvars (mlflow_tracking_uri).
ENV_MATRIX: dict[str, tuple[str, str | None]] = {
    "devweu": ("https://mlflow-devweu.devds.net", "9"),
    "deveus": ("https://mlflow-deveus.devds.net", None),
    "stgweu": ("https://mlflow-stgweu.devds.net", None),
    "stgeus": ("https://mlflow-stgeus.devds.net", None),
    "prdweu": ("https://mlflow-prdweu.devds.net", "1"),
    "prdeus": ("https://mlflow-prdeus.devds.net", "1"),
}

# Canonical envs to auto-sweep for `session` (those with a verified experiment id),
# in priority order. deveus is excluded (TLS hostname mismatch — unreachable from here);
# stgweu/stgeus are excluded (experiment id unverified — reach them with --experiment).
SESSION_SWEEP_ENVS: tuple[str, ...] = ("devweu", "prdweu", "prdeus")
ENV_ALIASES: dict[str, str] = {
    "dev": "devweu",
    "stg": "stgweu",
    "stage": "stgweu",
    "staging": "stgweu",
    "prd": "prdweu",
    "prod": "prdweu",
}


def resolve_env(env: str) -> tuple[str, str | None]:
    """Map an env alias or canonical name to its tracking URI + experiment id."""
    key = env.strip().lower()
    canonical = ENV_ALIASES.get(key, key)
    if canonical not in ENV_MATRIX:
        known = ", ".join(sorted(ENV_MATRIX))
        aliases = ", ".join(sorted(ENV_ALIASES))
        raise ValueError(f"unknown env '{env}'. Known: {known} (aliases: {aliases})")
    uri, experiment = ENV_MATRIX[canonical]
    return uri.rstrip("/"), experiment


def resolve_env_or_exit(env: str) -> tuple[str, str | None]:
    try:
        return resolve_env(env)
    except ValueError as e:
        raise SystemExit(str(e))


def looks_like_trace_id(identifier: str) -> bool:
    return identifier.startswith("tr-")


def session_sweep_order(preferred: str | None = None) -> list[str]:
    """Canonical envs to try for a session search, most-likely first.

    Defaults to the verified-experiment-id envs (SESSION_SWEEP_ENVS). When an env
    is explicitly preferred, it leads the list (deduped) — even if its experiment
    id is unverified, because the caller may have pinned --experiment.
    """
    order = list(SESSION_SWEEP_ENVS)
    if preferred:
        canonical = ENV_ALIASES.get(preferred.strip().lower(), preferred.strip().lower())
        order = [canonical] + [e for e in order if e != canonical]
    return order


def effective_uri(args: argparse.Namespace) -> str:
    """--env wins over the inherited MLFLOW_TRACKING_URI, which wins over the default."""
    env = getattr(args, "env", None)
    if env:
        return resolve_env_or_exit(env)[0]
    return tracking_uri()


def connection_error_message(url: str, reason: object) -> str:
    """A DNS failure on a *.devds.net host almost always means the VPN is off."""
    if isinstance(reason, socket.gaierror) or "getaddrinfo failed" in str(reason):
        host = urllib.parse.urlparse(url).hostname or url
        return (
            f"Cannot resolve '{host}'. If this is a *.devds.net host, "
            f"connect the corporate VPN and retry."
        )
    return f"Connection failed for {url}: {reason}"


def tracking_uri() -> str:
    return os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI).rstrip("/")


class HttpError(Exception):
    """An HTTP error response, carrying the status code so callers can branch on it."""

    def __init__(self, code: int, body: str, url: str) -> None:
        super().__init__(f"HTTP {code} on {url}")
        self.code = code
        self.body = body
        self.url = url


def _http_get(url: str) -> bytes:
    """Raw GET. Raises HttpError on an HTTP status error; SystemExit on a DNS/VPN failure."""
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        raise HttpError(e.code, body, url)
    except urllib.error.URLError as e:
        raise SystemExit(connection_error_message(url, e.reason))


def http_get_json(url: str) -> dict[str, Any]:
    try:
        return json.loads(_http_get(url).decode("utf-8"))
    except HttpError as e:
        raise SystemExit(f"HTTP {e.code} on {e.url}\n{e.body}")


def search_session_traces(experiment_id: str, session_uuid: str) -> list[dict[str, Any]]:
    filter_str = f"metadata.`mlflow.trace.session` = '{session_uuid}'"
    qs = urllib.parse.urlencode({
        "experiment_ids": experiment_id,
        "filter": filter_str,
        "max_results": "200",
    })
    url = f"{tracking_uri()}/api/2.0/mlflow/traces?{qs}"
    data = http_get_json(url)
    return data.get("traces", []) or []


def get_trace(trace_id: str) -> dict[str, Any]:
    qs = urllib.parse.urlencode({"trace_id": trace_id})
    url = f"{tracking_uri()}/api/3.0/mlflow/traces/get?{qs}"
    try:
        raw = _http_get(url)
    except HttpError as e:
        if e.code == 404:
            # Older MLflow (e.g. prdeus) has no api/3.0 trace endpoint — fall back.
            return get_trace_via_artifact(trace_id)
        raise SystemExit(f"HTTP {e.code} on {e.url}\n{e.body}")
    data = json.loads(raw.decode("utf-8"))
    trace = data.get("trace") or data
    if not trace or "trace_info" not in trace and "info" not in trace:
        raise SystemExit(f"unexpected payload for {trace_id}: keys={list(data)[:10]}")
    return trace


def get_trace_via_artifact(trace_id: str) -> dict[str, Any]:
    """Pre-3.3.0 fallback: fetch spans from the ajax-api trace artifact (param is request_id).

    Returns the spans only (UI subset) wrapped in a trace shape; trace_info is empty —
    for `session` dumps the index is built from the search API, so it stays rich.
    """
    qs = urllib.parse.urlencode({"request_id": trace_id})
    url = f"{tracking_uri()}/ajax-api/2.0/mlflow/get-trace-artifact?{qs}"
    try:
        data = json.loads(_http_get(url).decode("utf-8"))
    except HttpError as e:
        raise SystemExit(f"HTTP {e.code} on {e.url}\n{e.body}")
    spans = data.get("spans") if isinstance(data, dict) else data
    if not isinstance(spans, list):
        spans = []
    return {"trace_info": {}, "trace_data": {"spans": spans}}


def metadata_dict(trace_info: dict[str, Any]) -> dict[str, str]:
    md = trace_info.get("trace_metadata") or trace_info.get("request_metadata") or []
    if isinstance(md, dict):
        return {str(k): str(v) for k, v in md.items()}
    out: dict[str, str] = {}
    for entry in md:
        if isinstance(entry, dict) and "key" in entry:
            out[str(entry["key"])] = str(entry.get("value", ""))
    return out


def tags_dict(trace_info: dict[str, Any]) -> dict[str, str]:
    tags = trace_info.get("tags") or []
    if isinstance(tags, dict):
        return {str(k): str(v) for k, v in tags.items()}
    out: dict[str, str] = {}
    for entry in tags:
        if isinstance(entry, dict) and "key" in entry:
            out[str(entry["key"])] = str(entry.get("value", ""))
    return out


def truncate(s: str, max_len: int = TREE_FIELD_MAX) -> str:
    if len(s) <= max_len:
        return s
    return s[:max_len] + f"...[truncated {len(s) - max_len} chars]"


def unwrap_otlp_value(v: Any) -> Any:
    """OTLP wraps scalars as {string_value: …} / {int_value: …} / {kvlist_value: {values: [...]}} / etc."""
    if not isinstance(v, dict):
        return v
    for prim in ("string_value", "int_value", "double_value", "bool_value"):
        if prim in v:
            raw = v[prim]
            if prim == "string_value" and isinstance(raw, str) and raw and raw[0] in '{[':
                try:
                    return json.loads(raw)
                except json.JSONDecodeError:
                    return raw
            return raw
    if "kvlist_value" in v:
        kv = v["kvlist_value"]
        values = kv.get("values") if isinstance(kv, dict) else None
        if isinstance(values, list):
            return {str(e.get("key")): unwrap_otlp_value(e.get("value")) for e in values if isinstance(e, dict)}
        return kv
    if "array_value" in v:
        av = v["array_value"]
        values = av.get("values") if isinstance(av, dict) else None
        if isinstance(values, list):
            return [unwrap_otlp_value(x) for x in values]
        return av
    return v


def parse_attrs(span: dict[str, Any]) -> dict[str, Any]:
    raw = span.get("attributes")
    if raw is None:
        return {}
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"_raw": raw}
    if isinstance(raw, list):
        out: dict[str, Any] = {}
        for entry in raw:
            if isinstance(entry, dict) and "key" in entry:
                out[str(entry["key"])] = unwrap_otlp_value(entry.get("value"))
        return out
    if isinstance(raw, dict):
        parsed: dict[str, Any] = {}
        for k, v in raw.items():
            if isinstance(v, str) and v and v[0] in '{[':
                try:
                    parsed[k] = json.loads(v)
                    continue
                except json.JSONDecodeError:
                    pass
            parsed[k] = v
        return parsed
    return {}


def span_id_of(span: dict[str, Any]) -> str:
    """Span id, tolerating both the OTLP shape (top-level) and the artifact shape (context.span_id)."""
    sid = span.get("span_id") or span.get("spanId")
    if sid:
        return str(sid)
    ctx = span.get("context")
    if isinstance(ctx, dict):
        return str(ctx.get("span_id") or ctx.get("spanId") or "")
    return ""


def span_duration_ms(span: dict[str, Any]) -> int:
    start = span.get("start_time_unix_nano") or span.get("start_time_ns") or span.get("start_time")
    end = span.get("end_time_unix_nano") or span.get("end_time_ns") or span.get("end_time")
    if start is None or end is None:
        return 0
    try:
        return max(0, (int(end) - int(start)) // 1_000_000)
    except (TypeError, ValueError):
        return 0


def span_status(span: dict[str, Any]) -> str:
    status = span.get("status")
    raw = ""
    if isinstance(status, dict):
        raw = str(status.get("code") or status.get("status_code") or "UNKNOWN")
    elif isinstance(status, str):
        raw = status
    else:
        raw = "UNKNOWN"
    if raw.startswith("STATUS_CODE_"):
        raw = raw[len("STATUS_CODE_"):]
    return raw


def span_type(attrs: dict[str, Any], span: dict[str, Any]) -> str:
    t = attrs.get("mlflow.spanType")
    if isinstance(t, str):
        return t.strip('"')
    return str(span.get("span_type") or span.get("kind") or "UNKNOWN")


def render_chat_model(attrs: dict[str, Any]) -> str:
    usage = attrs.get("mlflow.chat.tokenUsage") or attrs.get("llm.token_count") or {}
    if isinstance(usage, dict):
        in_t = usage.get("input_tokens") or usage.get("prompt_tokens") or usage.get("input")
        out_t = usage.get("output_tokens") or usage.get("completion_tokens") or usage.get("output")
        if in_t is not None or out_t is not None:
            model = attrs.get("model_name") or attrs.get("mlflow.llm.model") or ""
            model_suffix = f" {model}" if model else ""
            return f"  in_toks={in_t or '?'} out_toks={out_t or '?'}{model_suffix}"
    return ""


def render_tool(attrs: dict[str, Any]) -> str:
    inputs = attrs.get("mlflow.spanInputs") or attrs.get("inputs") or {}
    outputs = attrs.get("mlflow.spanOutputs") or attrs.get("outputs")
    arg_keys = ""
    if isinstance(inputs, dict) and inputs:
        arg_keys = ",".join(sorted(inputs.keys())[:6])
    elif isinstance(inputs, list):
        arg_keys = f"[{len(inputs)} args]"
    out_preview = ""
    if outputs is not None:
        s = outputs if isinstance(outputs, str) else json.dumps(outputs, default=str)
        s = s.replace("\n", " ").replace("\r", " ")
        out_preview = truncate(s, TOOL_OUTPUT_PREVIEW)
    pieces = []
    if arg_keys:
        pieces.append(f"args={{{arg_keys}}}")
    if out_preview:
        pieces.append(f"→ {out_preview}")
    return "  " + " ".join(pieces) if pieces else ""


def render_error(span: dict[str, Any], attrs: dict[str, Any]) -> str:
    events = span.get("events") or []
    for ev in events if isinstance(events, list) else []:
        if not isinstance(ev, dict):
            continue
        name = ev.get("name", "")
        if "exception" in str(name).lower():
            ev_attrs = ev.get("attributes") or {}
            if isinstance(ev_attrs, list):
                ev_attrs = {a.get("key"): a.get("value") for a in ev_attrs if isinstance(a, dict)}
            exc_type = ev_attrs.get("exception.type") or "Exception"
            msg = str(ev_attrs.get("exception.message") or "").splitlines()[0:1]
            return f"  {exc_type}: {msg[0] if msg else ''}"
    status = span.get("status")
    if isinstance(status, dict):
        desc = status.get("description") or status.get("message")
        if desc:
            return f"  {truncate(str(desc).splitlines()[0], 200)}"
    return ""


def render_span_suffix(span: dict[str, Any], attrs: dict[str, Any], stype: str, status: str) -> str:
    if status == "ERROR":
        err = render_error(span, attrs)
        if err:
            return err
    if stype == "CHAT_MODEL" or stype == "LLM":
        return render_chat_model(attrs)
    if stype == "TOOL":
        return render_tool(attrs)
    return ""


def build_tree(spans: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    nodes: list[dict[str, Any]] = []
    by_id: dict[str, dict[str, Any]] = {}
    for raw in spans:
        attrs = parse_attrs(raw)
        node = {
            "span_id": span_id_of(raw),
            "parent_id": raw.get("parent_id") or raw.get("parentSpanId") or raw.get("parent_span_id") or "",
            "name": raw.get("name", ""),
            "type": span_type(attrs, raw),
            "status": span_status(raw),
            "duration_ms": span_duration_ms(raw),
            "raw": raw,
            "attrs": attrs,
        }
        nodes.append(node)
        if node["span_id"]:
            by_id[node["span_id"]] = node

    children: dict[str, list[dict[str, Any]]] = {}
    roots: list[dict[str, Any]] = []
    for n in nodes:
        pid = n["parent_id"]
        if pid and pid in by_id:
            children.setdefault(pid, []).append(n)
        else:
            roots.append(n)
    def start_key(n: dict[str, Any]) -> int:
        raw = n["raw"]
        return int(raw.get("start_time_unix_nano") or raw.get("start_time_ns") or raw.get("start_time") or 0)

    for siblings in children.values():
        siblings.sort(key=start_key)
    roots.sort(key=start_key)

    lines: list[str] = []
    index: list[dict[str, Any]] = []

    def walk(node: dict[str, Any], depth: int) -> None:
        idx = len(index)
        index.append({
            "idx": idx,
            "span_id": node["span_id"],
            "parent_id": node["parent_id"],
            "name": node["name"],
            "type": node["type"],
            "status": node["status"],
            "duration_ms": node["duration_ms"],
        })
        suffix = render_span_suffix(node["raw"], node["attrs"], node["type"], node["status"])
        lines.append(
            f"{'  ' * depth}[{idx:02d}] {node['name']}  {node['type']}  {node['status']}  {node['duration_ms']}ms{suffix}"
        )
        for c in children.get(node["span_id"], []):
            walk(c, depth + 1)

    for r in roots:
        walk(r, 0)

    return "\n".join(lines) + "\n", index


def trace_info_of(trace: dict[str, Any]) -> dict[str, Any]:
    return trace.get("trace_info") or trace.get("info") or {}


def trace_spans_of(trace: dict[str, Any]) -> list[dict[str, Any]]:
    data = trace.get("trace_data") or trace.get("data") or {}
    spans = data.get("spans") if isinstance(data, dict) else None
    if spans is None:
        spans = trace.get("spans")
    return spans or []


def trace_id_of(info: dict[str, Any]) -> str:
    return str(info.get("trace_id") or info.get("request_id") or "")


def trace_started_at(info: dict[str, Any]) -> str:
    ts = info.get("request_time") or info.get("timestamp_ms") or info.get("start_time_ms")
    if ts is None:
        return ""
    if isinstance(ts, str):
        return ts.replace("T", " ").rstrip("Z").split(".")[0]
    try:
        import datetime as dt
        return dt.datetime.fromtimestamp(int(ts) / 1000, tz=dt.UTC).strftime("%Y-%m-%d %H:%M:%S")
    except (TypeError, ValueError):
        return str(ts)


def trace_duration_s(info: dict[str, Any]) -> float:
    raw = info.get("execution_duration") or info.get("execution_duration_ms") or info.get("execution_time_ms")
    if raw is None:
        return 0.0
    if isinstance(raw, str):
        m = re.match(r"^\s*([0-9.]+)\s*([a-z]+)?\s*$", raw)
        if m:
            val = float(m.group(1))
            unit = (m.group(2) or "s").lower()
            return round(val if unit == "s" else val / 1000.0 if unit == "ms" else val, 1)
        try:
            return round(int(raw) / 1000, 1)
        except (TypeError, ValueError):
            return 0.0
    try:
        return round(int(raw) / 1000, 1)
    except (TypeError, ValueError):
        return 0.0


def trace_status(info: dict[str, Any]) -> str:
    return str(info.get("state") or info.get("status") or "")


def read_meta_field(md: dict[str, str], key: str) -> str:
    val = md.get(key, "")
    return val.strip('"')


def parse_json_field(md: dict[str, str], key: str) -> dict[str, Any]:
    raw = md.get(key, "")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {}


def trace_summary_row(trace: dict[str, Any]) -> dict[str, Any]:
    info = trace_info_of(trace)
    md = metadata_dict(info)
    tags = tags_dict(info)
    size_stats = parse_json_field(md, "mlflow.trace.sizeStats")
    token_usage = parse_json_field(md, "mlflow.trace.tokenUsage")
    cost = parse_json_field(md, "mlflow.trace.cost")
    request_preview = info.get("request_preview") or read_meta_field(md, "mlflow.traceInputs")
    if request_preview:
        try:
            obj = json.loads(request_preview)
            if isinstance(obj, dict):
                request_preview = str(obj.get("input") or obj.get("query") or obj.get("messages") or obj)
        except (json.JSONDecodeError, TypeError):
            pass
    total_cost = cost.get("total_cost") if isinstance(cost, dict) else None
    return {
        "trace_id": trace_id_of(info),
        "started_at": trace_started_at(info),
        "agent": read_meta_field(md, "agent_type") or tags.get("mlflow.traceName", ""),
        "duration_s": trace_duration_s(info),
        "status": trace_status(info),
        "num_spans": size_stats.get("num_spans") if isinstance(size_stats, dict) else None,
        "input_tokens": token_usage.get("input_tokens") if isinstance(token_usage, dict) else None,
        "output_tokens": token_usage.get("output_tokens") if isinstance(token_usage, dict) else None,
        "cost_usd": f"{total_cost:.4f}" if isinstance(total_cost, (int, float)) else "",
        "prompt_preview": truncate(str(request_preview).replace("\n", " "), 120),
        "user": read_meta_field(md, "mlflow.user"),
        "branch": read_meta_field(md, "mlflow.source.git.branch"),
        "session": read_meta_field(md, "mlflow.trace.session"),
    }


def write_index_md(rows: list[dict[str, Any]], out: Path) -> Path:
    headers = ["trace_id", "started_at", "agent", "duration_s", "status", "num_spans",
               "input_tokens", "output_tokens", "cost_usd", "prompt_preview"]
    sep = "|".join("---" for _ in headers)
    lines = ["| " + " | ".join(headers) + " |", "| " + sep + " |"]
    for r in rows:
        lines.append("| " + " | ".join(str(r.get(h, "") or "") for h in headers) + " |")
    path = out / "index.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def trace_meta_json(trace: dict[str, Any]) -> dict[str, Any]:
    info = trace_info_of(trace)
    md = metadata_dict(info)
    return {
        "trace_id": trace_id_of(info),
        "state": trace_status(info),
        "started_at": trace_started_at(info),
        "duration_s": trace_duration_s(info),
        "agent_type": read_meta_field(md, "agent_type"),
        "session": read_meta_field(md, "mlflow.trace.session"),
        "user": read_meta_field(md, "mlflow.user"),
        "branch": read_meta_field(md, "mlflow.source.git.branch"),
        "environment": read_meta_field(md, "environment"),
        "company_identifier": read_meta_field(md, "company_identifier"),
        "compaction_triggered": read_meta_field(md, "compaction_triggered"),
        "token_usage": parse_json_field(md, "mlflow.trace.tokenUsage"),
        "cost": parse_json_field(md, "mlflow.trace.cost"),
        "size_bytes": read_meta_field(md, "mlflow.trace.sizeBytes"),
        "size_stats": parse_json_field(md, "mlflow.trace.sizeStats"),
        "tags": tags_dict(info),
    }


def dump_trace(trace_id: str, out: Path, no_cache: bool, written: list[Path]) -> tuple[Path, Path, Path, list[dict[str, Any]]]:
    out.mkdir(parents=True, exist_ok=True)
    tree_path = out / f"{trace_id}.tree.txt"
    meta_path = out / f"{trace_id}.meta.json"
    spans_path = out / f"{trace_id}.spans.json"

    if not no_cache and tree_path.exists() and meta_path.exists() and spans_path.exists():
        spans_index = json.loads(spans_path.read_text(encoding="utf-8"))
        for p in (tree_path, meta_path, spans_path):
            written.append(p)
        return tree_path, meta_path, spans_path, spans_index

    trace = get_trace(trace_id)
    spans = trace_spans_of(trace)
    tree, index = build_tree(spans)
    tree_path.write_text(tree, encoding="utf-8")
    meta_path.write_text(json.dumps(trace_meta_json(trace), indent=2), encoding="utf-8")
    spans_path.write_text(json.dumps(index, indent=2), encoding="utf-8")
    for p in (tree_path, meta_path, spans_path):
        written.append(p)
    return tree_path, meta_path, spans_path, index


def coerce_message_list(value: Any) -> list[dict[str, Any]] | None:
    """Normalize a spanOutputs value into a pydantic-ai message list, or None.

    Tolerates: a JSON-encoded string; the double-wrap {"output": "<json string>"};
    {"messages": [...]}; or a bare list. Returns the list only when it looks like a
    message list (non-empty, items are dicts with a `parts` key).
    """
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except (json.JSONDecodeError, ValueError):
            return None
    if isinstance(value, dict):
        if "output" in value:
            return coerce_message_list(value["output"])
        if "messages" in value:
            return coerce_message_list(value["messages"])
        return None
    if isinstance(value, list) and value and all(
        isinstance(m, dict) and "parts" in m for m in value
    ):
        return value
    return None


def extract_messages(spans: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Pick the longest message list found across spans' spanOutputs (the root/Agent.run
    span carries the full history); empty list if none."""
    best: list[dict[str, Any]] = []
    for raw in spans:
        attrs = parse_attrs(raw)
        msgs = coerce_message_list(attrs.get("mlflow.spanOutputs"))
        if msgs and len(msgs) > len(best):
            best = msgs
    return best


def _render_part(part: dict[str, Any]) -> str | None:
    kind = str(part.get("part_kind") or part.get("kind") or "")
    name = part.get("tool_name") or ""

    def content_str(key: str = "content") -> str:
        c = part.get(key)
        if isinstance(c, (dict, list)):
            c = json.dumps(c, default=str)
        return str(c if c is not None else "")

    if kind == "system-prompt":
        return f"[system] {truncate(content_str(), SYSTEM_PROMPT_MAX)}"
    if kind == "user-prompt":
        return f"[user] {truncate(content_str(), MESSAGE_CONTENT_MAX)}"
    if kind == "text":
        return f"[assistant] {truncate(content_str(), MESSAGE_CONTENT_MAX)}"
    if kind == "tool-call":
        args = part.get("args")
        args_str = args if isinstance(args, str) else json.dumps(args, default=str)
        return f"[tool-call] {name}({truncate(str(args_str), MESSAGE_CONTENT_MAX)})"
    if kind == "tool-return":
        return f"[tool-return] {name} → {truncate(content_str(), MESSAGE_CONTENT_MAX)}"
    if kind == "retry-prompt":
        body = content_str()
        prefix = f"[retry] {name}: " if name else "[retry] "
        return prefix + truncate(body, MESSAGE_CONTENT_MAX)
    if kind:
        return f"[{kind}] {truncate(content_str(), MESSAGE_CONTENT_MAX)}"
    return None


def render_transcript(msgs: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for msg in msgs:
        for part in msg.get("parts", []) if isinstance(msg, dict) else []:
            if isinstance(part, dict):
                rendered = _render_part(part)
                if rendered:
                    lines.append(rendered)
    return "\n".join(lines) + ("\n" if lines else "")


def cmd_messages(args: argparse.Namespace) -> int:
    os.environ["MLFLOW_TRACKING_URI"] = effective_uri(args)
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.trace_id
    out.mkdir(parents=True, exist_ok=True)
    msg_path = out / f"{args.trace_id}.messages.txt"

    if not args.no_cache and msg_path.exists():
        print(msg_path.resolve())
        return 0

    trace = get_trace(args.trace_id)
    msgs = extract_messages(trace_spans_of(trace))
    if not msgs:
        print(f"no message history found in spanOutputs for {args.trace_id}", file=sys.stderr)
        return 4
    msg_path.write_text(render_transcript(msgs), encoding="utf-8")
    print(msg_path.resolve())
    return 0


def session_rows(traces: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for t in traces:
        info = t.get("trace_info") or t.get("info") or t
        rows.append(trace_summary_row({"trace_info": info}))
    rows.sort(key=lambda r: r.get("started_at") or "")
    return rows


def search_session_with_sweep(args: argparse.Namespace) -> list[dict[str, Any]] | None:
    """Find a session's traces, auto-sweeping candidate envs. Sets MLFLOW_TRACKING_URI to
    the env that matched. Returns rows, or None (after printing guidance) if no env had it."""
    session_uuid = args.session_uuid
    requested = (
        ENV_ALIASES.get(args.env.strip().lower(), args.env.strip().lower())
        if args.env else None
    )

    # A pinned --experiment targets one specific env: search it directly, no sweep.
    if args.experiment:
        os.environ["MLFLOW_TRACKING_URI"] = effective_uri(args)
        traces = search_session_traces(args.experiment, session_uuid)
        if traces:
            return session_rows(traces)
        print(f"no traces matched session {session_uuid} in {tracking_uri()}", file=sys.stderr)
        return None

    # An explicit env with no known experiment id and no --experiment: keep the actionable error.
    if requested is not None and resolve_env(requested)[1] is None:
        raise SystemExit(
            f"experiment id for env '{args.env}' is unknown; pass --experiment <id> "
            f"(it's the experiment named 'agent-server')"
        )

    tried: list[str] = []
    for env in session_sweep_order(args.env):
        uri, exp = resolve_env(env)
        if exp is None:
            continue  # can't search without an experiment id
        os.environ["MLFLOW_TRACKING_URI"] = uri
        tried.append(env)
        try:
            traces = search_session_traces(exp, session_uuid)
        except SystemExit as e:
            print(f"  {env}: {e}", file=sys.stderr)
            continue
        if traces:
            if env != requested:
                print(f"matched env: {env} (experiment {exp})", file=sys.stderr)
            return session_rows(traces)

    scope = "any swept env" if requested is None else f"{requested} or fallback envs"
    print(
        f"no traces matched session {session_uuid} in {scope} ({', '.join(tried)}). "
        f"For staging/eus, pass --env <name> --experiment <id>; if every env failed to "
        f"connect, check the corporate VPN.",
        file=sys.stderr,
    )
    return None


def cmd_session(args: argparse.Namespace) -> int:
    if looks_like_trace_id(args.session_uuid):
        raise SystemExit(
            f"'{args.session_uuid}' looks like a trace id; "
            f"use: mlflow_dump.py trace {args.session_uuid}"
        )

    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.session_uuid
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    summary_path = out / "summary.json"
    index_path = out / "index.md"

    if not args.no_cache and summary_path.exists() and index_path.exists():
        rows = json.loads(summary_path.read_text(encoding="utf-8"))
        # Cached per-trace files won't hit the network; point at the requested env anyway.
        os.environ["MLFLOW_TRACKING_URI"] = effective_uri(args)
        written.extend([index_path, summary_path])
    else:
        rows = search_session_with_sweep(args)
        if rows is None:
            return 2
        summary_path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
        write_index_md(rows, out)
        written.extend([index_path, summary_path])

    for row in rows:
        tid = row.get("trace_id")
        if not tid:
            continue
        try:
            dump_trace(tid, out, args.no_cache, written)
        except SystemExit as e:
            print(f"failed to dump trace {tid}: {e}", file=sys.stderr)

    for p in written:
        print(p.resolve())
    return 0


def cmd_trace(args: argparse.Namespace) -> int:
    os.environ["MLFLOW_TRACKING_URI"] = effective_uri(args)
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.trace_id
    written: list[Path] = []
    dump_trace(args.trace_id, out, args.no_cache, written)
    for p in written:
        print(p.resolve())
    return 0


def cmd_span(args: argparse.Namespace) -> int:
    os.environ["MLFLOW_TRACKING_URI"] = effective_uri(args)
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.trace_id
    out.mkdir(parents=True, exist_ok=True)
    safe_id = re.sub(r"[^A-Za-z0-9_.-]", "_", args.span_id)
    span_path = out / f"{safe_id}.json"

    if not args.no_cache and span_path.exists():
        print(span_path.resolve())
        return 0

    trace = get_trace(args.trace_id)
    spans = trace_spans_of(trace)
    match = None
    for s in spans:
        if span_id_of(s) == args.span_id:
            match = s
            break
    if match is None:
        print(f"span {args.span_id} not found in {args.trace_id}", file=sys.stderr)
        return 3
    span_path.write_text(json.dumps(match, indent=2, default=str), encoding="utf-8")
    print(span_path.resolve())
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    env_help = "env alias/name (dev|stg|prd or devweu|prdweu|...); sets tracking URI"

    sp = sub.add_parser("session", help="dump every trace of a chat session")
    sp.add_argument("session_uuid")
    sp.add_argument("--env", help=env_help + " + experiment id")
    sp.add_argument("--experiment", default=None)
    sp.add_argument("--out")
    sp.add_argument("--no-cache", action="store_true")
    sp.set_defaults(func=cmd_session)

    tp = sub.add_parser("trace", help="dump one trace (tree + meta + span index)")
    tp.add_argument("trace_id")
    tp.add_argument("--env", help=env_help)
    tp.add_argument("--out")
    tp.add_argument("--no-cache", action="store_true")
    tp.set_defaults(func=cmd_trace)

    spn = sub.add_parser("span", help="dump one span's full payload")
    spn.add_argument("trace_id")
    spn.add_argument("span_id")
    spn.add_argument("--env", help=env_help)
    spn.add_argument("--out")
    spn.add_argument("--no-cache", action="store_true")
    spn.set_defaults(func=cmd_span)

    mp = sub.add_parser("messages", help="extract the pydantic-ai transcript from spanOutputs")
    mp.add_argument("trace_id")
    mp.add_argument("--env", help=env_help)
    mp.add_argument("--out")
    mp.add_argument("--no-cache", action="store_true")
    mp.set_defaults(func=cmd_messages)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
