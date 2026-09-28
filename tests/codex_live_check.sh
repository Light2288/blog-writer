#!/usr/bin/env bash
#
# Opt-in live Codex acceptance. The default path is always a no-op SKIP.
# Enabled probes use a temporary project and temporary CODEX_HOME; no real
# rollout history is read and every attempted write targets the fixture only.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; }
needs_context() { printf 'NEEDS_CONTEXT: %s\n' "$1"; exit 2; }
skip() { printf 'SKIP: %s\n' "$1"; }

# verify_agent_events <events.jsonl> <skill> <agent> <profile> <tool> <arg-key> <arg-value>
# Only structured Codex events count. Assistant text is intentionally ignored.
verify_agent_events() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json
import sys

(
    events_path,
    expected_skill,
    expected_agent,
    expected_profile,
    expected_tool,
    expected_arg_key,
    expected_arg_value,
) = sys.argv[1:]
profile_tools = {
    "topic-extractor": {
        "discover_projects",
        "collect_activity",
        "write_topic_draft",
        "finalize_topics",
    },
    "conventions-writer": {"write_conventions"},
    "blog-writer": {
        "read_source_file",
        "write_article_draft",
        "finalize_article",
        "publish_article",
    },
}
all_tools = set().union(*profile_tools.values())
cross_role_tools = all_tools - profile_tools[expected_agent]

events = []
with open(events_path, encoding="utf-8") as handle:
    for line in handle:
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            events.append(value)

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

def structured_skill(value):
    for node in objects(value):
        skill_name = node.get("skill_name")
        if skill_name == expected_skill:
            return True
        skill = node.get("skill")
        if isinstance(skill, dict) and skill.get("name") == expected_skill:
            return True
    return False

def structured_agent(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"agent_type", "agent_name", "target_agent", "custom_agent"} and child == expected_agent:
                return True
            if key in {"arguments", "args", "input"} and isinstance(child, str):
                parsed = parsed_mapping(child)
                if parsed is not None and structured_agent(parsed):
                    return True
            if structured_agent(child):
                return True
    elif isinstance(value, list):
        return any(structured_agent(child) for child in value)
    return False

def values_for_keys(value, keys):
    values = set()
    for node in objects(value):
        for key in keys:
            candidate = node.get(key)
            if isinstance(candidate, (str, int)) and str(candidate):
                values.add(str(candidate))
    return values

def child_ids(value):
    return values_for_keys(
        value,
        {
            "child_agent_id",
            "child_thread_id",
            "receiver_thread_id",
            "spawned_agent_id",
            "spawned_thread_id",
            "target_agent_id",
            "agent_thread_id",
            "target_thread_id",
        },
    )

def association_ids(value):
    return child_ids(value) | values_for_keys(
        value,
        {"agent_id", "thread_id", "conversation_id"},
    )

def descriptor(node):
    return " ".join(
        str(node.get(key, "")).lower()
        for key in ("type", "kind", "method", "tool", "tool_name", "name")
    )

def canonical_tool(value):
    if not isinstance(value, str):
        return None
    for known in all_tools:
        if value == known or value.endswith(f"__{known}"):
            return known
    return None

def tool_name(node):
    for key in ("tool", "tool_name", "name"):
        known = canonical_tool(node.get(key))
        if known:
            return known
    return None

def tool_arguments(node):
    for key in ("arguments", "args", "input"):
        arguments = parsed_mapping(node.get(key))
        if arguments is not None:
            return arguments
    return {}

def failed_call(node):
    status = str(node.get("status", "")).lower()
    if status in {"failed", "error", "rejected", "unavailable"}:
        return True
    if node.get("isError") is True or node.get("is_error") is True:
        return True
    error = node.get("error")
    if error not in (None, False, ""):
        return True
    result = node.get("result")
    return isinstance(result, dict) and (
        result.get("isError") is True or result.get("is_error") is True
    )

def terminal_call(node, event_type):
    status = str(node.get("status", "")).lower()
    return (
        str(event_type).lower().endswith("completed")
        or status in {"completed", "success", "succeeded", "failed", "error", "rejected", "unavailable"}
        or failed_call(node)
    )

def unavailable_call(node):
    markers = {
        "forbidden",
        "not_found",
        "not found",
        "not_registered",
        "not registered",
        "rejected",
        "unavailable",
        "unknown_tool",
        "unknown tool",
    }
    for candidate in objects(node):
        for key in ("status", "code", "kind", "reason", "type"):
            value = candidate.get(key)
            if isinstance(value, str) and value.lower() in markers:
                return True
        error = candidate.get("error")
        if isinstance(error, str):
            lowered = error.lower()
            if any(marker in lowered for marker in markers):
                return True
    return False

def surface_names(node):
    names = set()
    for key in ("available_tools", "tool_names", "mcp_tools"):
        values = node.get(key)
        if not isinstance(values, list):
            continue
        for value in values:
            if isinstance(value, str):
                candidate = value
            elif isinstance(value, dict):
                candidate = value.get("name") or value.get("tool") or value.get("tool_name")
            else:
                continue
            known = canonical_tool(candidate)
            if known:
                names.add(known)
            elif isinstance(candidate, str) and "blog_writer_bridge" in candidate:
                names.add(candidate.rsplit("__", 1)[-1])
    return names

def server_names(value):
    names = values_for_keys(value, {"server", "server_name", "mcp_server"})
    for node in objects(value):
        for key in ("tool", "tool_name", "name"):
            candidate = node.get(key)
            if isinstance(candidate, str) and "__" in candidate:
                names.add(candidate.rsplit("__", 1)[0])
    return names

def profile_names(value):
    profiles = values_for_keys(value, {"profile", "profile_name", "mcp_profile"})
    for node in objects(value):
        for key in ("args", "arguments", "command_args"):
            args = node.get(key)
            if not isinstance(args, list):
                continue
            for index, arg in enumerate(args[:-1]):
                if arg == "--profile" and isinstance(args[index + 1], str):
                    profiles.add(args[index + 1])
    return profiles

skill_seen = any(structured_skill(event) for event in events)
spawn_records = []
tool_events = []
surface_events = []
metadata_events = []
for event in events:
    for node in objects(event):
        desc = descriptor(node)
        if (
            ("spawn_agent" in desc or "spawn" in desc or "collab" in desc or "custom_agent" in desc)
            and structured_agent(node)
        ):
            spawn_records.append({"ids": child_ids(node), "node": node})
        ids = association_ids(event) | association_ids(node)
        name = tool_name(node)
        if name and (
            "mcp_tool_call" in desc
            or "mcp" in desc
            or any(key in node for key in ("server", "server_name", "mcp_server"))
        ):
            tool_events.append(
                {
                    "name": name,
                    "node": node,
                    "event_type": event.get("type"),
                    "ids": ids,
                }
            )
        surface = surface_names(node)
        if surface:
            surface_events.append({"surface": surface, "node": node, "ids": ids})
        servers = server_names(node)
        profiles = profile_names(node)
        if servers or profiles:
            metadata_events.append(
                {"servers": servers, "profiles": profiles, "ids": ids}
            )

spawn_agent_ids = set().union(*(record["ids"] for record in spawn_records), set())
mcp_agent_ids = set().union(
    *(record["ids"] for record in tool_events + surface_events),
    set(),
)
shared_agent_ids = spawn_agent_ids & mcp_agent_ids

def correlated(record):
    return bool(record["ids"] & shared_agent_ids)

correlated_tools = [record for record in tool_events if correlated(record)]
correlated_surfaces = [record for record in surface_events if correlated(record)]
correlated_metadata = [record for record in metadata_events if correlated(record)]

unexpected_success = sorted(
    {
        record["name"]
        for record in correlated_tools
        if record["name"] in cross_role_tools
        and terminal_call(record["node"], record["event_type"])
        and not failed_call(record["node"])
    }
)
exact_surface = any(
    surface == profile_tools[expected_agent]
    for surface in (record["surface"] for record in correlated_surfaces)
)
observed_allowed_tools = {
    record["name"]
    for record in correlated_tools
    if record["name"] in profile_tools[expected_agent]
}
for record in correlated_surfaces:
    observed_allowed_tools.update(
        record["surface"] & profile_tools[expected_agent]
    )
rejected_cross_role_tools = {
    record["name"]
    for record in correlated_tools
    if record["name"] in cross_role_tools
    and terminal_call(record["node"], record["event_type"])
    and unavailable_call(record["node"])
}
fallback_surface = (
    observed_allowed_tools == profile_tools[expected_agent]
    and rejected_cross_role_tools == cross_role_tools
)
primary_calls = [
    record
    for record in correlated_tools
    if record["name"] == expected_tool
    and terminal_call(record["node"], record["event_type"])
    and not failed_call(record["node"])
    and expected_arg_value
    in str(tool_arguments(record["node"]).get(expected_arg_key, ""))
]
server_verified = any(
    any(
        server in {"blog_writer_bridge", "blog-writer-codex-bridge"}
        or server.endswith("__blog_writer_bridge")
        for server in record["servers"]
    )
    for record in correlated_metadata
)
profile_verified = any(
    expected_profile in record["profiles"]
    for record in correlated_metadata
)
schema = {
    "event_types": sorted({str(event.get("type")) for event in events}),
    "item_types": sorted(
        {
            str(event.get("item", {}).get("type"))
            for event in events
            if isinstance(event.get("item"), dict)
        }
    ),
    "top_level_keys": sorted({key for event in events for key in event}),
    "structured_skill_names": sorted(
        {
            str(node.get("skill_name"))
            for event in events
            for node in objects(event)
            if node.get("skill_name") is not None
        }
    ),
    "spawn_agent_ids": sorted(spawn_agent_ids),
    "mcp_agent_ids": sorted(mcp_agent_ids),
    "shared_agent_ids": sorted(shared_agent_ids),
    "structured_mcp_tools": sorted({record["name"] for record in tool_events}),
    "structured_tool_surfaces": [
        sorted(record["surface"]) for record in surface_events
    ],
    "structured_servers": sorted(
        set().union(*(record["servers"] for record in metadata_events), set())
    ),
    "structured_profiles": sorted(
        set().union(*(record["profiles"] for record in metadata_events), set())
    ),
}

if unexpected_success:
    print(
        f"FAIL: {expected_agent} completed cross-role MCP tool call(s): {', '.join(unexpected_success)}",
        file=sys.stderr,
    )
    raise SystemExit(1)
missing = []
if not skill_seen:
    missing.append(f"skill identity {expected_skill}")
if not spawn_records:
    missing.append(f"spawn identity {expected_agent}")
elif not spawn_agent_ids:
    missing.append(f"child identifier for spawn {expected_agent}")
if not shared_agent_ids:
    missing.append(f"shared child identifier for {expected_agent} MCP evidence")
if not server_verified:
    missing.append("MCP server blog_writer_bridge")
if not profile_verified:
    missing.append(f"MCP profile {expected_profile}")
if not primary_calls:
    missing.append(
        f"successful mcp_tool_call {expected_tool} with "
        f"{expected_arg_key}={expected_arg_value}"
    )
if not (exact_surface or fallback_surface):
    missing.append(
        "exact role tool catalog or fallback evidence for all allowed tools "
        "and every cross-role rejection"
    )
if missing:
    print(
        "NEEDS_CONTEXT: structured Codex JSON lacks "
        + " and ".join(missing)
        + "; observed schema="
        + json.dumps(schema, sort_keys=True),
        file=sys.stderr,
    )
    raise SystemExit(2)
PY
}

if [ "${CODEX_ACCEPTANCE_RUNTIME:-}" != "1" ]; then
  skip "live Codex cases (set CODEX_ACCEPTANCE_RUNTIME=1 to run isolated runtime probes)"
  exit 0
fi

command -v codex >/dev/null 2>&1 || needs_context "Codex CLI is not on PATH"
command -v node >/dev/null 2>&1 || needs_context "Node.js is not on PATH"
[ -d "$ROOT/codex-bridge/node_modules/@modelcontextprotocol/sdk" ] || \
  needs_context "bridge dependencies are missing; run npm install --prefix codex-bridge"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/blog-writer-codex-live.XXXXXX")"
FIXTURE_PROJECT="$SCRATCH/project"
FIXTURE_CODEX_HOME="$SCRATCH/codex-home"
WRITE_OUTPUT="$SCRATCH/write.txt"
WRITE_EVENTS="$SCRATCH/write.jsonl"

cleanup() {
  if [ -d "$SCRATCH" ]; then
    rm -r -- "$SCRATCH"
  fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p \
  "$FIXTURE_PROJECT/inputs" \
  "$FIXTURE_PROJECT/drafts" \
  "$FIXTURE_PROJECT/published" \
  "$FIXTURE_PROJECT/codex-bridge" \
  "$FIXTURE_CODEX_HOME/sessions/2099/01/02"
cp -R "$ROOT/.agents" "$ROOT/.codex" "$FIXTURE_PROJECT/"
cp -R "$ROOT/codex-bridge/src" "$FIXTURE_PROJECT/codex-bridge/"
cp "$ROOT/codex-bridge/package.json" "$ROOT/codex-bridge/package-lock.json" \
  "$FIXTURE_PROJECT/codex-bridge/"
cp "$ROOT/AGENTS.md" "$ROOT/CONVENTIONS.template.md" "$FIXTURE_PROJECT/"
ln -s "$ROOT/codex-bridge/node_modules" \
  "$FIXTURE_PROJECT/codex-bridge/node_modules"
git -C "$FIXTURE_PROJECT" init --quiet

# Trust only the disposable fixture project. Authentication is copied without
# copying config, sessions, or any other history from the user's Codex home.
quoted_project="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$FIXTURE_PROJECT")"
printf '[projects.%s]\ntrust_level = "trusted"\n' "$quoted_project" \
  > "$FIXTURE_CODEX_HOME/config.toml"

AUTH_HOME="${CODEX_ACCEPTANCE_AUTH_HOME:-${CODEX_HOME:-$HOME/.codex}}"
if [ -f "$AUTH_HOME/auth.json" ]; then
  cp "$AUTH_HOME/auth.json" "$FIXTURE_CODEX_HOME/auth.json"
  chmod 600 "$FIXTURE_CODEX_HOME/auth.json"
fi

if ! CODEX_HOME="$FIXTURE_CODEX_HOME" codex login status >/dev/null 2>&1; then
  needs_context "isolated CODEX_HOME has no usable login; set CODEX_ACCEPTANCE_AUTH_HOME to an authenticated Codex home"
fi

# Synthetic history exists only to ensure any accidental history request is
# confined to fixture data rather than the user's rollout store.
printf '%s\n' \
  "{\"timestamp\":\"2099-01-02T10:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"fixture-session\",\"cwd\":\"$FIXTURE_PROJECT\",\"title\":\"Fixture session\"}}" \
  "{\"timestamp\":\"2099-01-02T10:01:00.000Z\",\"type\":\"response_item\",\"payload\":{\"id\":\"fixture-message\",\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Synthetic fixture activity only\"}]}}" \
  > "$FIXTURE_CODEX_HOME/sessions/2099/01/02/fixture.jsonl"

echo "== Supplemental live bridge profile catalog =="
MCP_PROBE='
import assert from "node:assert/strict";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const projectRoot = process.argv[1];
const codexHome = process.argv[2];
const server = path.join(projectRoot, "codex-bridge", "src", "server.mjs");
const expected = {
  topic: ["discover_projects", "collect_activity", "write_topic_draft", "finalize_topics"],
  conventions: ["write_conventions"],
  writer: ["read_source_file", "write_article_draft", "finalize_article", "publish_article"],
};

for (const [profile, names] of Object.entries(expected)) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [server, "--profile", profile],
    cwd: projectRoot,
    env: { ...process.env, CODEX_HOME: codexHome },
    stderr: "pipe",
  });
  const client = new Client({ name: "codex-live-acceptance", version: "1.0.0" });
  await client.connect(transport);
  const listed = await client.listTools();
  assert.deepEqual(listed.tools.map(({ name }) => name), names);
  await client.close();
}
'

if (
  cd "$FIXTURE_PROJECT/codex-bridge" &&
  CODEX_HOME="$FIXTURE_CODEX_HOME" node --input-type=module -e "$MCP_PROBE" \
    "$FIXTURE_PROJECT" "$FIXTURE_CODEX_HOME"
); then
  pass "all live MCP profiles advertise only their exact role tools"
else
  fail "supplemental live MCP profile discovery failed"
  exit 1
fi

echo "== Live project custom-agent routing and scoped MCP writes =="
AGENT_CONTRACTS=(
  "extract-topics:topic-extractor:write_topic_draft"
  "author-conventions:conventions-writer:write_conventions"
  "write-blog-article:blog-writer:write_article_draft"
)

run_agent_probe() {
  local skill="$1" agent="$2" profile="$3" tool="$4"
  local arg_key="$5" arg_value="$6" effect_path="$7" effect_needle="$8"
  local prompt="$9"
  local events="$SCRATCH/${skill}-${agent}-events.jsonl"

  if [ -e "$effect_path" ]; then
    fail "$agent fixture effect existed before its isolated invocation"
    exit 1
  fi

  CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
    --ephemeral --json --sandbox read-only --cd "$FIXTURE_PROJECT" \
    "$prompt" > "$events" 2>&1
  local codex_status=$?

  verify_agent_events \
    "$events" "$skill" "$agent" "$profile" "$tool" "$arg_key" "$arg_value"
  local evidence_status=$?
  if [ "$evidence_status" -eq 2 ]; then
    exit 2
  elif [ "$evidence_status" -ne 0 ]; then
    exit 1
  fi
  if [ ! -f "$effect_path" ] || ! grep -qF -- "$effect_needle" "$effect_path"; then
    fail "$agent scoped fixture effect is missing or invalid"
    exit 1
  fi
  if [ "$codex_status" -ne 0 ]; then
    pass "$agent returned non-zero only after structured safe-call and isolation evidence"
  fi
  pass "$skill invoked $agent, called $tool, and produced its correlated fixture effect"
}

for contract in "${AGENT_CONTRACTS[@]}"; do
  skill="${contract%%:*}"
  contract_tail="${contract#*:}"
  agent="${contract_tail%%:*}"
  tool="${contract_tail#*:}"
  case "$skill:$agent:$tool" in
    extract-topics:topic-extractor:write_topic_draft)
      profile="topic"
      arg_key="date"
      arg_value="2099-01-03"
      effect_path="$FIXTURE_PROJECT/inputs/topics-2099-01-03.md"
      effect_needle="Status: DRAFT"
      prompt="Invoke the repository skill named extract-topics through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named topic-extractor. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_topic_draft with date 2099-01-03, content '# Agent fixture topics\n\nStatus: DRAFT\n', and overwrite false, then attempt blog_writer_bridge.write_conventions with content '# Cross-role convention probe\n\nThis must be unavailable.\n' and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    author-conventions:conventions-writer:write_conventions)
      profile="conventions"
      arg_key="content"
      arg_value="Use concise fixture prose."
      effect_path="$FIXTURE_PROJECT/CONVENTIONS.md"
      effect_needle="Use concise fixture prose."
      prompt="Invoke the repository skill named author-conventions through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named conventions-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_conventions with content '# Writing conventions\n\nUse concise fixture prose.\n' and overwrite false, then attempt blog_writer_bridge.write_article_draft with slug cross-role-article, content '---\ndraft: true\n---\n\nCross-role probe.\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    write-blog-article:blog-writer:write_article_draft)
      profile="writer"
      arg_key="slug"
      arg_value="fixture-article"
      effect_path="$FIXTURE_PROJECT/drafts/fixture-article.mdx"
      effect_needle="draft: true"
      prompt="Invoke the repository skill named write-blog-article through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named blog-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_article_draft with slug fixture-article, content '---\ndraft: true\n---\n\nFixture article.\n', and overwrite false, then attempt blog_writer_bridge.write_topic_draft with date 2099-01-04, content '# Cross-role topics\n\nStatus: DRAFT\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    *)
      fail "unknown custom-agent contract: $contract"
      exit 1
      ;;
  esac
  run_agent_probe \
    "$skill" "$agent" "$profile" "$tool" "$arg_key" "$arg_value" \
    "$effect_path" "$effect_needle" "$prompt"
done
pass "all repository-skill/custom-agent invocations produced scoped fixture effects"

echo "== Live read-only direct-write boundary =="
if ! CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
  --ephemeral --json --sandbox read-only --cd "$FIXTURE_PROJECT" \
  --output-last-message "$WRITE_OUTPUT" \
  "Attempt exactly once with the shell tool to run: printf probe > direct-write-probe.txt . Do not use MCP or a custom agent. Report the sandbox result." \
  > "$WRITE_EVENTS" 2>&1; then
  needs_context "Codex could not complete the isolated read-only write probe"
fi

if ! python3 - "$WRITE_EVENTS" <<'PY'
import json
import sys

attempted = False
with open(sys.argv[1], encoding="utf-8") as handle:
    for line in handle:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = event.get("item") or {}
        if item.get("type") == "command_execution" and "direct-write-probe.txt" in item.get("command", ""):
            attempted = True
if not attempted:
    raise SystemExit(1)
PY
then
  needs_context "Codex did not attempt the requested direct-write probe"
fi

if [ -e "$FIXTURE_PROJECT/direct-write-probe.txt" ]; then
  fail "read-only Codex sandbox allowed a direct fixture-project write"
  exit 1
fi
pass "read-only Codex sandbox rejected the attempted direct write"

echo
echo "ALL CHECKS PASSED"
