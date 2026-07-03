---
description: Read an Optimizely Analytics dashboard's tiles + query definitions cheaply. Usage: /ds:analyze-oa-dashboard <dashboard-url|dashboard_id> [tile filter]
allowed-tools: Bash, Read, Write, mcp__optimizely-analytics__oa_list_apps, mcp__optimizely-analytics__oa_explores_for_dashboard, mcp__optimizely-analytics__oa_analyze_explore, mcp__optimizely-analytics__oa_confirm_app, mcp__optimizely-analytics__oa_find_entities, mcp__optimizely-analytics__oa_find_column_values
argument-hint: "<dashboard-url|dashboard_id> [optional: only tiles matching …]"
---

You are reading an Optimizely Analytics (OA) dashboard's tiles and their query definitions. The user provided:

**Arguments:** `{{$ARGUMENTS}}`

`oa_analyze_explore` returns **~130–150k chars per explore** because it bundles the query *definition* (`explore.detail`, a Java-serialized dump padded with noise keys) with the query *result data* (`data.upserts`). Reading a 12-tile dashboard the naive way cost ~350k tokens; the bulk of that was **spawning subagents to hold the payload**, which was pointless — the harness already auto-diverts any over-limit tool output to a file and returns only a ~200-token `saved to <path>` message. **Fire the calls in the main context, let each overflow to a file, and distill all files in one pass with `oa_explore_distill.py`.** Target for the whole dashboard: **~15k tokens**.

The `oa_*` MCP tools are deferred — if a call fails because a tool schema isn't loaded, run `ToolSearch select:oa_list_apps,oa_explores_for_dashboard,oa_analyze_explore` (etc.) first.

## Step 1 — Parse args

From `{{$ARGUMENTS}}`:
- A pasted dashboard URL looks like `…/dashboard/<dashboard_id>/?app=<app_uuid>`, where `dashboard_id` is `<number>_<uuid>`. Extract both `dashboard_id` and the `app` uuid.
- A bare `dashboard_id` (`<number>_<uuid>`) is also accepted; then there's no `app` uuid to pre-fill.
- **Remaining tokens = an optional tile filter** (e.g. "only conversion tiles"). Apply it when choosing which tiles to fetch in Step 4; default is all tiles.

## Step 2 — Resolve app

Call `oa_list_apps`. If the URL carried an `app` uuid, map it to its app name and use it. If there was no uuid (bare id) or it's ambiguous, ask the user which app. **Do not print the raw app uuid to the user** — refer to the app by name.

## Step 3 — List tiles

Call `oa_explores_for_dashboard(appid, dashboard_id)` — cheap (~4k tokens). Keep the result raw; it's small. From it, per explore tile, capture:
- the **explore `id`** — this is what `analyze_explore` takes,
- the tile names/types/layout from `all_tiles`,
- the `filter_tiles` (dashboard-level user-selectable filters).

**Hard rule — `id`, not `tile_id`:** in `explores_for_dashboard`, `explores[].id` is the explore; `tile_id` is the tile. **Passing a `tile_id` to `analyze_explore` throws a 500.** Use `id`.

## Step 4 — Fetch every explore in parallel

Issue **all** `oa_analyze_explore(appid, id, dashboard_id)` calls **in a single message** (independent calls batch fine), one per explore `id` from Step 3 (minus any excluded by the tile filter).

- **Hard rule — never Read a raw payload into context.** Each call overflows to a `tool-results/*.txt` file; collect the `saved to <path>` file paths from the ~200-token messages. That's all you need.
- **Inline-small edge case:** a tiny explore may return its JSON *inline* instead of overflowing (~40k tokens if you let it sit). If a call returns inline JSON rather than a `saved to <path>` message, immediately `Write` that JSON to a scratch file and use that path — do not distill it in place or analyze it inline.

## Step 5 — Distill once

Run one process over all collected paths:

```
python ~/.claude/scripts/oa_explore_distill.py --summary <path1> <path2> … <pathN>
```

It prints one compact block per explore (id · type/viz · measure(s) · breakdown · filter · range·grain · sampling), plus `⚠` lines for any smells. Use `--full` instead only when you need the noise-stripped query-spec JSON for one tile. It won't crash on broken-bloq explores (it flags them). Distillation output for a whole dashboard is ~4–6k tokens.

## Step 6 — Present

Render a markdown **table** of tiles — columns: tile · type/viz · measure(s) · breakdown · filter · range·grain — followed by a **"Smells"** section. Breakdown/filter show entity ids; resolve the ones that matter with `oa_find_entities` (batch them) if the user wants names, otherwise leave the ids.

Flag, don't hide, what the distiller surfaces:
- **Personal derived columns** in a measure — `Users."<name>".<col>` instead of a shared dataset column. Fragile: breaks if that user renames the column. (Reference case: a "Files Imported (MB)" headline built on `Users."Samuel Porter".kb_to_mb`.)
- **Broken bloqs** (`errors:[…]`, e.g. `Invalid Formula with null input`, `Missing input`) sitting in saved explores — harmless if not referenced by an active measure, but worth reporting.
- **Event-name/source inconsistency** across tiles (human-readable raw event names on one dataset vs `UPPER_SNAKE` on another).
- **Sampling** mode per tile — worth stating explicitly (all-`DISABLED` means every tile is a full scan).

## Hard rules (each of these bit the first run)

- **No subagents for this.** Overflow-to-file already isolates the payload; a subagent just adds its own system-prompt + schema-load cost (~330k of the ~350k wasted).
- **Use `id`, not `tile_id`,** for `analyze_explore`.
- **Never Read a raw `analyze_explore` payload** — collect the overflow file path and let the distiller read it.
