#!/usr/bin/env python3
"""Isolated app-server probes and strict parent-session evidence verification."""
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time


def normalize_app_server_events(records):
    """Derive evidence only from acknowledged RPCs and their matching thread/turn."""
    if not any("direction" in r for r in records):
        return records
    pending = {}
    roots = {}
    events = []
    for record in records:
        message = record.get("message", {})
        direction = record.get("direction")
        request_id = message.get("id")
        if direction == "send" and "method" in message and request_id is not None:
            if request_id in pending:
                raise ValueError("duplicate RPC request identity")
            pending[request_id] = message
            continue
        if direction != "receive":
            continue
        if request_id is not None:
            request = pending.pop(request_id, None)
            if not request or "error" in message:
                continue
            result = message.get("result", {})
            params = request.get("params", {})
            method = request.get("method")
            if method == "thread/start":
                thread = result.get("thread", {}).get("id")
                if thread and isinstance(params.get("cwd"), str):
                    roots[thread] = Path(params["cwd"])
            elif method == "mcpServerStatus/list":
                thread = params.get("threadId")
                if thread not in roots or result.get("nextCursor"):
                    continue
                for server in result.get("data", []):
                    if server.get("name") == "blog_writer_bridge":
                        tools = server.get("tools", {})
                        events.append({"type":"catalog", "thread_id":thread, "item":{
                            "server":"blog_writer_bridge", "available_tools":list(tools)}})
            elif method == "turn/start":
                thread = params.get("threadId")
                turn = result.get("turn", {}).get("id")
                if thread not in roots or not turn:
                    continue
                for item in params.get("input", []):
                    skill = item.get("name")
                    if item.get("type") != "skill" or not isinstance(skill, str):
                        continue
                    expected_path = roots[thread] / '.agents' / 'skills' / skill / 'SKILL.md'
                    if item.get("path") != str(expected_path):
                        continue
                    events.append({"type":"skill.invoked", "thread_id":thread,
                                   "skill_name":skill, "turn_id":turn})
            continue
        if message.get("method") != "item/completed":
            continue
        params = message.get("params", {})
        thread, turn = params.get("threadId"), params.get("turnId")
        item = params.get("item", {})
        if item.get("type") == "collabAgentToolCall":
            events.append({"type":"collab", "child_thread_id":item.get("newThreadId")})
        if item.get("type") == "mcpToolCall":
            # Retain unknown/cross-role calls as negative evidence too.
            events.append({"type":"item.completed", "thread_id":thread, "item":{
                "type":"mcp_tool_call", "server":item.get("server"), "name":item.get("tool"),
                "arguments":item.get("arguments"), "status":item.get("status"),
                "turn_id":turn, **({"result":item["result"]} if "result" in item else {}),
                "error":item.get("error")}})
    return events


def verify_command_events(argv):
    import json
    import sys

    events_path, expected_skill, expected_profile, expected_tool, expected_json = argv
    try:
        expected_arguments = json.loads(expected_json)
    except json.JSONDecodeError:
        print("NEEDS_CONTEXT: expected MCP arguments are not valid JSON", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(expected_arguments, dict):
        print("NEEDS_CONTEXT: expected MCP arguments must be a JSON object", file=sys.stderr)
        raise SystemExit(2)

    profile_tools = {
        "topic": {
            "discover_projects",
            "collect_activity",
            "write_topic_draft",
            "finalize_topics",
        },
        "writer": {
            "read_source_file",
            "write_article_draft",
            "finalize_article",
            "publish_article",
        },
    }
    profile_tools["conventions"] = {"write_conventions"}
    profile_tools["desktop"] = set().union(*profile_tools.values())
    if expected_profile not in profile_tools or expected_tool not in profile_tools[expected_profile]:
        print("NEEDS_CONTEXT: unsupported expected command profile/tool", file=sys.stderr)
        raise SystemExit(2)
    expected_surface = profile_tools[expected_profile]

    events = []
    with open(events_path, encoding="utf-8") as handle:
        for line in handle:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                events.append(value)

    events = normalize_app_server_events(events)

    def objects(value):
        if isinstance(value, dict):
            yield value
            for child in value.values():
                yield from objects(child)
        elif isinstance(value, list):
            for child in value:
                yield from objects(child)

    def parsed_mapping(value):
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError:
                return None
            return parsed if isinstance(parsed, dict) else None
        return None

    def child_ids(value):
        found = set()
        for node in objects(value):
            desc = " ".join(
                str(node.get(key, "")).lower()
                for key in ("type", "kind", "name", "tool_name")
            )
            if not any(marker in desc for marker in ("spawn_agent", "custom_agent", "collab")):
                continue
            for key in (
                "child_thread_id",
                "child_agent_id",
                "spawned_thread_id",
                "spawned_agent_id",
            ):
                child = node.get(key)
                if isinstance(child, str) and child:
                    found.add(child)
        return found

    def owner(event, node):
        for candidate in (node, event):
            for key in ("thread_id", "agent_thread_id", "agent_id", "owner_id"):
                value = candidate.get(key)
                if isinstance(value, str) and value:
                    return value
        return "__parent__"

    bridge_tool_prefixes = (
        "mcp__blog_writer_bridge__",
        "blog-writer-codex-bridge__",
        "blog_writer_bridge.",
    )

    def normalize_tool(value):
        if not isinstance(value, str):
            return None
        for prefix in bridge_tool_prefixes:
            if value.startswith(prefix):
                return value[len(prefix):]
        return value

    def is_bridge_qualified_tool(value):
        return isinstance(value, str) and value.startswith(bridge_tool_prefixes)

    def servers(node):
        values = set()
        for key in ("server", "server_name", "mcp_server"):
            value = node.get(key)
            if isinstance(value, str):
                values.add(value)
        return values

    def is_bridge_server(values):
        return any(
            value in {"blog_writer_bridge", "blog-writer-codex-bridge"}
            or value.endswith("__blog_writer_bridge")
            for value in values
        )

    def surface(node):
        names = set()
        for key in ("available_tools", "tool_names", "mcp_tools"):
            values = node.get(key)
            if not isinstance(values, list):
                continue
            for value in values:
                if isinstance(value, dict):
                    value = value.get("name") or value.get("tool") or value.get("tool_name")
                name = normalize_tool(value)
                if name:
                    names.add(name)
        return names

    def call_name(node):
        bridge_server = is_bridge_server(servers(node))
        for key in ("name", "tool", "tool_name"):
            raw_name = node.get(key)
            name = normalize_tool(raw_name)
            if name and (bridge_server or is_bridge_qualified_tool(raw_name)):
                return name
        return None

    def call_arguments(node):
        for key in ("arguments", "args", "input"):
            value = parsed_mapping(node.get(key))
            if value is not None:
                return value
        return {}

    def successful_result(node, event_type):
        status = str(node.get("status", "")).lower()
        if status in {"failed", "error", "rejected", "unavailable"}:
            return False
        if not (event_type.lower().endswith("completed") or status in {"completed", "success", "succeeded"}):
            return False
        if "result" not in node:
            return False
        result = node.get("result")
        if not isinstance(result, dict):
            return False
        if isinstance(result, dict) and (result.get("isError") is True or result.get("is_error") is True):
            return False
        return node.get("error") in (None, False, "")

    skill_owners = [
        owner(event, node)
        for event in events
        for node in objects(event)
        if node.get("skill_name") == expected_skill
    ]
    spawned = set().union(*(child_ids(event) for event in events)) if events else set()
    catalogs = []
    calls = []
    for event in events:
        event_type = str(event.get("type", ""))
        for node in objects(event):
            record_owner = owner(event, node)
            advertised = surface(node)
            if advertised and is_bridge_server(servers(node)):
                catalogs.append((record_owner, advertised, node))
            name = call_name(node)
            if name:
                calls.append((record_owner, name, node, event_type))

    unsafe_calls = sorted(
        {
            name
            for _, name, node, event_type in calls
            if name not in expected_surface and successful_result(node, event_type)
        }
    )
    if unsafe_calls:
        print(
            "FAIL: command-scoped session completed cross-role MCP tool call(s): "
            + ", ".join(unsafe_calls),
            file=sys.stderr,
        )
        raise SystemExit(1)

    candidate_owners = sorted(
        {
            record_owner
            for record_owner, advertised, _ in catalogs
            if advertised == expected_surface and record_owner not in spawned
        }
    )
    valid = []
    for candidate in candidate_owners:
        if skill_owners.count(candidate) != 1:
            continue
        exact_catalogs = [
            advertised
            for record_owner, advertised, _ in catalogs
            if record_owner == candidate
        ]
        if exact_catalogs != [expected_surface]:
            continue
        matching_calls = [
            node
            for record_owner, name, node, event_type in calls
            if record_owner == candidate
            and name == expected_tool
            and call_arguments(node) == expected_arguments
            and successful_result(node, event_type)
            and (record_owner, node.get("turn_id")) in {
                (owner(e, n), n.get("turn_id")) for e in events for n in objects(e)
                if n.get("skill_name") == expected_skill
            }
        ]
        if len(matching_calls) == 1:
            valid.append(candidate)

    missing = []
    if not skill_owners:
        missing.append(f"skill identity {expected_skill}")
    elif not any(candidate in skill_owners for candidate in candidate_owners):
        missing.append(f"skill identity {expected_skill} on the same parent session")
    if not candidate_owners:
        missing.append(f"exact {expected_profile} profile catalog on the parent session")
    if not valid:
        missing.append(f"successful parent mcp_tool_call {expected_tool} with exact arguments and result")
    elif len(valid) > 1:
        missing.append("one unambiguous parent session satisfying every requirement")
    if missing:
        schema = {
            "event_types": sorted({str(event.get("type")) for event in events}),
            "spawned_child_ids": sorted(spawned),
            "catalogs": [
                {"owner": owner_id, "surface": sorted(advertised)}
                for owner_id, advertised, _ in catalogs
            ],
            "calls": [
                {"owner": owner_id, "name": name}
                for owner_id, name, _, _ in calls
            ],
        }
        print(
            "NEEDS_CONTEXT: structured Codex JSON lacks "
            + " and ".join(missing)
            + "; observed schema="
            + json.dumps(schema, sort_keys=True),
            file=sys.stderr,
        )
        raise SystemExit(2)

    print(valid[0])


def fixture_approval_response(message, records, expected):
    """Approve only the exact fixture call authorized by the probe's user input."""
    if not expected or message.get('method') != 'mcpServer/elicitation/request':
        return None
    thread, tool, arguments = expected
    params = message.get('params',{})
    meta = params.get('_meta',{})
    if (params.get('threadId') != thread or params.get('serverName') != 'blog_writer_bridge' or
        params.get('mode') != 'form' or meta.get('codex_approval_kind') != 'mcp_tool_call' or
        meta.get('tool_params') != arguments or
        params.get('message') != f'Allow the blog_writer_bridge MCP server to run tool "{tool}"?' or
        params.get('requestedSchema') != {'type':'object','properties':{}}):
        return None
    requests = {r['message'].get('id') for r in records if r.get('direction') == 'send'
                and r['message'].get('method') == 'turn/start'
                and r['message'].get('params',{}).get('threadId') == thread}
    acknowledged = any(r.get('direction') == 'receive' and r['message'].get('id') in requests
                       and r['message'].get('result',{}).get('turn',{}).get('id') == params.get('turnId')
                       for r in records)
    if not acknowledged:
        return None
    # No persistence metadata: approve this one fixture call only.
    return {'action':'accept','content':{}}



class AppServer:
    def __init__(self, project, codex_home, profile, events):
        self.records = []
        self.events = events.open('w', encoding='utf-8')
        self.errors = events.with_suffix('.stderr').open('w', encoding='utf-8')
        self.queue = queue.Queue()
        self.next_id = 0
        self.expected_approval = None
        command = ['codex', 'app-server']
        if profile != 'desktop':
            command.extend(['-c', 'mcp_servers.blog_writer_bridge.command="node"',
                            '-c', 'mcp_servers.blog_writer_bridge.args=' + json.dumps([
                                'codex-bridge/src/server.mjs', '--profile', profile])])
        # HOME is isolated too: a server that drops CODEX_HOME cannot reach real history.
        fixture_home = codex_home.parent / 'home'
        fixture_home.mkdir(exist_ok=True)
        fallback = fixture_home / '.codex'
        if not fallback.exists():
            fallback.symlink_to(codex_home, target_is_directory=True)
        self.process = subprocess.Popen(command, cwd=project,
            env={**os.environ, 'CODEX_HOME':str(codex_home), 'HOME':str(fixture_home)},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors,
            text=True, bufsize=1, start_new_session=True)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.process.stdout:
            self.queue.put(line)
        self.queue.put(None)

    def _record(self, direction, message):
        self.records.append({'direction':direction, 'message':message})
        self.events.write(json.dumps(self.records[-1])+'\n')
        self.events.flush()

    def send(self, method, params, request_id=None):
        message = {'method':method, 'params':params}
        if request_id is not None:
            message['id'] = request_id
        self._record('send', message)
        self.process.stdin.write(json.dumps(message)+'\n')
        self.process.stdin.flush()

    def receive(self, deadline):
        remaining = deadline-time.monotonic()
        if remaining <= 0:
            raise TimeoutError('app-server response timed out')
        try:
            line = self.queue.get(timeout=remaining)
        except queue.Empty as error:
            raise TimeoutError('app-server response timed out') from error
        if line is None:
            raise RuntimeError('app-server closed its output')
        message = json.loads(line)
        self._record('receive',message)
        if 'method' in message and 'id' in message:
            approval = fixture_approval_response(message,self.records,self.expected_approval)
            if approval is None:
                raise RuntimeError('unexpected approval request: '+json.dumps(message))
            response = {'id':message['id'],'result':approval}
            self._record('send',response)
            self.process.stdin.write(json.dumps(response)+'\n')
            self.process.stdin.flush()
        return message

    def rpc(self, method, params):
        self.next_id += 1
        request_id = self.next_id
        self.send(method,params,request_id)
        deadline = time.monotonic()+60
        while True:
            message = self.receive(deadline)
            if message.get('id') == request_id and 'method' not in message:
                if 'error' in message:
                    raise RuntimeError(method+' failed: '+json.dumps(message['error']))
                return message['result']

    def turn(self, thread, text, skill=None, project=None):
        inputs = [{'type':'text','text':text}]
        if skill:
            inputs.append({'type':'skill','name':skill,
                           'path':str(project/'.agents/skills'/skill/'SKILL.md')})
        start = len(self.records)
        turn = self.rpc('turn/start',{'threadId':thread, 'input':inputs})['turn']['id']
        deadline = time.monotonic()+180
        while True:
            for record in self.records[start:]:
                message = record['message']
                params = message.get('params',{})
                if message.get('method') == 'turn/completed' and params.get('threadId') == thread and params.get('turn',{}).get('id') == turn:
                    if params['turn'].get('status') != 'completed':
                        raise RuntimeError('fixture turn did not complete successfully')
                    return
            start = len(self.records)
            self.receive(deadline)

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid,signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid,signal.SIGKILL)
                self.process.wait(timeout=5)
        self.reader.join(timeout=1)
        self.process.stdin.close()
        self.process.stdout.close()
        self.events.close()
        self.errors.close()


def run_probe(project, codex_home, profile, events):
    project, codex_home, events = Path(project).resolve(), Path(codex_home).resolve(), Path(events).resolve()
    conventions = '# Writing conventions\n\nUse concise English first, then Italian. Use only Lang blocks and standard Markdown.\n'
    topic = '# Fixture topics\n\n| Status | DRAFT |\n'
    article = '---\ndraft: true\n---\n\nFixture English article.\n'
    date = '2099-01-07' if profile == 'desktop' else '2099-01-08'
    slug = 'desktop-fixture-article' if profile == 'desktop' else 'command-fixture-article'
    scenarios = [
        ('extract-topics','write_topic_draft',{'date':date,'content':topic,'overwrite':False},project/'inputs'/f'topics-{date}.md',topic),
        ('author-conventions','write_conventions',{'content':conventions,'overwrite':False},project/'CONVENTIONS.md',conventions),
        ('write-blog-article','write_article_draft',{'slug':slug,'content':article,'overwrite':False},project/'drafts'/f'{slug}.mdx',article),
    ]
    if profile == 'topic':
        scenarios = scenarios[:1]
    elif profile == 'writer':
        scenarios = scenarios[2:]
    server = AppServer(project,codex_home,profile,events)
    try:
        server.rpc('initialize',{'clientInfo':{'name':'blog-writer-acceptance','version':'1'},
                                 'capabilities':{'experimentalApi':True}})
        server.send('initialized',{})
        # Omit MCP and sandbox overrides in desktop mode: the project config is the subject.
        thread = server.rpc('thread/start',{'cwd':str(project),'approvalPolicy':'on-request','ephemeral':True})['thread']['id']
        deadline = time.monotonic()+30
        while True:
            catalog = server.rpc('mcpServerStatus/list',{'threadId':thread,'serverName':'blog_writer_bridge','detail':'toolsAndAuthOnly'})
            if any(entry.get('name') == 'blog_writer_bridge' and entry.get('tools') for entry in catalog.get('data',[])):
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('bridge catalog did not initialize; servers: '+json.dumps([{'name':e.get('name'), 'status':e.get('runtimeStatus'), 'error':e.get('toolsError')} for e in catalog.get('data',[])]))
            time.sleep(0.2)
        for skill,tool,args,target,content in scenarios:
            if target.exists():
                raise AssertionError('fixture output existed before its invocation: '+target.name)
            text = (f'${skill} This is an isolated transport acceptance fixture. '
                    'The user explicitly approves persisting the supplied already-reviewed DRAFT/document unchanged. '
                    'All interview answers and content choices for this fixture are complete; do not collect history, '
                    'generate replacement content, spawn agents, finalize, or publish. '
                    f'Call blog_writer_bridge.{tool} directly with exactly these JSON arguments: '+json.dumps(args)+'. '
                    'Stop after the tool result. Do not use shell or file tools to persist it.')
            server.expected_approval = (thread,tool,args)
            server.turn(thread,text,skill,project)
            server.expected_approval = None
            # Verify independently against recorded protocol and actual bytes, never model prose.
            verify_command_events([str(events),skill,profile,tool,json.dumps(args)])
            if not target.is_file() or target.read_bytes() != content.encode():
                raise AssertionError('missing or incorrect fixture effect: '+target.name)
            print('PASS: '+profile+' '+skill+' produced its correlated fixture effect',flush=True)
        if profile == 'desktop':
            # No sandbox override: command/exec inherits this project's policy.
            # A direct RPC avoids treating an assistant's claimed rejection as proof.
            denied = server.rpc('command/exec', {
                'command':['/bin/sh','-c','printf probe > direct-write-probe.txt'],
                'cwd':str(project), 'timeoutMs':10000})
            if (project/'direct-write-probe.txt').exists():
                raise AssertionError('read-only Codex sandbox allowed direct fixture writing')
            if denied.get('exitCode') in (None,0) or 'direct-write-probe.txt' not in denied.get('stderr',''):
                raise RuntimeError('no structured failed direct-write attempt was observed')
            print('PASS: read-only sandbox rejected the attempted direct write',flush=True)
        if list((project/'published').glob('*.mdx')) or (project/'inputs/published-topics.md').exists():
            raise AssertionError('DRAFT fixture unexpectedly published or changed the ledger')
    except BaseException:
        summary = []
        for record in server.records:
            message = record['message']
            params = message.get('params',{})
            item = params.get('item',{})
            if message.get('method') in ('configWarning','mcpServer/startupStatus/updated'):
                summary.append(message)
            elif message.get('method') == 'item/completed':
                summary.append({'type':item.get('type'), 'tool':item.get('tool'), 'server':item.get('server'), **({'arguments':item.get('arguments'), 'status':item.get('status'), 'result':item.get('result'), 'error':item.get('error'), 'turnId':params.get('turnId')} if item.get('type') == 'mcpToolCall' else {'text':item.get('text')} if item.get('type') == 'agentMessage' else {})})
        print('Runtime diagnostic: '+json.dumps(summary),file=sys.stderr)
        raise
    finally:
        server.close()


if __name__ == '__main__':
    try:
        if sys.argv[1:2] == ['--verify']:
            verify_command_events(sys.argv[2:])
        elif sys.argv[1:2] == ['--run'] and len(sys.argv) == 6:
            run_probe(*sys.argv[2:])
        else:
            raise ValueError('expected --verify events skill profile tool arguments, or --run project codex-home profile events')
    except AssertionError as error:
        print(f'FAIL: {error}',file=sys.stderr)
        raise SystemExit(1)
    except (ValueError, OSError, KeyError, TypeError, RuntimeError, TimeoutError) as error:
        print(f'NEEDS_CONTEXT: {error}',file=sys.stderr)
        raise SystemExit(2)
