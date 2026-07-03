---
description: Read an Optimizely Analytics dashboard cheaply — the whole tile table, or scoped to one tile with a question. Usage: /ds:analyze-oa-dashboard <dashboard-url|dashboard_id> [tile + optional question]
allowed-tools: Bash, Read, Write, mcp__optimizely-analytics__oa_list_apps, mcp__optimizely-analytics__oa_explores_for_dashboard, mcp__optimizely-analytics__oa_analyze_explore, mcp__optimizely-analytics__oa_confirm_app, mcp__optimizely-analytics__oa_find_entities, mcp__optimizely-analytics__oa_find_column_values
argument-hint: "<dashboard-url|dashboard_id> [a tile name/filter and/or a question about it]"
---

You are reading an Optimizely Analytics (OA) dashboard's tiles and their query definitions. The user provided:

**Arguments:** `{{$ARGUMENTS}}`

`oa_analyze_explore` returns **~130–150k chars per explore** because it bundles the query *definition* (`explore.detail`, a Java-serialized dump padded with noise keys) with the query *result data* (`data.upserts`). Reading a 12-tile dashboard the naive way cost ~350k tokens; the bulk of that was **spawning subagents to hold the payload**, which was pointless — the harness already auto-diverts any over-limit tool output to a file and returns only a ~200-token `saved to <path>` message. **Fire the calls in the main context, let each overflow to a file, and distill all files in one pass with `oa_explore_distill.py`.** Target for the whole dashboard: **~15k tokens**.

**Two modes** (auto-detected in Step 1 from whether the args scope to a tile):
- **Full read** (default, no tile focus): fetch every explore, present the whole tile table.
- **Targeted** (a tile is named/described, and/or a question is asked about a specific tile): fetch **only** the matching explore(s) and answer. The tile is identified from the **cheap** Step 3 listing (tile names + explore ids, no `analyze_explore` call), so a single-tile question costs ~1 explore fetch instead of N.

The `oa_*` MCP tools are deferred — if a call fails because a tool schema isn't loaded, run `ToolSearch select:oa_list_apps,oa_explores_for_dashboard,oa_analyze_explore` (etc.) first.

## Step 1 — Parse args

From `{{$ARGUMENTS}}`:
- A pasted dashboard URL looks like `…/dashboard/<dashboard_id>/?app=<app_uuid>`, where `dashboard_id` is `<number>_<uuid>`. Extract both `dashboard_id` and the `app` uuid.
- A bare `dashboard_id` (`<number>_<uuid>`) is also accepted; then there's no `app` uuid to pre-fill.
- **Everything after the id/URL is a free-form *focus*** — it may name/describe a tile, carry a question, both, or be empty:
  - **Empty** → **full read** mode.
  - **Names or describes a specific tile** (e.g. `Files Imported (MB)`, `the conversion-rate funnel`), optionally with a question (`… what filter does it use?`) → **targeted** mode. Hold onto both the tile reference and the question text.
  - **A question with no tile hint** → if it's clearly about one tile, treat it as targeted and resolve the tile in Step 3.5; if it's genuinely dashboard-wide (e.g. "which tiles use sampling?"), fall back to **full read**.

## Step 2 — Resolve app

Call `oa_list_apps`. If the URL carried an `app` uuid, map it to its app name and use it. If there was no uuid (bare id) or it's ambiguous, ask the user which app. **Do not print the raw app uuid to the user** — refer to the app by name.

## Step 3 — List tiles (always, cheap)

Call `oa_explores_for_dashboard(appid, dashboard_id)` — cheap (~4k tokens). Keep the result raw; it's small. From it, per explore tile, capture:
- the **explore `id`** — this is what `analyze_explore` takes,
- the tile names/types/layout from `all_tiles`,
- the `filter_tiles` (dashboard-level user-selectable filters).

Run this in **both** modes — it's what lets targeted mode pick a tile without any expensive fetch.

**Hard rule — `id`, not `tile_id`:** in `explores_for_dashboard`, `explores[].id` is the explore; `tile_id` is the tile. **Passing a `tile_id` to `analyze_explore` throws a 500.** Use `id`.

## Step 3.5 — Select which explores to fetch

- **Full read** → all explore `id`s from Step 3.
- **Targeted** → match the focus's tile reference against the tile names/types from Step 3 (`all_tiles`):
  - **One clear match** → that single explore `id`.
  - **A few plausible matches**, or the question spans a small set → those `id`s (still a subset, not all).
  - **Ambiguous or no match** → **do not guess**: show the user the tile list (names only, from Step 3 — still no fetch) and ask which tile(s) they mean (`AskUserQuestion`; fall back to a numbered list if it returns empty).

## Step 4 — Fetch the selected explores

Issue `oa_analyze_explore(appid, id, dashboard_id)` for the **selected** ids only — all in a single message when there's more than one (independent calls batch fine). In targeted single-tile mode this is usually one call.

- **Hard rule — never Read a raw payload into context.** Each call overflows to a `tool-results/*.txt` file; collect the `saved to <path>` file paths from the ~200-token messages. That's all you need.
- **Inline-small edge case:** a tiny explore may return its JSON *inline* instead of overflowing (~40k tokens if you let it sit). If a call returns inline JSON rather than a `saved to <path>` message, immediately `Write` that JSON to a scratch file and use that path — do not distill it in place or analyze it inline.

## Step 5 — Distill

Run one process over the collected paths:

```
python ~/.claude/scripts/oa_explore_distill.py --summary <path1> [<path2> …]
```

It prints one compact block per explore (id · type/viz · measure(s) · breakdown · filter · range·grain · sampling), plus `⚠` lines for any smells. It won't crash on broken-bloq explores (it flags them).

- For a **targeted deep question** about a single tile (e.g. "what exactly does this formula compute?", "show the full filter tree"), run `--full <that one path>` instead — it prints the whole noise-stripped query spec (all bloqs incl. inactive, the full predicate tree) and is still cheap for one explore.

## Step 6 — Present

- **Full read** → a markdown **table** of tiles (columns: tile · type/viz · measure(s) · breakdown · filter · range·grain), followed by a **"Smells"** section.
- **Targeted** → **answer the user's question directly**, citing the tile's distilled fields (measure/breakdown/filter/range·grain/sampling) as evidence; call out any smell on that tile. Keep it a focused answer, not the whole-dashboard table. If no explicit question was asked, give a short read of just that tile (its distilled block in prose).

Breakdown/filter show entity ids; resolve the ones that matter with `oa_find_entities` (batch them) if the user wants names, otherwise leave the ids.

Flag, don't hide, what the distiller surfaces:
- **Personal derived columns** in a measure — `Users."<name>".<col>` instead of a shared dataset column. Fragile: breaks if that user renames the column. (Reference case: a "Files Imported (MB)" headline built on `Users."Samuel Porter".kb_to_mb`.)
- **Broken bloqs** (`errors:[…]`, e.g. `Invalid Formula with null input`, `Missing input`) sitting in saved explores — harmless if not referenced by an active measure, but worth reporting.
- **Event-name/source inconsistency** across tiles (human-readable raw event names on one dataset vs `UPPER_SNAKE` on another) — full-read mode only; a single tile can't show inconsistency.
- **Sampling** mode per tile — worth stating explicitly (all-`DISABLED` means every tile is a full scan).

## Hard rules (each of these bit the first run)

- **No subagents for this.** Overflow-to-file already isolates the payload; a subagent just adds its own system-prompt + schema-load cost (~330k of the ~350k wasted).
- **Resolve the target tile from the cheap Step 3 listing** — never fetch all explores just to find the one you were asked about.
- **Use `id`, not `tile_id`,** for `analyze_explore`.
- **Never Read a raw `analyze_explore` payload** — collect the overflow file path and let the distiller read it.
