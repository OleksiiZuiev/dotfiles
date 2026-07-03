# Spec — OA dashboard analysis tooling (`/ds:analyze-oa-dashboard` + `oa_explore_distill.py`)

> Status: **implemented 2026-07-03** — `oa_explore_distill.py` (+ `test_oa_explore_distill.py`) and `commands/ds/analyze-oa-dashboard.md` are live. Kept as the reference for the investigation findings (§2), the field map (§4), and the reference dashboard's entity map (§6). Author: analysis session 2026-07-03.
> Goal: make "read an Optimizely Analytics dashboard's tiles + query definitions" fast and cheap.
> Two artifacts, mirroring the `mlflow_dump.py` + `/ds:analyze-mlflow` pattern: a distiller **script** and a **slash command** that wraps it.

## 1. Problem this solves (token diagnosis)

Reading one OA dashboard's 12 tiles the naive way cost **~350k tokens** in the reference session. Breakdown of what went wrong:

- `oa_analyze_explore` returns **~130–150k chars per explore** because it bundles the query *definition* (`explore.detail`) **and** the query *result data* (`data.upserts`). The `detail` is a Java-serialized object dump padded with noise keys (`init_shim`, `to_string`, `hash_code`, `*_initialize`, verbose `TimeInterval`/`TimeInstant` objects).
- I reached for **6 subagents to keep the payload out of context (~330k tokens)** — but that was redundant: **the harness already auto-diverts any over-limit tool output to a file** and returns only a ~200-token `saved to <path>` message. The giant payload never needed to touch context in the first place.

**The fix is no subagents.** Fire the calls in the main context, let each overflow to a file, distill all files in one pass. Target: **~15k tokens** for the same 12-tile dashboard.

## 2. Direct-REST-API investigation (findings — do not re-investigate)

Investigated 2026-07-03. Verdict: **do not build a direct-API script.**

- Backend is Optimizely **Opal tools**: `https://analytics.optimizely.com/opal-tools/<tool>` (e.g. `/opal-tools/analyze-explore`; the 500 error's `instance` field revealed this). `/opal-tools/discovery` publicly lists the full tool catalog (names, paths, params).
- The product is **Netspring** (Optimizely acquired it — "warehouse-native analytics"); hence the `explore`/`bloq`/`netscript`/`funnel` vocabulary. The public `docs.developers.optimizely.com` covers *Web/Feature Experimentation* (`api.optimizely.com`), a **different** product — those PAT/OAuth docs do **not** apply here.
- **Every Opal tool requires `OptiID` OAuth**: discovery shows `"auth_requirements":[{"provider":"OptiID","scope_bundle":"default","required":true}]` on every endpoint. This is an SSO OAuth token the MCP connector holds internally — **not** a static personal access token a user can paste into a script. (Contrast `mlflow_dump.py`, which works via corporate-VPN network access + a tracking URI, no per-user OAuth.)
- **No definition-only tool exists.** Both `analyze-explore` and `create-explore` always return `explore` (definition) **+** `data` (results) together. So a direct HTTP call returns the *same* oversized payload → **zero size win**.
- A genuinely lighter path would be an **undocumented internal Netspring UI backend endpoint** (browser session-cookie auth) that returns a definition without data. Not exposed via Opal, not documented; discovering it needs browser network inspection, and scripting fragile cookie auth against an internal endpoint isn't worth it.

**Conclusion:** the payload is identical direct-vs-MCP, and context cost is already handled by overflow-to-file. Keep using the MCP `oa_analyze_explore` tool; put all the leverage into the method + distiller below.

## 3. The method (encoded by the slash command)

All in main context, **no subagents**:

1. **Resolve app** — `oa_list_apps`. If the user passed a dashboard URL with `?app=<uuid>`, that uuid *is* the app; `oa_list_apps` maps it to a name. (Reference dashboard's app `2f31303e-…` = **DataSnipper**.)
2. **List tiles** — `oa_explores_for_dashboard(appid, dashboard_id)`. Cheap (~4k tokens). Yields, per explore tile: the **explore `id`** (NOT the `tile_id` — passing a `tile_id` to `analyze_explore` throws a 500), plus `filter_tiles` and `all_tiles` (tile names + types + layout). Keep this raw; it's small.
3. **Fetch every explore in parallel** — issue all N `oa_analyze_explore(appid, explore_id, dashboard_id)` calls **in a single message** (independent calls batch fine). Each overflows to a `tool-results/*.txt` file; collect the N paths from the error messages (~200 tokens each). **Never read a raw payload into context.**
4. **Distill in one pass** — `python ~/.claude/scripts/oa_explore_distill.py --summary <path1> <path2> … <pathN>` → prints the compact per-tile table directly.
5. **Present** — table of tiles (type/viz, measure, breakdown, filter, range·grain) + flagged smells.

Notes / gotchas to bake into the command:
- **`id` vs `tile_id`:** in `explores_for_dashboard`, the `explores[].id` is the explore; `tile_id` is the tile. Use `id` for `analyze_explore`. (Cost me two 500s the first time.)
- **Small-explore edge case:** if an `analyze_explore` result is *small enough to return inline* (rare — tiny explores), it lands in context (~40k tokens). Mitigation: if a call returns inline JSON instead of a `saved to <path>` error, `Write` it to a scratch file first, then distill. Don't analyze it in place.
- **Optional payload-shrink (marginal):** `analyze_explore` accepts a `time_range` override. Passing a degenerate window (e.g. `{start:"2000-01-01", end:"2000-01-02"}`) makes the query return ~no rows, shrinking `data.upserts`. Irrelevant for the MCP path (overflow-to-file makes size moot) but harmless. **Caveat: verify the override does not overwrite the reported default range** — read the explore's saved range from `param_configs[name=TIME_RANGE].default_values`, which reflects the stored config, not the query-time override.

## 4. Artifact 1 — `~/.claude/scripts/oa_explore_distill.py`

Promote the validated prototype (below) and add a CLI. Lives at `dotfiles/claude/scripts/oa_explore_distill.py` (symlinked to `~/.claude/scripts/`).

### CLI
```
oa_explore_distill.py [--summary | --full] <analyze_explore_result.json> [<more.json> …]
```
- `--full` (default): print the noise-stripped query spec JSON per file (what the prototype does today).
- `--summary`: print **one compact block per explore** — the table-row fields, ~1 line of measure text. This is what the slash command uses; keeps distillation output to ~4–6k tokens for a whole dashboard.
- Accept **many files** in one invocation (one `analyze_explore` result each) so step 4 is a single process call.
- Robust to the two known broken shapes: bloqs carrying `errors:[{message:…}]` (e.g. `Invalid Formula with null input`, `Missing input`) — include them in `--full`, and in `--summary` mark the explore as having a stray/broken bloq rather than crashing.

### `--summary` row format (target)
One block per explore:
```
<explore_id>  [<sub_type> → <chart subType>]  "<display_name or tile name>"
  measure(s): <netscript one-liner, or built-in measure type>   # e.g. sum(NUMBER_OF_FILES)/count_distinct(SESSION_ID)
  breakdown:  <attribute names or entity ids, or —>
  filter:     <event/property predicate, or —>                  # e.g. event = INTEGRATIONS_IMPORT_COMPLETED
  range·grain: <e.g. 30d · week>   sampling: <mode>
  ⚠ <any broken bloq / personal-column dependency>              # only if present
```
The command joins these into a markdown table for the user.

### Validated core (lift verbatim — already proven on the reference dashboard)
The noise-stripping + time-collapsing core below was validated against all 12 reference explores. Keep `NOISE_KEYS`, `clean()`, `collapse_time()`, and the `explore_template` de-dup as-is; wrap them in the CLI above and add the `--summary` projection.

```python
import sys, json

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

def distill(path):
    d = json.load(open(path, encoding="utf-8"))
    exp = d["explore"]
    det = exp.get("detail", {})
    templates = {}
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
```

### Where the fields live (map for the `--summary` projector)
- **sub_type**: `explore.detail.sub_type` → `FUNNEL_BLOQ` / `EVENT_SEGMENT` / `UNIVERSAL`. The active template is `funnel_bloq_template` / `event_segment` / `universal_template` respectively.
- **chart type**: `templates.<t>.chart_config.subType` (HEADLINE / BAR / LINE / TABLE).
- **measure(s)**: `templates.<t>.bloqs.bloqs[]` — each has `display_name`, `type` (AGGREGATE / FORMULA / PROPERTY), and a human-readable `netscript`. Active ones are indexed by `measures[].bloq_id` / `measure_ids`. For funnels, `measures[].type` (`TOTAL_CONVERTED_TO_STAGE` / `CONVERSION_RATE`) + `sequence.stages[].event…name`.
- **breakdown**: `templates.<t>.attributes[].entity_id` (resolve via §6 map).
- **filter**: `templates.<t>.global_filters[]` → walk `junction.operands[].predicate.property` → `{left.entity_id operator right.literal}`.
- **range·grain**: `time_range_param_value` + `time_grain_param_value` (already collapsed to `30d` / `week` etc).
- **sampling**: `templates.<t>.sampling_spec.mode` (all reference tiles = `DISABLED`).

## 5. Artifact 2 — `/ds:analyze-oa-dashboard` slash command

Lives at `dotfiles/claude/commands/ds/analyze-oa-dashboard.md`. Mirror the `analyze-mlflow.md` structure (frontmatter + numbered steps + gotchas).

### Frontmatter
```yaml
---
description: Read an Optimizely Analytics dashboard's tiles + query definitions cheaply. Usage: /ds:analyze-oa-dashboard <dashboard-url|dashboard_id> [tile filter]
allowed-tools: Bash, Read, Write, mcp__optimizely-analytics__oa_list_apps, mcp__optimizely-analytics__oa_explores_for_dashboard, mcp__optimizely-analytics__oa_analyze_explore, mcp__optimizely-analytics__oa_confirm_app, mcp__optimizely-analytics__oa_find_entities, mcp__optimizely-analytics__oa_find_column_values
argument-hint: "<dashboard-url|dashboard_id> [optional: only tiles matching …]"
---
```
(The `oa_*` MCP tools are deferred — the command should `ToolSearch select:…` them first, as this session did, or rely on allowed-tools surfacing them.)

### Steps (prose in the command)
1. **Parse args** — extract `dashboard_id` (`<number>_<uuid>`) and `app` uuid from a pasted URL (`/dashboard/<dashboard_id>/?app=<app_uuid>`), or take a bare `dashboard_id`. Remaining tokens = optional tile filter.
2. **Resolve app** — `oa_list_apps`; match the URL's `app` uuid (or ask if ambiguous). Do not print the raw uuid to the user.
3. **List tiles** — `oa_explores_for_dashboard`. Capture `explores[].id` (+ tile names from `all_tiles`), `filter_tiles`. **State the `id`-vs-`tile_id` rule.**
4. **Parallel fetch** — one message, all `oa_analyze_explore(appid, id, dashboard_id)` calls. **Hard rule: never Read a raw payload; collect the `saved to <path>` file paths.** Handle the inline-small edge case by writing to scratch first.
5. **Distill once** — `python ~/.claude/scripts/oa_explore_distill.py --summary <all paths>`.
6. **Present** — markdown table (tile · type/viz · measure · breakdown · filter · range·grain) + a "smells" section.

### Hard rules / heuristics to bake in (each bit us)
- **No subagents for this.** Overflow-to-file already isolates the payload; a subagent just adds its own system-prompt + schema-load cost. (This was ~330k of the ~350k wasted.)
- **Use `id`, not `tile_id`,** for `analyze_explore`.
- **Flag, don't hide, smells** the distiller surfaces:
  - Measures built on a **personal derived column** (`Users."<name>".<col>`) rather than a shared dataset column — fragile (breaks if that user's column is renamed). Reference case: "Files Imported" MB headline used `Users."Samuel Porter".kb_to_mb`.
  - **Broken bloqs** (`errors:[…]`) sitting in saved explores (harmless if not in `measures`, but worth reporting).
  - **Event-name/source inconsistency** across tiles (human-readable raw events on one dataset vs UPPER_SNAKE on another).
- **Sampling** is worth stating (reference dashboard: DISABLED everywhere = full scans).

## 6. Reference data — reference dashboard entity map (seed for entity resolution)

Dashboard `436283174_2f31303e-…` ("Product & Engineering.Integrations: Adoption & Engagement"), app DataSnipper. Resolving these was left as a TODO in the session; capture them so re-analysis is instant and to seed a `--resolve` feature (batch `oa_find_entities`).

| entity_id (prefix `_2f31303e-…`) | meaning |
|---|---|
| `434646798` | actor **License User (Seat)** |
| `436309458` | dataset **Integrations events** (feature dataset) |
| `436309462` | event-type column on `Integrations events` (filter target) |
| `433251337` | raw **events dataset**; `433251343` = its event-type column |
| `436309475` | attribute **Integration Name** |
| `436309476` | `NUMBER_OF_FILES` |
| `436309477` | `INTEGRATIONS_SESSION_ID` |
| `436309478` | `TOTAL_FILES_SIZE_KB` |
| `436970464` | `kb_to_mb` (⚠ personal col `Users."Samuel Porter"`) |
| `433251099` | entity **Company License** |
| `433251102` | `HUBSPOT_COMPANY_ID` |
| `433251108` | **License Name** (also a dashboard filter col) |
| `433251113` | **License Type** / `COMPANY_USAGE_TYPE` (filter col) |
| `433251125` | **Exclude Domain** filter col |
| `433251197` | `HAS_ACCESS_TO_INTEGRATION_SUITE` (bool) |
| `434646799`, `434646801` | **UNRESOLVED** breakdown attributes — resolve via `oa_find_entities` |

Dashboard filter tiles (all user-selectable, `default_value:null`): License Name (`433251108`, EQUAL), License Type (`433251113`, EQUAL), Exclude Domain (`433251125`, NOT_CONTAINS), Integration Name (`436309475`, EQUAL).

## 7. Acceptance

- Running `/ds:analyze-oa-dashboard <reference URL>` reproduces the 12-tile table from the 2026-07-03 session, in **one main-context pass, no subagents, well under ~20k tokens**.
- `oa_explore_distill.py --summary f1..f12` prints all 12 rows without crashing on the two broken-bloq explores.
- The "smells" section flags the `Samuel Porter` personal column and the two broken bloqs.
