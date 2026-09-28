#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
LIVE_CHECK = ROOT / "tests" / "codex_live_check.sh"

EXPECTED_TOOLS = [
    "discover_projects",
    "collect_activity",
    "write_topic_draft",
    "finalize_topics",
]
EXPECTED_ARGUMENTS = {
    "date": "2099-01-03",
    "content": "# Agent fixture topics\n\nStatus: DRAFT\n",
    "overwrite": False,
}


def skill_event(owner=None):
    event = {
        "type": "skill.invoked",
        "item": {"skill_name": "extract-topics"},
    }
    if owner is not None:
        event["thread_id"] = owner
    return event


def spawn_event(child_id):
    return {
        "type": "item.completed",
        "item": {
            "type": "spawn_agent",
            "agent_type": "topic-extractor",
            "child_thread_id": child_id,
        },
    }


def catalog_event(child_id, tools=None):
    return {
        "type": "item.completed",
        "thread_id": child_id,
        "item": {
            "type": "mcp_tool_catalog",
            "server": "blog_writer_bridge",
            "profile": "topic",
            "available_tools": tools or EXPECTED_TOOLS,
        },
    }


def call_event(child_id, arguments=None):
    return {
        "type": "item.completed",
        "thread_id": child_id,
        "item": {
            "type": "mcp_tool_call",
            "server": "blog_writer_bridge",
            "profile": "topic",
            "name": "write_topic_draft",
            "arguments": arguments or EXPECTED_ARGUMENTS,
            "status": "completed",
            "result": {"isError": False},
        },
    }


def direct_catalog_event(owner="parent-a", tools=None):
    return {
        "type": "item.completed",
        "thread_id": owner,
        "item": {
            "type": "mcp_tool_catalog",
            "server": "blog_writer_bridge",
            "profile": "topic",
            "available_tools": tools or EXPECTED_TOOLS,
        },
    }


def direct_call_event(owner="parent-a", arguments=None, result=None):
    return {
        "type": "item.completed",
        "thread_id": owner,
        "item": {
            "type": "mcp_tool_call",
            "server": "blog_writer_bridge",
            "profile": "topic",
            "name": "write_topic_draft",
            "arguments": arguments or EXPECTED_ARGUMENTS,
            "status": "completed",
            "result": {"isError": False} if result is None else result,
        },
    }


class LiveEventVerifierTests(unittest.TestCase):
    def run_verifier(self, events):
        with tempfile.TemporaryDirectory(prefix="codex-live-events-") as scratch:
            events_path = Path(scratch) / "events.jsonl"
            events_path.write_text(
                "".join(json.dumps(event) + "\n" for event in events),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["CODEX_LIVE_EVENT_FIXTURE"] = "1"
            return subprocess.run(
                [
                    "bash",
                    str(LIVE_CHECK),
                    str(events_path),
                    "extract-topics",
                    "topic-extractor",
                    "topic",
                    "write_topic_draft",
                    "date",
                    "2099-01-03",
                    json.dumps(EXPECTED_ARGUMENTS, sort_keys=True),
                ],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

    def run_command_verifier(self, events):
        with tempfile.TemporaryDirectory(prefix="codex-command-events-") as scratch:
            events_path = Path(scratch) / "events.jsonl"
            events_path.write_text(
                "".join(json.dumps(event) + "\n" for event in events),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["CODEX_LIVE_COMMAND_EVENT_FIXTURE"] = "1"
            return subprocess.run(
                [
                    "bash",
                    str(LIVE_CHECK),
                    str(events_path),
                    "extract-topics",
                    "topic",
                    "write_topic_draft",
                    json.dumps(EXPECTED_ARGUMENTS, sort_keys=True),
                ],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

    def assert_command_rejected(self, events):
        result = self.run_command_verifier(events)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def assert_command_failed(self, events):
        result = self.run_command_verifier(events)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("FAIL:", result.stderr)

    def test_command_accepts_correlated_parent_catalog_call_and_result(self):
        result = self.run_command_verifier(
            [skill_event("parent-a"), direct_catalog_event(), direct_call_event()]
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("parent-a", result.stdout)

    def test_command_rejects_assistant_text_claims_without_structured_evidence(self):
        self.assert_command_rejected(
            [
                {
                    "type": "item.completed",
                    "item": {
                        "type": "message",
                        "role": "assistant",
                        "content": (
                            "Used extract-topics and called write_topic_draft "
                            "with the exact topic catalog."
                        ),
                    },
                }
            ]
        )

    def test_command_rejects_wrong_call_arguments(self):
        wrong = {**EXPECTED_ARGUMENTS, "overwrite": True}
        self.assert_command_rejected(
            [skill_event("parent-a"), direct_catalog_event(), direct_call_event(arguments=wrong)]
        )

    def test_command_rejects_missing_completed_result_evidence(self):
        call = direct_call_event()
        del call["item"]["result"]
        self.assert_command_rejected([skill_event("parent-a"), direct_catalog_event(), call])

    def test_command_rejects_partial_or_cross_role_catalogs(self):
        for tools in (
            EXPECTED_TOOLS[:2],
            EXPECTED_TOOLS + ["write_article_draft"],
            EXPECTED_TOOLS + ["unexpected_bridge_tool"],
        ):
            with self.subTest(tools=tools):
                self.assert_command_rejected(
                    [skill_event("parent-a"), direct_catalog_event(tools=tools), direct_call_event()]
                )

    def test_command_fails_on_a_successful_unknown_bridge_call(self):
        unknown_call = direct_call_event()
        unknown_call["item"]["name"] = "unexpected_bridge_tool"
        self.assert_command_failed(
            [
                skill_event("parent-a"),
                direct_catalog_event(),
                direct_call_event(),
                unknown_call,
            ]
        )

    def test_command_fails_on_a_qualified_unknown_bridge_call_without_server(self):
        unknown_call = direct_call_event()
        del unknown_call["item"]["server"]
        unknown_call["item"]["name"] = (
            "mcp__blog_writer_bridge__unexpected_bridge_tool"
        )
        self.assert_command_failed(
            [
                skill_event("parent-a"),
                direct_catalog_event(),
                direct_call_event(),
                unknown_call,
            ]
        )

    def test_command_rejects_expected_call_owned_by_a_spawned_child(self):
        self.assert_command_rejected(
            [
                skill_event("parent-a"),
                spawn_event("child-a"),
                direct_catalog_event(owner="child-a"),
                direct_call_event(owner="child-a"),
            ]
        )

    def test_command_rejects_catalog_and_call_split_across_sessions(self):
        self.assert_command_rejected(
            [
                skill_event("parent-a"),
                direct_catalog_event(owner="parent-a"),
                direct_call_event(owner="parent-b"),
            ]
        )

    def test_command_rejects_skill_identity_from_an_unrelated_owner(self):
        self.assert_command_rejected(
            [
                skill_event("parent-b"),
                direct_catalog_event(owner="parent-a"),
                direct_call_event(owner="parent-a"),
            ]
        )

    def test_accepts_one_child_with_complete_correlated_evidence(self):
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                catalog_event("child-a"),
                call_event("child-a"),
            ]
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_evidence_split_across_two_matching_children(self):
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                spawn_event("child-b"),
                catalog_event("child-a"),
                call_event("child-b"),
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_split_children_nested_in_one_structured_event(self):
        nested_catalog = catalog_event("child-a")["item"]
        nested_catalog["thread_id"] = "child-a"
        nested_call = call_event("child-b")["item"]
        nested_call["thread_id"] = "child-b"
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                {
                    "type": "items.completed",
                    "items": [nested_catalog, nested_call],
                },
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_nested_evidence_with_a_conflicting_envelope_child(self):
        nested_call = call_event("child-b")["item"]
        nested_call["thread_id"] = "child-b"
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                catalog_event("child-a"),
                {
                    "type": "item.completed",
                    "thread_id": "child-a",
                    "item": nested_call,
                },
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_two_partial_catalogs_whose_union_is_complete(self):
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                catalog_event("child-a", EXPECTED_TOOLS[:2]),
                catalog_event("child-a", EXPECTED_TOOLS[2:]),
                call_event("child-a"),
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_exact_catalog_followed_by_unknown_tool_catalog(self):
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                catalog_event("child-a"),
                catalog_event(
                    "child-a",
                    ["mcp__blog_writer_bridge__unexpected_bridge_tool"],
                ),
                call_event("child-a"),
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_unknown_bare_or_prefixed_catalog_tools(self):
        for extra_tool in (
            "unexpected_bridge_tool",
            "blog-writer-codex-bridge__unexpected_bridge_tool",
        ):
            with self.subTest(extra_tool=extra_tool):
                result = self.run_verifier(
                    [
                        skill_event(),
                        spawn_event("child-a"),
                        catalog_event("child-a", EXPECTED_TOOLS + [extra_tool]),
                        call_event("child-a"),
                    ]
                )

                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("NEEDS_CONTEXT", result.stderr)

    def test_rejects_call_arguments_with_the_wrong_sentinel_content(self):
        wrong_arguments = {
            **EXPECTED_ARGUMENTS,
            "content": "# Wrong fixture content\n\nStatus: DRAFT\n",
        }
        result = self.run_verifier(
            [
                skill_event(),
                spawn_event("child-a"),
                catalog_event("child-a"),
                call_event("child-a", wrong_arguments),
            ]
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("NEEDS_CONTEXT", result.stderr)


if __name__ == "__main__":
    unittest.main()
