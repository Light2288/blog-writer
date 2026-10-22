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

verify_command_events() {
  python3 "$SCRIPT_DIR/codex_runtime_probe.py" --verify "$@"
}
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
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
FIXTURE_PROJECT="$SCRATCH/project"
FIXTURE_CODEX_HOME="$SCRATCH/codex-home"

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
  desktop: ["discover_projects", "collect_activity", "write_topic_draft", "finalize_topics", "write_conventions", "read_source_file", "write_article_draft", "finalize_article", "publish_article"],
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


# The desktop probe loads the trusted project's actual registration, with no
# launcher MCP overrides, and uses three skills in one parent session.
python3 "$SCRIPT_DIR/codex_runtime_probe.py" --run \
  "$FIXTURE_PROJECT" "$FIXTURE_CODEX_HOME" desktop "$SCRATCH/desktop-events.jsonl" || exit $?

# Start narrow-profile compatibility probes with the same invocation overrides
# as the launcher. Their exact catalogs must exclude all cross-role tools.
for profile in topic writer; do
  python3 "$SCRIPT_DIR/codex_runtime_probe.py" --run \
    "$FIXTURE_PROJECT" "$FIXTURE_CODEX_HOME" "$profile" "$SCRATCH/$profile-events.jsonl" || exit $?
done

echo "ALL CHECKS PASSED"
