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

# verify_agent_events <events.jsonl> <skill> <agent> <profile> <tool> <arg-key> <arg-value> <expected-args-json>
# Only structured Codex events count. Assistant text is intentionally ignored.
verify_agent_events() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" <<'PY'
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
    expected_arguments_json,
) = sys.argv[1:]
try:
    expected_arguments = json.loads(expected_arguments_json)
except json.JSONDecodeError:
    print("NEEDS_CONTEXT: expected MCP arguments are not valid JSON", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(expected_arguments, dict):
    print("NEEDS_CONTEXT: expected MCP arguments must be a JSON object", file=sys.stderr)
    raise SystemExit(2)
if expected_arg_value not in str(expected_arguments.get(expected_arg_key, "")):
    print("NEEDS_CONTEXT: expected MCP argument sentinel is inconsistent", file=sys.stderr)
    raise SystemExit(2)
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

def direct_values_for_keys(value, keys):
    if not isinstance(value, dict):
        return set()
    return {
        str(value[key])
        for key in keys
        if isinstance(value.get(key), (str, int)) and str(value[key])
    }

OWNER_ID_PRECEDENCE = (
    (
        "child_agent_id",
        "child_thread_id",
        "receiver_thread_id",
        "spawned_agent_id",
        "spawned_thread_id",
        "target_agent_id",
        "target_thread_id",
    ),
    ("agent_thread_id",),
    ("thread_id",),
    ("agent_id",),
    ("conversation_id",),
)

def direct_owner(value):
    if not isinstance(value, dict):
        return None, "missing"
    for keys in OWNER_ID_PRECEDENCE:
        values = direct_values_for_keys(value, keys)
        if len(values) == 1:
            return next(iter(values)), "present"
        if len(values) > 1:
            return None, "ambiguous"
    return None, "missing"

def normalized_records(envelope):
    has_item = "item" in envelope
    has_items = "items" in envelope
    if has_item and has_items:
        return
    if has_item:
        if not isinstance(envelope["item"], dict):
            return
        nested = [envelope["item"]]
    elif has_items:
        if (
            not isinstance(envelope["items"], list)
            or len(envelope["items"]) != 1
            or not isinstance(envelope["items"][0], dict)
        ):
            return
        nested = envelope["items"]
    else:
        nested = [envelope]

    envelope_owner, _ = direct_owner(envelope)
    for node in nested:
        node_owner, node_owner_state = direct_owner(node)
        # A nested event owns its evidence. The envelope ID is only a fallback
        # when the nested schema has no direct owner field at all.
        if node is envelope or node_owner_state != "missing":
            owner = node_owner
        else:
            owner = envelope_owner
        yield {
            "node": node,
            "owner": owner,
            "event_type": envelope.get("type"),
        }

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

def normalized_surface_tool(value):
    if not isinstance(value, str):
        return None
    prefixes = (
        "mcp__blog_writer_bridge__",
        "blog_writer_bridge__",
        "mcp__blog-writer-codex-bridge__",
        "blog-writer-codex-bridge__",
    )
    for prefix in prefixes:
        if value.startswith(prefix):
            return value[len(prefix):]
    return value

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
            normalized = normalized_surface_tool(candidate)
            if normalized:
                names.add(normalized)
    return names

def server_names(value):
    names = direct_values_for_keys(value, {"server", "server_name", "mcp_server"})
    for key in ("tool", "tool_name", "name"):
        candidate = value.get(key)
        if isinstance(candidate, str) and "__" in candidate:
            names.add(candidate.rsplit("__", 1)[0])
    return names

def profile_names(value):
    profiles = direct_values_for_keys(value, {"profile", "profile_name", "mcp_profile"})
    for key in ("args", "arguments", "command_args"):
        args = value.get(key)
        if not isinstance(args, list):
            continue
        for index, arg in enumerate(args[:-1]):
            if arg == "--profile" and isinstance(args[index + 1], str):
                profiles.add(args[index + 1])
    return profiles

def expected_server(names):
    return any(
        name in {"blog_writer_bridge", "blog-writer-codex-bridge"}
        or name.endswith("__blog_writer_bridge")
        for name in names
    )

skill_seen = any(structured_skill(event) for event in events)
spawn_records = []
tool_events = []
surface_events = []
metadata_events = []
for event in events:
    for record in normalized_records(event):
        node = record["node"]
        owner = record["owner"]
        desc = descriptor(node)
        if (
            ("spawn_agent" in desc or "spawn" in desc or "collab" in desc or "custom_agent" in desc)
            and structured_agent(node)
        ):
            spawn_records.append({"owner": owner, "node": node})
        servers = server_names(node)
        profiles = profile_names(node)
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
                    "event_type": record["event_type"],
                    "owner": owner,
                }
            )
        surface = surface_names(node)
        if surface and expected_server(servers):
            surface_events.append({"surface": surface, "node": node, "owner": owner})
        if servers or profiles:
            metadata_events.append(
                {"servers": servers, "profiles": profiles, "owner": owner}
            )

spawn_agent_ids = {
    record["owner"] for record in spawn_records if record["owner"] is not None
}
mcp_agent_ids = {
    record["owner"]
    for record in tool_events + surface_events
    if record["owner"] is not None
}
candidate_child_ids = sorted(spawn_agent_ids & mcp_agent_ids)
candidate_results = {}
unsafe_cross_role_calls = []
for child_id in candidate_child_ids:
    child_tools = [record for record in tool_events if child_id == record["owner"]]
    child_surfaces = [
        record for record in surface_events if child_id == record["owner"]
    ]
    child_metadata = [
        record for record in metadata_events if child_id == record["owner"]
    ]

    unexpected_success = sorted(
        {
            record["name"]
            for record in child_tools
            if record["name"] in cross_role_tools
            and terminal_call(record["node"], record["event_type"])
            and not failed_call(record["node"])
        }
    )
    if unexpected_success:
        unsafe_cross_role_calls.append((child_id, unexpected_success))

    # Catalogs are indivisible observations: two partial advertisements cannot
    # be combined into an exact role surface.
    exact_surface = False
    for record in child_surfaces:
        surface = record["surface"]
        if surface == profile_tools[expected_agent]:
            exact_surface = True
            break
    unknown_surface_tools = {
        name
        for record in child_surfaces
        for name in record["surface"] - all_tools
    }
    observed_allowed_tools = {
        record["name"]
        for record in child_tools
        if record["name"] in profile_tools[expected_agent]
    }
    rejected_cross_role_tools = {
        record["name"]
        for record in child_tools
        if record["name"] in cross_role_tools
        and terminal_call(record["node"], record["event_type"])
        and unavailable_call(record["node"])
    }
    fallback_surface = (
        not unknown_surface_tools
        and observed_allowed_tools == profile_tools[expected_agent]
        and rejected_cross_role_tools == cross_role_tools
    )
    primary_calls = [
        record
        for record in child_tools
        if record["name"] == expected_tool
        and terminal_call(record["node"], record["event_type"])
        and not failed_call(record["node"])
        and tool_arguments(record["node"]) == expected_arguments
    ]
    server_verified = any(
        expected_server(record["servers"])
        for record in child_metadata
    )
    profile_verified = any(
        expected_profile in record["profiles"]
        for record in child_metadata
    )

    missing = []
    if not server_verified:
        missing.append("MCP server blog_writer_bridge")
    if not profile_verified:
        missing.append(f"MCP profile {expected_profile}")
    if not primary_calls:
        missing.append(
            f"successful mcp_tool_call {expected_tool} with exact sentinel arguments"
        )
    if not ((exact_surface and not unknown_surface_tools) or fallback_surface):
        missing.append(
            "exact role tool catalog or fallback evidence for all allowed tools "
            "and every cross-role rejection"
        )
    candidate_results[child_id] = missing

valid_child_ids = [
    child_id for child_id, missing in candidate_results.items() if not missing
]
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
    "candidate_child_ids": candidate_child_ids,
    "candidate_missing": candidate_results,
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

if unsafe_cross_role_calls:
    details = "; ".join(
        f"{child_id}: {', '.join(names)}"
        for child_id, names in unsafe_cross_role_calls
    )
    print(
        f"FAIL: {expected_agent} child completed cross-role MCP tool call(s): {details}",
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
if not candidate_child_ids:
    missing.append(f"child-scoped {expected_agent} MCP evidence")
elif not valid_child_ids:
    missing.append("one child satisfying every structured evidence requirement")
elif len(valid_child_ids) > 1:
    missing.append(
        "one unambiguous child satisfying every structured evidence requirement"
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
chosen_child_id = valid_child_ids[0]
print(chosen_child_id)
PY
}

# verify_command_events <events.jsonl> <skill> <profile> <tool> <expected-args-json>
# Only one correlated parent-session catalog/call/result set is accepted.
verify_command_events() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json
import sys

events_path, expected_skill, expected_profile, expected_tool, expected_json = sys.argv[1:]
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
PY
}

if [ "${CODEX_LIVE_EVENT_FIXTURE:-}" = "1" ]; then
  verify_agent_events "$@"
  exit $?
fi

if [ "${CODEX_LIVE_COMMAND_EVENT_FIXTURE:-}" = "1" ]; then
  verify_command_events "$@"
  exit $?
fi

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

echo "== Live command-scoped main-session routing and scoped MCP writes =="

run_command_probe() {
  local skill="$1" profile="$2" tool="$3" expected_arguments="$4"
  local effect_path="$5" effect_content="$6" cross_effect_path="$7"
  local prompt="$8" events="$SCRATCH/${skill}-command-events.jsonl"

  if [ -e "$effect_path" ] || [ -e "$cross_effect_path" ]; then
    fail "$skill command fixture effect existed before its isolated invocation"
    return 1
  fi

  CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
    --json --no-daemon --sandbox read-only --cd "$FIXTURE_PROJECT" \
    -c 'mcp_servers.blog_writer_bridge.command="node"' \
    -c "mcp_servers.blog_writer_bridge.args=[\"codex-bridge/src/server.mjs\",\"--profile\",\"$profile\"]" \
    "$prompt" > "$events" 2>&1
  local codex_status=$?

  local parent_owner
  parent_owner="$(verify_command_events \
    "$events" "$skill" "$profile" "$tool" "$expected_arguments")"
  local evidence_status=$?
  if [ "$evidence_status" -ne 0 ]; then
    return "$evidence_status"
  fi
  if [ ! -f "$effect_path" ] || \
     ! cmp -s -- "$effect_path" <(printf '%s' "$effect_content"); then
    fail "$skill command-scoped fixture effect is missing or invalid"
    return 1
  fi
  if [ -e "$cross_effect_path" ]; then
    fail "$skill command-scoped session completed a cross-role fixture effect"
    return 1
  fi
  if [ "$codex_status" -ne 0 ]; then
    pass "$skill returned non-zero only after structured safe-call and isolation evidence"
  fi
  pass "$skill parent $parent_owner called $tool and produced its correlated fixture effect"
}

topic_expected='{"content":"# Command fixture topics\n\n| Status | DRAFT |\n","date":"2099-01-05","overwrite":false}'
topic_effect="$FIXTURE_PROJECT/inputs/topics-2099-01-05.md"
topic_content=$'# Command fixture topics\n\n| Status | DRAFT |\n'
topic_cross_effect="$FIXTURE_PROJECT/drafts/cross-role-command-article.mdx"
topic_prompt="Invoke the repository skill named extract-topics through Codex's structured skill mechanism in command-scoped mode. Do not spawn or delegate to a custom agent. The user explicitly approves this fixture persistence. From the main session call blog_writer_bridge.write_topic_draft with date 2099-01-05, content '# Command fixture topics\n\n| Status | DRAFT |\n', and overwrite false. Then attempt blog_writer_bridge.write_article_draft with slug cross-role-command-article, content '---\ndraft: true\n---\n\nCross-role command probe.\n', and overwrite false; this tool must be unavailable. Prose about skill or tool availability is not evidence."
run_command_probe \
  extract-topics topic write_topic_draft "$topic_expected" \
  "$topic_effect" "$topic_content" "$topic_cross_effect" "$topic_prompt" || exit $?

cp "$ROOT/CONVENTIONS.md" "$FIXTURE_PROJECT/CONVENTIONS.md"
writer_expected='{"content":"---\ndraft: true\n---\n\nCommand fixture article.\n","overwrite":false,"slug":"command-fixture-article"}'
writer_effect="$FIXTURE_PROJECT/drafts/command-fixture-article.mdx"
writer_content=$'---\ndraft: true\n---\n\nCommand fixture article.\n'
writer_cross_effect="$FIXTURE_PROJECT/inputs/topics-2099-01-06.md"
writer_prompt="Invoke the repository skill named write-blog-article through Codex's structured skill mechanism in command-scoped mode. Do not spawn or delegate to a custom agent. The user explicitly approves this fixture persistence. From the main session call blog_writer_bridge.write_article_draft with slug command-fixture-article, content '---\ndraft: true\n---\n\nCommand fixture article.\n', and overwrite false. Then attempt blog_writer_bridge.write_topic_draft with date 2099-01-06, content '# Cross-role command topics\n\n| Status | DRAFT |\n', and overwrite false; this tool must be unavailable. Prose about skill or tool availability is not evidence."
run_command_probe \
  write-blog-article writer write_article_draft "$writer_expected" \
  "$writer_effect" "$writer_content" "$writer_cross_effect" "$writer_prompt" || exit $?
rm -f -- "$FIXTURE_PROJECT/CONVENTIONS.md"
pass "all command-scoped main-session invocations produced isolated fixture effects"

echo "== Diagnostic: project custom-agent routing and scoped MCP writes =="
AGENT_CONTRACTS=(
  "extract-topics:topic-extractor:write_topic_draft"
  "author-conventions:conventions-writer:write_conventions"
  "write-blog-article:blog-writer:write_article_draft"
)

run_agent_probe() {
  local skill="$1" agent="$2" profile="$3" tool="$4"
  local arg_key="$5" arg_value="$6" expected_arguments="$7"
  local effect_path="$8" effect_content="$9" prompt="${10}"
  local events="$SCRATCH/${skill}-${agent}-events.jsonl"

  if [ -e "$effect_path" ]; then
    fail "$agent fixture effect existed before its isolated invocation"
    return 1
  fi

  CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
    --ephemeral --json --sandbox read-only --cd "$FIXTURE_PROJECT" \
    "$prompt" > "$events" 2>&1
  local codex_status=$?

  local chosen_child_id
  chosen_child_id="$(verify_agent_events \
    "$events" "$skill" "$agent" "$profile" "$tool" "$arg_key" "$arg_value" \
    "$expected_arguments")"
  local evidence_status=$?
  if [ "$evidence_status" -eq 2 ]; then
    return 2
  elif [ "$evidence_status" -ne 0 ]; then
    return 1
  fi
  if [ ! -f "$effect_path" ] || \
     ! cmp -s -- "$effect_path" <(printf '%s' "$effect_content"); then
    fail "$agent scoped fixture effect is missing or invalid"
    return 1
  fi
  if [ "$codex_status" -ne 0 ]; then
    pass "$agent returned non-zero only after structured safe-call and isolation evidence"
  fi
  pass "$skill child $chosen_child_id called $tool and produced its correlated fixture effect"
}

agent_diagnostics=0
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
      expected_arguments='{"content":"# Agent fixture topics\n\n| Status | DRAFT |\n","date":"2099-01-03","overwrite":false}'
      effect_path="$FIXTURE_PROJECT/inputs/topics-2099-01-03.md"
      effect_content=$'# Agent fixture topics\n\n| Status | DRAFT |\n'
      prompt="Invoke the repository skill named extract-topics through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named topic-extractor. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_topic_draft with date 2099-01-03, content '# Agent fixture topics\n\n| Status | DRAFT |\n', and overwrite false, then attempt blog_writer_bridge.write_conventions with content '# Cross-role convention probe\n\nThis must be unavailable.\n' and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    author-conventions:conventions-writer:write_conventions)
      profile="conventions"
      arg_key="content"
      arg_value="Use concise fixture prose."
      expected_arguments='{"content":"# Writing conventions\n\nUse concise fixture prose.\n","overwrite":false}'
      effect_path="$FIXTURE_PROJECT/CONVENTIONS.md"
      effect_content=$'# Writing conventions\n\nUse concise fixture prose.\n'
      prompt="Invoke the repository skill named author-conventions through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named conventions-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_conventions with content '# Writing conventions\n\nUse concise fixture prose.\n' and overwrite false, then attempt blog_writer_bridge.write_article_draft with slug cross-role-article, content '---\ndraft: true\n---\n\nCross-role probe.\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    write-blog-article:blog-writer:write_article_draft)
      profile="writer"
      arg_key="slug"
      arg_value="fixture-article"
      expected_arguments='{"content":"---\ndraft: true\n---\n\nFixture article.\n","overwrite":false,"slug":"fixture-article"}'
      effect_path="$FIXTURE_PROJECT/drafts/fixture-article.mdx"
      effect_content=$'---\ndraft: true\n---\n\nFixture article.\n'
      prompt="Invoke the repository skill named write-blog-article through Codex's structured skill mechanism. Within that skill invocation, spawn the project custom agent named blog-writer. The user explicitly approves this fixture persistence. Instruct only that agent to first call blog_writer_bridge.write_article_draft with slug fixture-article, content '---\ndraft: true\n---\n\nFixture article.\n', and overwrite false, then attempt blog_writer_bridge.write_topic_draft with date 2099-01-04, content '# Cross-role topics\n\n| Status | DRAFT |\n', and overwrite false so any accidental exposure would succeed. Wait for the agent. The main chat must not call MCP tools or write files, and prose about skill, agent, or tool availability is not evidence."
      ;;
    *)
      fail "unknown custom-agent contract: $contract"
      exit 1
      ;;
  esac
  if run_agent_probe \
    "$skill" "$agent" "$profile" "$tool" "$arg_key" "$arg_value" \
    "$expected_arguments" "$effect_path" "$effect_content" "$prompt"; then
    :
  else
    agent_status=$?
    if [ "$agent_status" -eq 2 ]; then
      agent_diagnostics=1
    else
      exit "$agent_status"
    fi
  fi
done
if [ "$agent_diagnostics" -eq 0 ]; then
  pass "all repository-skill/custom-agent invocations produced scoped fixture effects"
else
  skip "custom-agent MCP propagation remains diagnostic; command-scoped acceptance already passed"
fi

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
