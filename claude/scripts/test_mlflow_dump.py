#!/usr/bin/env python3
"""Stdlib unittest coverage for mlflow_dump pure logic.

Run: python claude/scripts/test_mlflow_dump.py
"""

import argparse
import json
import socket
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))

import mlflow_dump as m


class ResolveEnvTests(unittest.TestCase):
    def test_aliases_map_to_canonical_uri(self):
        self.assertEqual(m.resolve_env("dev"), "https://mlflow-devweu.devds.net")
        self.assertEqual(m.resolve_env("prd"), "https://mlflow-prdweu.devds.net")
        self.assertEqual(m.resolve_env("prod"), "https://mlflow-prdweu.devds.net")

    def test_staging_alias_resolves_uri(self):
        self.assertEqual(m.resolve_env("stg"), "https://mlflow-stgweu.devds.net")
        self.assertEqual(m.resolve_env("staging"), m.resolve_env("stg"))

    def test_canonical_names_pass_through(self):
        self.assertEqual(m.resolve_env("devweu"), "https://mlflow-devweu.devds.net")
        self.assertEqual(m.resolve_env("prdweu"), "https://mlflow-prdweu.devds.net")

    def test_case_insensitive_and_trimmed(self):
        self.assertEqual(m.resolve_env("  PRD  "), m.resolve_env("prd"))

    def test_uri_has_no_trailing_slash(self):
        for env in ("devweu", "deveus", "stgweu", "stgeus", "prdweu", "prdeus"):
            uri = m.resolve_env(env)
            self.assertFalse(uri.endswith("/"), env)

    def test_unknown_env_raises_value_error(self):
        with self.assertRaises(ValueError):
            m.resolve_env("qa")

    def test_prdeus_resolves_uri(self):
        self.assertEqual(m.resolve_env("prdeus"), "https://mlflow-prdeus.devds.net")


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

    def test_preferred_env_still_tried_first(self):
        # An explicitly-requested env leads the order even when it isn't an auto-swept
        # region (the caller may have pinned --experiment, or want dynamic resolution there).
        self.assertEqual(m.session_sweep_order("stgweu")[0], "stgweu")


class ExperimentSearchOrderTests(unittest.TestCase):
    def test_agent_server_experiments_first_default_dropped(self):
        exps = [
            {"experiment_id": "0", "name": "Default"},
            {"experiment_id": "9", "name": "disclosure-accuracy-newLLMEvidenceFilter"},
            {"experiment_id": "1", "name": "agent-server-local-dev"},
            {"experiment_id": "5", "name": "agent-server"},
        ]
        # agent-server* first (input order preserved), then non-Default others; Default dropped.
        self.assertEqual(m.experiment_search_order(exps), ["1", "5", "9"])

    def test_case_insensitive_prefix(self):
        exps = [{"experiment_id": "3", "name": "Agent-Server-Staging"}]
        self.assertEqual(m.experiment_search_order(exps), ["3"])

    def test_tolerates_id_key_and_skips_blank(self):
        exps = [
            {"id": "7", "name": "agent-server"},             # tolerate the `id` key
            {"name": "no-id-here"},                          # skipped: no id
            {"experiment_id": "", "name": "agent-server"},   # skipped: blank id
        ]
        self.assertEqual(m.experiment_search_order(exps), ["7"])


class SearchSessionSweepTests(unittest.TestCase):
    """The core fix: a session is found by resolving experiments dynamically, even when the
    old hardcoded id pointed at the wrong (now-renamed) experiment."""

    def _args(self, env=None, experiment=None):
        return argparse.Namespace(session_uuid="sess-uuid", env=env, experiment=experiment)

    def test_finds_session_in_non_agent_id_experiment(self):
        # The bug: agent-server traces live in experiment 1 (agent-server-local-dev); the old
        # hardcoded devweu id (9) is now a disclosure-accuracy experiment with 0 matches.
        experiments = [
            {"experiment_id": "0", "name": "Default"},
            {"experiment_id": "9", "name": "disclosure-accuracy"},
            {"experiment_id": "1", "name": "agent-server-local-dev"},
        ]

        def fake_search(exp, uuid):
            return [{"trace_info": {"trace_id": "tr-x"}}] if exp == "1" else []

        with mock.patch.object(m, "list_experiments", return_value=experiments), \
             mock.patch.object(m, "search_session_traces", side_effect=fake_search):
            rows = m.search_session_with_sweep(self._args(env="devweu"))
        self.assertIsNotNone(rows)
        self.assertEqual(rows[0]["trace_id"], "tr-x")

    def test_unreachable_env_does_not_abort_sweep(self):
        experiments = [{"experiment_id": "5", "name": "agent-server"}]
        calls = {"n": 0}

        def fake_list():
            calls["n"] += 1
            if calls["n"] == 1:  # first env (devweu): flaky/unreachable, e.g. prdeus SSL EOF
                raise m.ConnectionFailure("[SSL: UNEXPECTED_EOF_WHILE_READING]")
            return experiments

        with mock.patch.object(m, "list_experiments", side_effect=fake_list), \
             mock.patch.object(m, "search_session_traces",
                               return_value=[{"trace_info": {"trace_id": "tr-y"}}]):
            rows = m.search_session_with_sweep(self._args())
        self.assertIsNotNone(rows)
        self.assertEqual(rows[0]["trace_id"], "tr-y")

    def test_all_reachable_empty_returns_none(self):
        experiments = [{"experiment_id": "5", "name": "agent-server"}]
        with mock.patch.object(m, "list_experiments", return_value=experiments), \
             mock.patch.object(m, "search_session_traces", return_value=[]):
            rows = m.search_session_with_sweep(self._args())
        self.assertIsNone(rows)


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

    def test_falls_back_to_span_inputs(self):
        # Sub-agent traces sometimes carry the message list on spanInputs, not spanOutputs.
        spans = [{"attributes": {"mlflow.spanInputs": json.dumps({"messages": _MSGS})}}]
        self.assertEqual(m.extract_messages(spans), _MSGS)

    def test_prefers_span_outputs_over_inputs(self):
        # When both exist, spanOutputs (the full history) wins — inputs is only a fallback.
        spans = [{
            "attributes": {
                "mlflow.spanOutputs": json.dumps(_MSGS),
                "mlflow.spanInputs": json.dumps(_MSGS[:1]),
            }
        }]
        self.assertEqual(m.extract_messages(spans), _MSGS)


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
