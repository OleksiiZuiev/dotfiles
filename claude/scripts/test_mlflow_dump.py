#!/usr/bin/env python3
"""Stdlib unittest coverage for mlflow_dump pure logic.

Run: python claude/scripts/test_mlflow_dump.py
"""

import json
import socket
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import mlflow_dump as m


class ResolveEnvTests(unittest.TestCase):
    def test_aliases_map_to_canonical_uri_and_experiment(self):
        self.assertEqual(
            m.resolve_env("dev"), ("https://mlflow-devweu.devds.net", "9")
        )
        self.assertEqual(
            m.resolve_env("prd"), ("https://mlflow-prdweu.devds.net", "1")
        )
        self.assertEqual(
            m.resolve_env("prod"), ("https://mlflow-prdweu.devds.net", "1")
        )

    def test_staging_alias_has_unknown_experiment(self):
        uri, exp = m.resolve_env("stg")
        self.assertEqual(uri, "https://mlflow-stgweu.devds.net")
        self.assertIsNone(exp)
        self.assertEqual(m.resolve_env("staging"), m.resolve_env("stg"))

    def test_canonical_names_pass_through(self):
        self.assertEqual(
            m.resolve_env("devweu"), ("https://mlflow-devweu.devds.net", "9")
        )
        self.assertEqual(
            m.resolve_env("prdweu"), ("https://mlflow-prdweu.devds.net", "1")
        )

    def test_case_insensitive_and_trimmed(self):
        self.assertEqual(m.resolve_env("  PRD  "), m.resolve_env("prd"))

    def test_uri_has_no_trailing_slash(self):
        for env in ("devweu", "deveus", "stgweu", "stgeus", "prdweu", "prdeus"):
            uri, _ = m.resolve_env(env)
            self.assertFalse(uri.endswith("/"), env)

    def test_unknown_env_raises_value_error(self):
        with self.assertRaises(ValueError):
            m.resolve_env("qa")

    def test_prdeus_experiment_is_one(self):
        self.assertEqual(
            m.resolve_env("prdeus"), ("https://mlflow-prdeus.devds.net", "1")
        )


class SessionSweepOrderTests(unittest.TestCase):
    def test_default_order_is_known_experiment_envs(self):
        self.assertEqual(m.session_sweep_order(), ["devweu", "prdweu", "prdeus"])

    def test_unverified_and_tls_broken_envs_excluded(self):
        order = m.session_sweep_order()
        for env in ("deveus", "stgweu", "stgeus"):
            self.assertNotIn(env, order)

    def test_preferred_alias_moves_to_front_deduped(self):
        self.assertEqual(m.session_sweep_order("prd"), ["prdweu", "devweu", "prdeus"])
        self.assertEqual(m.session_sweep_order("prdeus"), ["prdeus", "devweu", "prdweu"])

    def test_preferred_unknown_id_env_still_tried_first(self):
        # An explicitly-requested env with no known experiment id is searched first
        # anyway (the caller may have pinned --experiment); the rest follow.
        self.assertEqual(m.session_sweep_order("stgweu")[0], "stgweu")


class SpanIdOfTests(unittest.TestCase):
    def test_top_level_span_id(self):
        self.assertEqual(m.span_id_of({"span_id": "a"}), "a")

    def test_camel_case_span_id(self):
        self.assertEqual(m.span_id_of({"spanId": "b"}), "b")

    def test_nested_context_span_id(self):
        self.assertEqual(m.span_id_of({"context": {"span_id": "c"}}), "c")

    def test_missing_span_id_is_empty(self):
        self.assertEqual(m.span_id_of({}), "")


class BuildTreeArtifactSpansTests(unittest.TestCase):
    """Older-MLflow artifact spans nest the id under context.span_id and use start_time (ns)."""

    def _spans(self):
        return [
            {
                "name": "root", "context": {"span_id": "s1"}, "parent_id": "",
                "start_time": 1_000_000_000, "end_time": 3_000_000_000,
                "status": {"status_code": "OK"},
                "attributes": {"mlflow.spanType": '"AGENT"'},
            },
            {
                "name": "child", "context": {"span_id": "s2"}, "parent_id": "s1",
                "start_time": 1_500_000_000, "end_time": 1_800_000_000,
                "status": {"status_code": "OK"},
                "attributes": {"mlflow.spanType": '"TOOL"'},
            },
        ]

    def test_ids_types_and_nesting(self):
        _, index = m.build_tree(self._spans())
        self.assertEqual([n["span_id"] for n in index], ["s1", "s2"])
        self.assertEqual(index[1]["parent_id"], "s1")
        self.assertEqual(index[0]["type"], "AGENT")
        self.assertEqual(index[1]["type"], "TOOL")


_MSGS = [
    {
        "kind": "request",
        "parts": [
            {"part_kind": "system-prompt", "content": "You are a helpful agent."},
            {"part_kind": "user-prompt", "content": "find files"},
        ],
    },
    {
        "kind": "response",
        "parts": [
            {"part_kind": "tool-call", "tool_name": "find_integration_files",
             "args": {"query": "k-1"}},
        ],
    },
    {
        "kind": "request",
        "parts": [
            {"part_kind": "tool-return", "tool_name": "find_integration_files",
             "content": "service_unavailable"},
            {"part_kind": "retry-prompt", "content": "please try again"},
        ],
    },
    {
        "kind": "response",
        "parts": [
            {"part_kind": "text", "content": "The integration service is unavailable"},
        ],
    },
]


class CoerceMessageListTests(unittest.TestCase):
    def test_direct_list(self):
        self.assertEqual(m.coerce_message_list(_MSGS), _MSGS)

    def test_json_string(self):
        self.assertEqual(m.coerce_message_list(json.dumps(_MSGS)), _MSGS)

    def test_double_wrapped_output(self):
        self.assertEqual(m.coerce_message_list({"output": json.dumps(_MSGS)}), _MSGS)

    def test_messages_key(self):
        self.assertEqual(m.coerce_message_list({"messages": _MSGS}), _MSGS)

    def test_junk_returns_none(self):
        self.assertIsNone(m.coerce_message_list({"foo": "bar"}))
        self.assertIsNone(m.coerce_message_list("not json"))
        self.assertIsNone(m.coerce_message_list(123))
        self.assertIsNone(m.coerce_message_list([]))
        self.assertIsNone(m.coerce_message_list([{"no": "parts"}]))


class RenderTranscriptTests(unittest.TestCase):
    def test_each_part_kind_rendered(self):
        out = m.render_transcript(_MSGS)
        self.assertIn("[system]", out)
        self.assertIn("You are a helpful agent.", out)
        self.assertIn("[user] find files", out)
        self.assertIn("[tool-call] find_integration_files(", out)
        self.assertIn("k-1", out)
        self.assertIn("[tool-return] find_integration_files", out)
        self.assertIn("service_unavailable", out)
        self.assertIn("[retry]", out)
        self.assertIn("[assistant] The integration service is unavailable", out)


class ExtractMessagesTests(unittest.TestCase):
    def _span_with_output(self, payload):
        return {"attributes": {"mlflow.spanOutputs": json.dumps(payload)}}

    def test_picks_longest_valid_list(self):
        short = _MSGS[:1]
        spans = [
            self._span_with_output({"output": json.dumps(short)}),
            self._span_with_output({"output": json.dumps(_MSGS)}),
            {"attributes": {"mlflow.spanType": '"AGENT"'}},  # no spanOutputs
        ]
        self.assertEqual(m.extract_messages(spans), _MSGS)

    def test_no_messages_returns_empty(self):
        self.assertEqual(m.extract_messages([{"attributes": {}}]), [])


class LooksLikeTraceIdTests(unittest.TestCase):
    def test_trace_id_prefix(self):
        self.assertTrue(m.looks_like_trace_id("tr-f7b9954b086834fa78da6dcad1b75c8a"))

    def test_session_uuid_is_not_a_trace_id(self):
        self.assertFalse(m.looks_like_trace_id("dc21d160-d2c0-4517-a30a-3cabbd51c613"))

    def test_empty_is_not_a_trace_id(self):
        self.assertFalse(m.looks_like_trace_id(""))


class ConnectionErrorMessageTests(unittest.TestCase):
    def test_dns_failure_suggests_vpn_with_host(self):
        msg = m.connection_error_message(
            "https://mlflow-prdweu.devds.net/api/x",
            socket.gaierror(11001, "getaddrinfo failed"),
        )
        self.assertIn("VPN", msg)
        self.assertIn("mlflow-prdweu.devds.net", msg)

    def test_getaddrinfo_substring_also_triggers_vpn(self):
        msg = m.connection_error_message("https://h.devds.net/x", "getaddrinfo failed")
        self.assertIn("VPN", msg)

    def test_generic_connection_error_passes_through(self):
        msg = m.connection_error_message("https://h/x", TimeoutError("timed out"))
        self.assertIn("Connection failed", msg)
        self.assertNotIn("VPN", msg)


if __name__ == "__main__":
    unittest.main()
