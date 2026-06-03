#!/usr/bin/env python3
"""Stdlib unittest coverage for mlflow_dump pure logic.

Run: python claude/scripts/test_mlflow_dump.py
"""

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
