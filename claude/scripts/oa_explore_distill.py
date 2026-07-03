#!/usr/bin/env python3
"""Distill Optimizely Analytics `analyze_explore` results into a compact query spec.

`oa_analyze_explore` returns ~130-150k chars per explore: the query *definition*
(`explore.detail`, a Java-serialized dump padded with noise keys) bundled with the
query *result data* (`data.upserts`). This strips the noise and projects only what
describes the query, so a whole dashboard's tiles fit in a few thousand tokens.

Two modes:
  --full (default)  noise-stripped query-spec JSON per file (keeps broken bloqs)
  --summary         one compact block per explore (type/viz, measures, breakdown,
                    filter, range·grain, sampling) + flagged smells

Accepts many files in one call (one `analyze_explore` result each) so a dashboard
distills in a single process. Each input is the JSON the MCP tool returned, whether
it landed inline or was overflowed to a `tool-results/*.txt` file.

Stdlib only. Pairs with the /ds:analyze-oa-dashboard command, which fires the
`analyze_explore` calls and joins these blocks into a markdown table.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any

NOISE_KEYS = {
    "init_shim", "to_string", "hash_code", "dense_id", "lazy_init_bitmap",
    "id_initialize", "json_tags_from_db", "in_chrono_units", "in_millis",
    "pretty_print", "sqn", "orgid", "appid", "catalogued", "deleted",
    "state_description", "detail_initialize",
}


def clean(o):
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            if k in NOISE_KEYS or k.endswith("_initialize") or k.endswith("_shim"):
                continue
            cv = clean(v)
            if cv in (None, {}, [], ""):
                continue
            out[k] = cv
        return out
    if isinstance(o, list):
        return [clean(x) for x in o if clean(x) not in (None, {}, [], "")]
    return o


# Collapse verbose TimeInstant/TimeInterval objects to their pretty_print.
def collapse_time(o):
    if isinstance(o, dict):
        if "pretty_print" in o and "unit" in o:
            neg = o.get("negate_offset")
            return ("-" if neg else "") + str(o.get("pretty_print"))
        if "start_time" in o and "end_time" in o:
            return {"start": collapse_time(o["start_time"]),
                    "end": collapse_time(o["end_time"]),
                    "unbounded": o.get("is_unbounded")}
        if o.get("is_now"):
            return "now"
        if "offset" in o and "type" in o:
            return collapse_time(o["offset"])
        return {k: collapse_time(v) for k, v in o.items()}
    if isinstance(o, list):
        return [collapse_time(x) for x in o]
    return o


def find_explore(payload: Any) -> dict[str, Any]:
    """Locate the `explore` object in an analyze_explore result.

    Handles the plain `{explore, data}` shape and MCP envelopes that nest it. An
    explore is a dict carrying a `detail` (its query spec). Raises ValueError if none.
    """
    if isinstance(payload, dict):
        exp = payload.get("explore")
        if isinstance(exp, dict):
            return exp

    def walk(o: Any) -> dict[str, Any] | None:
        if isinstance(o, dict):
            exp = o.get("explore")
            if isinstance(exp, dict) and ("detail" in exp or "id" in exp):
                return exp
            if "detail" in o and "id" in o and "explore" not in o:
                return o
            for v in o.values():
                found = walk(v)
                if found is not None:
                    return found
        elif isinstance(o, list):
            for v in o:
                found = walk(v)
                if found is not None:
                    return found
        return None

    found = walk(payload)
    if found is None:
        raise ValueError("no 'explore' object found in payload")
    return found


def distill_explore(exp: dict[str, Any]) -> dict[str, Any]:
    det = exp.get("detail", {}) or {}
    templates: dict[str, Any] = {}
    for k, v in det.items():
        if k in ("sub_type", "display_name", "connection", "to_string", "hash_code"):
            continue
        cv = collapse_time(clean(v))
        if cv not in (None, {}, [], ""):
            templates[k] = cv
    # `explore_template` mirrors the type-specific template; drop when redundant.
    if "explore_template" in templates and len(templates) > 1:
        et = templates["explore_template"]
        if any(k != "explore_template" and v == et for k, v in templates.items()):
            del templates["explore_template"]
    return {
        "explore_id": exp.get("id"),
        "name": exp.get("name"),
        "description": exp.get("description"),
        "sub_type": det.get("sub_type"),
        "display_name": det.get("display_name"),
        "templates": templates,
    }


def distill(path: str) -> dict[str, Any]:
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)
    return distill_explore(find_explore(payload))


# --- --summary projection --------------------------------------------------

SUBTYPE_TEMPLATE = {
    "FUNNEL_BLOQ": "funnel_bloq_template",
    "EVENT_SEGMENT": "event_segment",
    "UNIVERSAL": "universal_template",
}
PERSONAL_COL_RE = re.compile(r'Users\."[^"]+"')


def _find_first(obj: Any, key: str) -> Any:
    """Depth-first search for the first value under `key`. Robust to nesting drift."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for v in obj.values():
            found = _find_first(v, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for v in obj:
            found = _find_first(v, key)
            if found is not None:
                return found
    return None


def _active_template(sub_type: Any, templates: dict[str, Any]) -> tuple[dict[str, Any], str | None]:
    if not isinstance(templates, dict):
        return {}, None
    key = SUBTYPE_TEMPLATE.get(str(sub_type))
    if key and isinstance(templates.get(key), dict):
        return templates[key], key
    for k, v in templates.items():
        if isinstance(v, dict) and ("chart_config" in v or "bloqs" in v or "measures" in v):
            return v, k
    for k, v in templates.items():
        if isinstance(v, dict):
            return v, k
    return {}, None


def _iter_bloqs(tmpl: dict[str, Any]) -> list[dict[str, Any]]:
    b = tmpl.get("bloqs") if isinstance(tmpl, dict) else None
    if isinstance(b, dict):
        inner = b.get("bloqs")
        if isinstance(inner, list):
            return [x for x in inner if isinstance(x, dict)]
    if isinstance(b, list):
        return [x for x in b if isinstance(x, dict)]
    return []


def _bloq_id(b: dict[str, Any]) -> Any:
    return b.get("id") if b.get("id") is not None else b.get("bloq_id")


def _render_bloq(b: dict[str, Any]) -> str:
    ns = b.get("netscript")
    if ns:
        return str(ns)
    name = b.get("display_name") or ""
    kind = b.get("type") or ""
    label = f"{name} ({kind})".strip()
    return label if label != "()" else ""


def _active_measure_ids(tmpl: dict[str, Any]) -> list[str]:
    ids: list[str] = []
    for measure in tmpl.get("measures") or []:
        if isinstance(measure, dict) and measure.get("bloq_id") is not None:
            ids.append(str(measure["bloq_id"]))
    measure_ids = tmpl.get("measure_ids")
    if isinstance(measure_ids, list):
        ids.extend(str(x) for x in measure_ids)
    return ids


def _render_bloq_measures(tmpl: dict[str, Any]) -> list[str]:
    bloqs = _iter_bloqs(tmpl)
    by_id = {str(_bloq_id(b)): b for b in bloqs if _bloq_id(b) is not None}
    active = [by_id[i] for i in _active_measure_ids(tmpl) if i in by_id]
    chosen = active or bloqs
    return [text for text in (_render_bloq(b) for b in chosen) if text]


def _render_funnel_measures(tmpl: dict[str, Any]) -> list[str]:
    seq = tmpl.get("sequence") if isinstance(tmpl, dict) else None
    stages = seq.get("stages") if isinstance(seq, dict) else None
    if not isinstance(stages, list):
        stages = _find_first(tmpl, "stages")
    stage_names: list[str] = []
    for stage in stages if isinstance(stages, list) else []:
        name = _find_first(stage, "name")
        if name:
            stage_names.append(str(name))
    seq_str = " → ".join(stage_names)
    out: list[str] = []
    for measure in tmpl.get("measures") or []:
        mtype = measure.get("type") if isinstance(measure, dict) else None
        if mtype and seq_str:
            out.append(f"{mtype} over [{seq_str}]")
        elif mtype:
            out.append(str(mtype))
    if not out and seq_str:
        out.append(f"funnel: {seq_str}")
    return out


def _render_measures(tmpl: dict[str, Any], sub_type: Any) -> list[str]:
    if not isinstance(tmpl, dict):
        return []
    if str(sub_type) == "FUNNEL_BLOQ":
        funnel = _render_funnel_measures(tmpl)
        if funnel:
            return funnel
    return _render_bloq_measures(tmpl)


def _render_breakdown(tmpl: dict[str, Any]) -> list[str]:
    attrs = tmpl.get("attributes") if isinstance(tmpl, dict) else None
    if not isinstance(attrs, list):
        attrs = _find_first(tmpl, "attributes")
    out: list[str] = []
    for attr in attrs if isinstance(attrs, list) else []:
        if isinstance(attr, dict):
            eid = attr.get("entity_id")
            if eid is not None:
                out.append(str(eid))
        elif attr is not None:
            out.append(str(attr))
    return out


def _walk_predicates(node: Any, out: list[str]) -> None:
    if isinstance(node, dict):
        pred = node.get("predicate")
        prop = pred.get("property") if isinstance(pred, dict) else None
        if isinstance(prop, dict):
            left = prop.get("left") or {}
            right = prop.get("right") or {}
            lid = left.get("entity_id") if isinstance(left, dict) else left
            op = prop.get("operator")
            lit = right.get("literal") if isinstance(right, dict) else right
            parts = [str(x) for x in (lid, op, lit) if x is not None]
            if parts:
                out.append(" ".join(parts))
        for v in node.values():
            _walk_predicates(v, out)
    elif isinstance(node, list):
        for v in node:
            _walk_predicates(v, out)


def _render_filter(tmpl: dict[str, Any]) -> str | None:
    filters = tmpl.get("global_filters") if isinstance(tmpl, dict) else None
    if not isinstance(filters, list) or not filters:
        filters = _find_first(tmpl, "global_filters")
    preds: list[str] = []
    _walk_predicates(filters, preds)
    return " AND ".join(preds) if preds else None


def _iter_bloq_errors(obj: Any) -> list[str]:
    found: list[str] = []

    def walk(o: Any) -> None:
        if isinstance(o, dict):
            errs = o.get("errors")
            if isinstance(errs, list) and errs:
                label = o.get("display_name") or o.get("id") or "?"
                msgs = [str(e.get("message") or e) if isinstance(e, dict) else str(e) for e in errs]
                found.append(f"{label}: {'; '.join(msgs)}")
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(obj)
    return found


def _short(v: Any) -> str | None:
    if v is None:
        return None
    if isinstance(v, str):
        return v
    if isinstance(v, (int, float, bool)):
        return str(v)
    return json.dumps(v, default=str, separators=(",", ":"))


def _iter_strings(o: Any):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for v in o.values():
            yield from _iter_strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from _iter_strings(v)


def _collect_warnings(templates: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    seen: set[str] = set()
    for s in _iter_strings(templates):
        for match in PERSONAL_COL_RE.findall(s):
            if match not in seen:
                seen.add(match)
                warnings.append(f"personal column dependency: {match}")
    for err in _iter_bloq_errors(templates):
        warnings.append(f"broken bloq: {err}")
    return warnings


def project_summary(distilled: dict[str, Any]) -> dict[str, Any]:
    templates = distilled.get("templates") or {}
    sub_type = distilled.get("sub_type")
    tmpl, _ = _active_template(sub_type, templates)

    chart = None
    if isinstance(tmpl, dict) and isinstance(tmpl.get("chart_config"), dict):
        chart = tmpl["chart_config"].get("subType")
    if not chart:
        cc = _find_first(templates, "chart_config")
        if isinstance(cc, dict):
            chart = cc.get("subType")

    sampling_spec = _find_first(templates, "sampling_spec")
    sampling = sampling_spec.get("mode") if isinstance(sampling_spec, dict) else None

    return {
        "explore_id": distilled.get("explore_id"),
        "sub_type": sub_type,
        "chart_type": chart,
        "title": distilled.get("display_name") or distilled.get("name") or "",
        "measures": _render_measures(tmpl, sub_type),
        "breakdown": _render_breakdown(tmpl),
        "filter": _render_filter(tmpl),
        "range": _short(_find_first(templates, "time_range_param_value")),
        "grain": _short(_find_first(templates, "time_grain_param_value")),
        "sampling": sampling,
        "warnings": _collect_warnings(templates),
    }


def render_summary(distilled: dict[str, Any]) -> str:
    s = project_summary(distilled)
    header = f'{s["explore_id"]}  [{s["sub_type"]} → {s["chart_type"] or "?"}]  "{s["title"]}"'
    lines = [
        header,
        f"  measure(s): {' / '.join(s['measures']) if s['measures'] else '—'}",
        f"  breakdown:  {', '.join(s['breakdown']) if s['breakdown'] else '—'}",
        f"  filter:     {s['filter'] or '—'}",
        f"  range·grain: {s['range'] or '?'} · {s['grain'] or '?'}   sampling: {s['sampling'] or '?'}",
    ]
    lines.extend(f"  ⚠ {w}" for w in s["warnings"])
    return "\n".join(lines)


def emit(paths: list[str], mode: str) -> int:
    successes = 0
    for path in paths:
        try:
            distilled = distill(path)
        except FileNotFoundError:
            print(f"# {path}: file not found", file=sys.stderr)
            continue
        except (json.JSONDecodeError, ValueError, KeyError, TypeError) as e:
            print(f"# {path}: could not parse ({e})", file=sys.stderr)
            continue
        if mode == "summary":
            print(render_summary(distilled))
        else:
            print(f"# {path}")
            print(json.dumps(distilled, indent=2, default=str))
        print()
        successes += 1
    return 0 if (successes or not paths) else 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--summary", action="store_true",
                      help="one compact block per explore (for the dashboard table)")
    mode.add_argument("--full", action="store_true",
                      help="noise-stripped query-spec JSON per explore (default)")
    p.add_argument("files", nargs="+", metavar="analyze_explore_result.json")
    return p


def _force_utf8_output() -> None:
    """The summary blocks carry → · ⚠; a cp1252 Windows console would crash on them."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            try:
                reconfigure(encoding="utf-8")
            except (ValueError, OSError):
                pass


def main(argv: list[str] | None = None) -> int:
    _force_utf8_output()
    args = build_parser().parse_args(argv)
    return emit(args.files, "summary" if args.summary else "full")


if __name__ == "__main__":
    sys.exit(main())
