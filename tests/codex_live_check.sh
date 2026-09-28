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

# verify_agent_events <events.jsonl> <agent-name> <expected-tool> <cross-role-tool>
# Only structured Codex events count. Assistant text is intentionally ignored.
verify_agent_events() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json
import sys

events_path, expected_agent, expected_tool, cross_role_tool = sys.argv[1:]
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

def structured_agent(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"agent_type", "agent_name", "target_agent", "custom_agent"} and child == expected_agent:
                return True
            if key in {"arguments", "args", "input"} and isinstance(child, str):
                try:
                    parsed = json.loads(child)
                except json.JSONDecodeError:
                    parsed = None
                if parsed is not None and structured_agent(parsed):
                    return True
            if structured_agent(child):
                return True
    elif isinstance(value, list):
        return any(structured_agent(child) for child in value)
    return False

def descriptor(node):
    return " ".join(
        str(node.get(key, "")).lower()
        for key in ("type", "kind", "method", "tool", "tool_name", "name")
    )

def tool_name(node):
    for key in ("tool", "tool_name", "name"):
        value = node.get(key)
        if not isinstance(value, str):
            continue
        for known in all_tools:
            if value == known or value.endswith(f"__{known}"):
                return known
    return None

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
            if not isinstance(candidate, str):
                continue
            for known in all_tools:
                if candidate == known or candidate.endswith(f"__{known}"):
                    names.add(known)
    return names

spawn_seen = False
observed_tools = []
tool_events = []
observed_surfaces = []
for event in events:
    for node in objects(event):
        desc = descriptor(node)
        if (
            ("spawn_agent" in desc or "spawn" in desc or "collab" in desc or "custom_agent" in desc)
            and structured_agent(node)
        ):
            spawn_seen = True
        name = tool_name(node)
        if name and (
            "mcp_tool_call" in desc
            or "mcp" in desc
            or any(key in node for key in ("server", "server_name", "mcp_server"))
        ):
            observed_tools.append(name)
            tool_events.append((name, node, event.get("type")))
        surface = surface_names(node)
        if surface:
            observed_surfaces.append(surface)

unexpected_success = sorted(
    {
        name
        for name, node, event_type in tool_events
        if name not in profile_tools[expected_agent]
        and terminal_call(node, event_type)
        and not failed_call(node)
    }
)
surface_verified = any(
    expected_tool in surface and not (surface - profile_tools[expected_agent])
    for surface in observed_surfaces
)
rejected_cross_role = any(
    name == cross_role_tool
    and terminal_call(node, event_type)
    and failed_call(node)
    for name, node, event_type in tool_events
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
    "structured_mcp_tools": sorted(set(observed_tools)),
    "structured_tool_surfaces": [sorted(surface) for surface in observed_surfaces],
}

if unexpected_success:
    print(
        f"FAIL: {expected_agent} completed cross-role MCP tool call(s): {', '.join(unexpected_success)}",
        file=sys.stderr,
    )
    raise SystemExit(1)
if not spawn_seen or expected_tool not in observed_tools or not (surface_verified or rejected_cross_role):
    missing = []
    if not spawn_seen:
        missing.append(f"spawn identity {expected_agent}")
    if expected_tool not in observed_tools:
        missing.append(f"mcp_tool_call {expected_tool}")
    if not (surface_verified or rejected_cross_role):
        missing.append(
            f"tool surface excluding cross-role tool {cross_role_tool} "
            f"or structured rejection of {cross_role_tool}"
        )
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
  "topic-extractor:write_topic_draft:write_conventions"
  "conventions-writer:write_conventions:write_article_draft"
  "blog-writer:write_article_draft:write_topic_draft"
)

run_agent_probe() {
  local agent="$1" tool="$2" cross_role_tool="$3" prompt="$4"
  local events="$SCRATCH/${agent}-events.jsonl"

  CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
    --ephemeral --json --sandbox read-only --cd "$FIXTURE_PROJECT" \
    "$prompt" > "$events" 2>&1
  local codex_status=$?

  verify_agent_events "$events" "$agent" "$tool" "$cross_role_tool"
  local evidence_status=$?
  if [ "$evidence_status" -eq 2 ]; then
    exit 2
  elif [ "$evidence_status" -ne 0 ]; then
    exit 1
  fi
  if [ "$codex_status" -ne 0 ]; then
    pass "$agent returned non-zero only after structured safe-call and isolation evidence"
  fi
  pass "$agent was spawned, called $tool, and proved cross-role isolation in structured events"
}

for contract in "${AGENT_CONTRACTS[@]}"; do
  agent="${contract%%:*}"
  contract_tail="${contract#*:}"
  tool="${contract_tail%%:*}"
  cross_role_tool="${contract_tail#*:}"
  case "$agent:$tool" in
    topic-extractor:write_topic_draft)
      prompt="Spawn the project custom agent named topic-extractor. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_topic_draft with date 2099-01-03, content '# Agent fixture topics\n\nStatus: DRAFT\n', and overwrite false, then attempt blog_writer_bridge.$cross_role_tool with content '# Cross-role convention probe\n\nThis must be unavailable.\n' and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about availability is not evidence."
      ;;
    conventions-writer:write_conventions)
      prompt="Spawn the project custom agent named conventions-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_conventions with content '# Writing conventions\n\nUse concise fixture prose.\n' and overwrite false, then attempt blog_writer_bridge.$cross_role_tool with slug cross-role-article, content '---\ndraft: true\n---\n\nCross-role probe.\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about availability is not evidence."
      ;;
    blog-writer:write_article_draft)
      prompt="Spawn the project custom agent named blog-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_article_draft with slug fixture-article, content '---\ndraft: true\n---\n\nFixture article.\n', and overwrite false, then attempt blog_writer_bridge.$cross_role_tool with date 2099-01-04, content '# Cross-role topics\n\nStatus: DRAFT\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about availability is not evidence."
      ;;
    *)
      fail "unknown custom-agent contract: $contract"
      exit 1
      ;;
  esac
  run_agent_probe "$agent" "$tool" "$cross_role_tool" "$prompt"
done

if [ ! -f "$FIXTURE_PROJECT/inputs/topics-2099-01-03.md" ] || \
   ! grep -qF 'Status: DRAFT' "$FIXTURE_PROJECT/inputs/topics-2099-01-03.md"; then
  fail "topic-extractor scoped fixture write is missing or invalid"
  exit 1
fi
if [ ! -f "$FIXTURE_PROJECT/CONVENTIONS.md" ] || \
   ! grep -qF 'Use concise fixture prose.' "$FIXTURE_PROJECT/CONVENTIONS.md"; then
  fail "conventions-writer scoped fixture write is missing or invalid"
  exit 1
fi
if [ ! -f "$FIXTURE_PROJECT/drafts/fixture-article.mdx" ] || \
   ! grep -qF 'draft: true' "$FIXTURE_PROJECT/drafts/fixture-article.mdx"; then
  fail "blog-writer scoped fixture write is missing or invalid"
  exit 1
fi
pass "all custom-agent MCP writes produced their scoped fixture effects"

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
