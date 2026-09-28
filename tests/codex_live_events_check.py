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


def skill_event():
    return {
        "type": "skill.invoked",
        "item": {"skill_name": "extract-topics"},
    }


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
