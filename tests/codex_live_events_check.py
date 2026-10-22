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
DESKTOP_TOOLS = EXPECTED_TOOLS + ["write_conventions", "read_source_file", "write_article_draft", "finalize_article", "publish_article"]
EXPECTED_ARGUMENTS = {
    "date": "2099-01-03",
    "content": "# Agent fixture topics\n\n| Status | DRAFT |\n",
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
    def run_command_verifier(self, events, profile="topic", skill="extract-topics", tool="write_topic_draft", arguments=None):
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
                    skill,
                    profile,
                    tool,
                    json.dumps(EXPECTED_ARGUMENTS if arguments is None else arguments, sort_keys=True),
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

    def test_command_fails_on_a_qualified_unknown_bridge_generic_tool_call(self):
        unknown_call = direct_call_event()
        unknown_call["item"]["type"] = "tool_call"
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

    def test_command_rejects_unqualified_expected_tool_from_another_server(self):
        unrelated_call = direct_call_event()
        unrelated_call["item"]["server"] = "unrelated_mcp_server"
        self.assert_command_rejected(
            [skill_event("parent-a"), direct_catalog_event(), unrelated_call]
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



    def rpc_events(self, tools=None, skill="extract-topics", tool="write_topic_draft", arguments=None):
        root = str(ROOT)
        records = []
        def pair(method, params, result, request_id):
            records.extend([
                {"direction":"send", "message":{"id":request_id,"method":method,"params":params}},
                {"direction":"receive", "message":{"id":request_id,"result":result}},
            ])
        pair("thread/start", {"cwd":root}, {"thread":{"id":"parent-a"}}, 1)
        pair("mcpServerStatus/list", {"threadId":"parent-a","serverName":"blog_writer_bridge"},
             {"data":[{"name":"blog_writer_bridge","tools":{n:{"name":n} for n in (tools or DESKTOP_TOOLS)}}]}, 2)
        pair("turn/start", {"threadId":"parent-a","input":[{"type":"skill","name":skill,"path":str(ROOT/'.agents/skills'/skill/'SKILL.md')}]},
             {"turn":{"id":"turn-a"}}, 3)
        records.append({"direction":"receive", "message":{"method":"item/completed","params":{
            "threadId":"parent-a","turnId":"turn-a","item":{"type":"mcpToolCall","id":"call-a",
            "server":"blog_writer_bridge","tool":tool,"arguments":arguments or EXPECTED_ARGUMENTS,
            "status":"completed","result":{"isError":False}}}}})
        return records

    def test_desktop_accepts_real_protocol_for_each_workflow(self):
        cases = [
            ("extract-topics","write_topic_draft",EXPECTED_ARGUMENTS),
            ("author-conventions","write_conventions",{"content":"# Guidance", "overwrite":False}),
            ("write-blog-article","write_article_draft",{"slug":"fixture", "content":"draft", "overwrite":False}),
        ]
        for skill,tool,arguments in cases:
            with self.subTest(skill=skill):
                result = self.run_command_verifier(self.rpc_events(skill=skill,tool=tool,arguments=arguments),
                    profile="desktop",skill=skill,tool=tool,arguments=arguments)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),"parent-a")

    def test_desktop_three_workflows_share_one_parent_catalog(self):
        cases = [("extract-topics","write_topic_draft",EXPECTED_ARGUMENTS),
                 ("author-conventions","write_conventions",{"content":"Guidance","overwrite":False}),
                 ("write-blog-article","write_article_draft",{"slug":"fixture","content":"draft","overwrite":False})]
        events = self.rpc_events()[:4]
        for index,(skill,tool,args) in enumerate(cases):
            part = self.rpc_events(skill=skill,tool=tool,arguments=args)[4:]
            part[0]["message"]["id"] = part[1]["message"]["id"] = 3+index
            part[1]["message"]["result"]["turn"]["id"] = f"turn-{index}"
            part[2]["message"]["params"]["turnId"] = f"turn-{index}"
            events.extend(part)
        for skill,tool,args in cases:
            result=self.run_command_verifier(events,profile="desktop",skill=skill,tool=tool,arguments=args)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.strip(),"parent-a")

    def test_fixture_approval_is_limited_to_matching_preapproved_call(self):
        from codex_runtime_probe import fixture_approval_response
        request={"method":"mcpServer/elicitation/request","params":{"threadId":"parent-a","turnId":"turn-a",
            "serverName":"blog_writer_bridge","mode":"form","_meta":{"codex_approval_kind":"mcp_tool_call","tool_params":EXPECTED_ARGUMENTS},
            "message":'Allow the blog_writer_bridge MCP server to run tool "write_topic_draft"?',
            "requestedSchema":{"type":"object","properties":{}}}}
        records=self.rpc_events()[:6]
        expected=("parent-a","write_topic_draft",EXPECTED_ARGUMENTS)
        self.assertEqual(fixture_approval_response(request,records,expected),{"action":"accept","content":{}})
        params=request["params"]
        for field,value in (("message",'Allow publication?'),("serverName","other"),("threadId","other"),("turnId","other")):
            previous=params[field];params[field]=value
            self.assertIsNone(fixture_approval_response(request,records,expected));params[field]=previous
        params["_meta"]["tool_params"]={}
        self.assertIsNone(fixture_approval_response(request,records,expected))
        self.assertIsNone(fixture_approval_response(request,records,None))

    def test_protocol_rejects_null_result(self):
        events=self.rpc_events();events[-1]["message"]["params"]["item"]["result"]=None
        self.assertNotEqual(self.run_command_verifier(events,profile="desktop").returncode,0)

    def test_desktop_rejects_partial_extra_or_split_catalog(self):
        for tools in (DESKTOP_TOOLS[:-1],DESKTOP_TOOLS+["shell"]):
            result = self.run_command_verifier(self.rpc_events(tools=tools),profile="desktop")
            self.assertNotEqual(result.returncode,0)
        events=self.rpc_events()
        events[3]["message"]["id"]=999
        self.assertNotEqual(self.run_command_verifier(events,profile="desktop").returncode,0)

    def test_protocol_rejects_calls_from_wrong_thread_or_turn_and_error_results(self):
        for field,value in (("threadId","other"),("turnId","other")):
            events=self.rpc_events();events[-1]["message"]["params"][field]=value
            self.assertNotEqual(self.run_command_verifier(events,profile="desktop").returncode,0)
        events=self.rpc_events();events[-1]["message"]["params"]["item"]["result"]={"isError":True}
        self.assertNotEqual(self.run_command_verifier(events,profile="desktop").returncode,0)

    def test_protocol_requires_acknowledged_skill_and_correct_skill_path(self):
        for mutate in (lambda e:e[5]["message"].update({"id":999}),
                       lambda e:e[4]["message"]["params"]["input"][0].update({"path":"/unrelated/SKILL.md"})):
            events=self.rpc_events();mutate(events)
            self.assertNotEqual(self.run_command_verifier(events,profile="desktop").returncode,0)

    def test_narrow_protocol_catalog_rejects_desktop_union(self):
        result=self.run_command_verifier(self.rpc_events(),profile="topic")
        self.assertNotEqual(result.returncode,0)

    def test_command_rejects_two_partial_catalogs_whose_union_is_complete(self):
        self.assert_command_rejected([skill_event("parent-a"),direct_catalog_event(tools=EXPECTED_TOOLS[:2]),
                                     direct_catalog_event(tools=EXPECTED_TOOLS[2:]),direct_call_event()])

    def test_command_rejects_exact_then_changed_catalog(self):
        self.assert_command_rejected([skill_event("parent-a"),direct_catalog_event(),
                                     direct_catalog_event(tools=EXPECTED_TOOLS+["shell"]),direct_call_event()])


if __name__ == "__main__":
    unittest.main()
