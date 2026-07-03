#!/usr/bin/env python3
"""Stdlib unittest coverage for oa_explore_distill pure logic.

Run: python claude/scripts/test_oa_explore_distill.py

Fixtures are hand-built to match the shapes documented in the spec's field map
(§4 "Where the fields live"); they are deliberately small, not real payloads.
"""

import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SCRIPT = str(Path(__file__).parent / "oa_explore_distill.py")

sys.path.insert(0, str(Path(__file__).parent))

import oa_explore_distill as d


def event_segment_explore(netscript="sum(NUMBER_OF_FILES)", extra_bloqs=None):
    bloqs = [{"id": "b1", "display_name": "Files Imported", "type": "FORMULA", "netscript": netscript}]
    if extra_bloqs:
        bloqs.extend(extra_bloqs)
    return {
        "id": "436000001",
        "name": "files-imported",
        "description": "",
        "detail": {
            "sub_type": "EVENT_SEGMENT",
            "display_name": "Files Imported",
            "connection": {"orgid": 1, "appid": 2},
            "event_segment": {
                "chart_config": {"subType": "HEADLINE"},
                "bloqs": {"bloqs": bloqs},
                "measures": [{"bloq_id": "b1"}],
                "attributes": [{"entity_id": "436309475"}],
                "global_filters": [
                    {"junction": {"operands": [
                        {"predicate": {"property": {
                            "left": {"entity_id": "436309462"},
                            "operator": "EQUAL",
                            "right": {"literal": "INTEGRATIONS_IMPORT_COMPLETED"},
                        }}},
                    ]}},
                ],
                "time_range_param_value": "30d",
                "time_grain_param_value": "week",
                "sampling_spec": {"mode": "DISABLED"},
            },
        },
    }


def funnel_explore():
    return {
        "id": "436000002",
        "name": "import-funnel",
        "detail": {
            "sub_type": "FUNNEL_BLOQ",
            "display_name": "Import Funnel",
            "funnel_bloq_template": {
                "chart_config": {"subType": "BAR"},
                "measures": [{"type": "CONVERSION_RATE"}],
                "sequence": {"stages": [
                    {"event": {"name": "INTEGRATIONS_IMPORT_STARTED"}},
                    {"event": {"name": "INTEGRATIONS_IMPORT_COMPLETED"}},
                ]},
                "time_range_param_value": "90d",
                "time_grain_param_value": "day",
                "sampling_spec": {"mode": "DISABLED"},
            },
        },
    }


class CleanTests(unittest.TestCase):
    def test_strips_noise_keys_and_initialize_shim_suffixes(self):
        o = {"keep": 1, "to_string": "x", "hash_code": 2,
             "foo_initialize": 3, "bar_shim": 4, "init_shim": 5, "orgid": 9}
        self.assertEqual(d.clean(o), {"keep": 1})

    def test_drops_empty_values(self):
        o = {"a": "", "b": {}, "c": [], "e": "v"}
        self.assertEqual(d.clean(o), {"e": "v"})

    def test_recurses_into_nested_dicts(self):
        o = {"x": {"pretty_print": "30d", "keep": "v"}}
        self.assertEqual(d.clean(o), {"x": {"keep": "v"}})


class CollapseTimeTests(unittest.TestCase):
    def test_is_now(self):
        self.assertEqual(d.collapse_time({"is_now": True, "foo": 1}), "now")

    def test_pretty_print_unit_with_negate(self):
        self.assertEqual(d.collapse_time({"pretty_print": "30d", "unit": "DAY", "negate_offset": True}), "-30d")

    def test_start_end_interval(self):
        o = {"start_time": {"is_now": True}, "end_time": {"is_now": True}, "is_unbounded": False}
        self.assertEqual(d.collapse_time(o), {"start": "now", "end": "now", "unbounded": False})


class DistillExploreTests(unittest.TestCase):
    def test_shape(self):
        out = d.distill_explore(event_segment_explore())
        self.assertEqual(out["explore_id"], "436000001")
        self.assertEqual(out["sub_type"], "EVENT_SEGMENT")
        self.assertEqual(out["display_name"], "Files Imported")
        self.assertIn("event_segment", out["templates"])
        self.assertNotIn("connection", out["templates"])

    def test_explore_template_deduped_when_redundant(self):
        exp = event_segment_explore()
        exp["detail"]["explore_template"] = dict(exp["detail"]["event_segment"])
        out = d.distill_explore(exp)
        self.assertNotIn("explore_template", out["templates"])
        self.assertIn("event_segment", out["templates"])


class FindExploreTests(unittest.TestCase):
    def test_top_level_explore(self):
        self.assertEqual(d.find_explore({"explore": {"id": "E"}, "data": {}})["id"], "E")

    def test_enveloped_explore(self):
        payload = {"content": [{"text": "noise"}], "result": {"explore": {"id": "E", "detail": {}}}}
        self.assertEqual(d.find_explore(payload)["id"], "E")

    def test_missing_explore_raises(self):
        with self.assertRaises(ValueError):
            d.find_explore({"data": {"upserts": []}})


class SummaryProjectionTests(unittest.TestCase):
    def test_event_segment_fields(self):
        s = d.project_summary(d.distill_explore(event_segment_explore()))
        self.assertEqual(s["sub_type"], "EVENT_SEGMENT")
        self.assertEqual(s["chart_type"], "HEADLINE")
        self.assertIn("sum(NUMBER_OF_FILES)", " ".join(s["measures"]))
        self.assertIn("436309475", s["breakdown"])
        self.assertIn("EQUAL", s["filter"])
        self.assertIn("INTEGRATIONS_IMPORT_COMPLETED", s["filter"])
        self.assertEqual(s["range"], "30d")
        self.assertEqual(s["grain"], "week")
        self.assertEqual(s["sampling"], "DISABLED")
        self.assertEqual(s["warnings"], [])

    def test_personal_column_dependency_flagged(self):
        exp = event_segment_explore(netscript='sum(TOTAL_FILES_SIZE_KB) * Users."Samuel Porter".kb_to_mb')
        s = d.project_summary(d.distill_explore(exp))
        self.assertTrue(any('Users."Samuel Porter"' in w for w in s["warnings"]))

    def test_broken_bloq_flagged_and_no_crash(self):
        broken = {"id": "b2", "display_name": "Stray", "type": "FORMULA",
                  "errors": [{"message": "Invalid Formula with null input"}]}
        exp = event_segment_explore(extra_bloqs=[broken])
        s = d.project_summary(d.distill_explore(exp))
        self.assertTrue(any("Invalid Formula with null input" in w for w in s["warnings"]))
        # the broken bloq is not the active measure, so it must not appear as a measure
        self.assertNotIn("Stray", " ".join(s["measures"]))

    def test_funnel_measure_lists_stages(self):
        s = d.project_summary(d.distill_explore(funnel_explore()))
        self.assertEqual(s["sub_type"], "FUNNEL_BLOQ")
        self.assertEqual(s["chart_type"], "BAR")
        joined = " ".join(s["measures"])
        self.assertIn("CONVERSION_RATE", joined)
        self.assertIn("INTEGRATIONS_IMPORT_STARTED", joined)
        self.assertIn("INTEGRATIONS_IMPORT_COMPLETED", joined)


class RenderSummaryTests(unittest.TestCase):
    def test_block_contains_header_and_labels(self):
        block = d.render_summary(d.distill_explore(event_segment_explore()))
        self.assertIn("436000001", block)
        self.assertIn("EVENT_SEGMENT", block)
        self.assertIn("HEADLINE", block)
        self.assertIn("measure(s):", block)
        self.assertIn("range·grain: 30d · week", block)
        self.assertIn("sampling: DISABLED", block)

    def test_missing_fields_render_dash(self):
        bare = {"explore_id": "x", "sub_type": "UNIVERSAL", "display_name": "", "name": "", "templates": {}}
        block = d.render_summary(bare)
        self.assertIn("—", block)


class CliTests(unittest.TestCase):
    def _write(self, tmp, name, explore):
        p = Path(tmp) / name
        p.write_text(json.dumps({"explore": explore, "data": {"upserts": []}}), encoding="utf-8")
        return str(p)

    def test_summary_over_multiple_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            f1 = self._write(tmp, "a.json", event_segment_explore())
            f2 = self._write(tmp, "b.json", funnel_explore())
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = d.main(["--summary", f1, f2])
            out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("436000001", out)
        self.assertIn("436000002", out)

    def test_full_is_default_and_includes_broken_bloq(self):
        broken = {"id": "b2", "display_name": "Stray", "type": "FORMULA",
                  "errors": [{"message": "Missing input"}]}
        with tempfile.TemporaryDirectory() as tmp:
            f1 = self._write(tmp, "a.json", event_segment_explore(extra_bloqs=[broken]))
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = d.main([f1])
            out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("Missing input", out)

    def test_subprocess_emits_utf8_glyphs(self):
        """Guards against a cp1252 console crash on the → · ⚠ glyphs (a pipe defaults
        to the locale encoding, so this reproduces the real failure)."""
        with tempfile.TemporaryDirectory() as tmp:
            f1 = self._write(tmp, "a.json", event_segment_explore())
            proc = subprocess.run(
                [sys.executable, SCRIPT, "--summary", f1],
                capture_output=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr.decode("utf-8", "replace"))
        out = proc.stdout.decode("utf-8")
        self.assertIn("range·grain", out)

    def test_bad_file_does_not_crash(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.json"
            bad.write_text("{not json", encoding="utf-8")
            good = self._write(tmp, "good.json", event_segment_explore())
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = d.main(["--summary", str(bad), good])
            out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("436000001", out)


if __name__ == "__main__":
    unittest.main()
