#!/usr/bin/env python3
"""Dump compact projections of MLflow traces/sessions to disk.

The goal is to keep Claude's context window small: pull big trace payloads
once, render a skeleton tree + meta JSON to disk, and only emit full
per-span payloads on explicit request.

Three subcommands:
  session <uuid>           — list all traces of a chat session + tree per trace
  trace   <trace_id>       — full tree + meta + span index for one trace
  span    <trace_id> <id>  — single span's full payload (inputs/outputs/attrs)

Defaults:
  --out  ~/.cache/mlflow-dump/<session_or_trace_id>/
  MLFLOW_TRACKING_URI env var (default https://mlflow-devweu.devds.net)
  --experiment 9   (only for `session`)

Stdlib only — no mlflow, no requests. Re-runs are cached unless --no-cache.
Every file written or hit-from-cache is printed (absolute path, one per line)
to stdout so the caller can `Read` it directly.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_TRACKING_URI = "https://mlflow-devweu.devds.net"
DEFAULT_EXPERIMENT_ID = "9"
DEFAULT_CACHE_ROOT = Path.home() / ".cache" / "mlflow-dump"
TREE_FIELD_MAX = 1024
TOOL_OUTPUT_PREVIEW = 80
HTTP_TIMEOUT_SECONDS = 60


def tracking_uri() -> str:
    return os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI).rstrip("/")


def http_get_json(url: str) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"HTTP {e.code} on {url}\n{body}")
    except urllib.error.URLError as e:
        raise SystemExit(f"Connection failed for {url}: {e.reason}")


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
    data = http_get_json(url)
    trace = data.get("trace") or data
    if not trace or "trace_info" not in trace and "info" not in trace:
        raise SystemExit(f"unexpected payload for {trace_id}: keys={list(data)[:10]}")
    return trace


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
            "span_id": raw.get("span_id") or raw.get("spanId") or "",
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
    for siblings in children.values():
        siblings.sort(key=lambda n: n["raw"].get("start_time_unix_nano") or n["raw"].get("start_time_ns") or 0)
    roots.sort(key=lambda n: n["raw"].get("start_time_unix_nano") or n["raw"].get("start_time_ns") or 0)

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


def cmd_session(args: argparse.Namespace) -> int:
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.session_uuid
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    summary_path = out / "summary.json"
    index_path = out / "index.md"

    if not args.no_cache and summary_path.exists() and index_path.exists():
        rows = json.loads(summary_path.read_text(encoding="utf-8"))
        written.extend([index_path, summary_path])
    else:
        traces = search_session_traces(args.experiment, args.session_uuid)
        if not traces:
            print(f"no traces matched session {args.session_uuid}", file=sys.stderr)
            return 2
        rows: list[dict[str, Any]] = []
        for t in traces:
            info = t.get("trace_info") or t.get("info") or t
            rows.append(trace_summary_row({"trace_info": info}))
        rows.sort(key=lambda r: r.get("started_at") or "")
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
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.trace_id
    written: list[Path] = []
    dump_trace(args.trace_id, out, args.no_cache, written)
    for p in written:
        print(p.resolve())
    return 0


def cmd_span(args: argparse.Namespace) -> int:
    out = Path(args.out).expanduser() if args.out else DEFAULT_CACHE_ROOT / args.trace_id
    span_dir = out / args.trace_id
    span_dir.mkdir(parents=True, exist_ok=True)
    safe_id = re.sub(r"[^A-Za-z0-9_.-]", "_", args.span_id)
    span_path = span_dir / f"{safe_id}.json"

    if not args.no_cache and span_path.exists():
        print(span_path.resolve())
        return 0

    trace = get_trace(args.trace_id)
    spans = trace_spans_of(trace)
    match = None
    for s in spans:
        sid = s.get("span_id") or s.get("spanId")
        if sid == args.span_id:
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

    sp = sub.add_parser("session", help="dump every trace of a chat session")
    sp.add_argument("session_uuid")
    sp.add_argument("--experiment", default=DEFAULT_EXPERIMENT_ID)
    sp.add_argument("--out")
    sp.add_argument("--no-cache", action="store_true")
    sp.set_defaults(func=cmd_session)

    tp = sub.add_parser("trace", help="dump one trace (tree + meta + span index)")
    tp.add_argument("trace_id")
    tp.add_argument("--out")
    tp.add_argument("--no-cache", action="store_true")
    tp.set_defaults(func=cmd_trace)

    spn = sub.add_parser("span", help="dump one span's full payload")
    spn.add_argument("trace_id")
    spn.add_argument("span_id")
    spn.add_argument("--out")
    spn.add_argument("--no-cache", action="store_true")
    spn.set_defaults(func=cmd_span)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
