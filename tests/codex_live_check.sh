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
DISCOVERY_OUTPUT="$SCRATCH/discovery.txt"
DISCOVERY_EVENTS="$SCRATCH/discovery.jsonl"
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

echo "== Live bridge profiles and scoped fixture write =="
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
  if (profile === "topic") {
    const result = await client.callTool({
      name: "write_topic_draft",
      arguments: {
        date: "2099-01-02",
        content: "# Fixture topics\\n\\nStatus: DRAFT\\n",
        overwrite: false,
      },
    });
    assert.ok(!result.isError, "fixture topic write failed");
  }
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
  fail "live MCP profile discovery or scoped fixture write failed"
  exit 1
fi

if [ -f "$FIXTURE_PROJECT/inputs/topics-2099-01-02.md" ] && \
   grep -qF 'Status: DRAFT' "$FIXTURE_PROJECT/inputs/topics-2099-01-02.md"; then
  pass "scoped MCP write created only the fixture topic draft"
else
  fail "scoped MCP fixture topic draft is missing or invalid"
  exit 1
fi

echo "== Live project skill and custom-agent visibility =="
if ! CODEX_HOME="$FIXTURE_CODEX_HOME" codex exec \
  --ephemeral --json --sandbox read-only --cd "$FIXTURE_PROJECT" \
  --output-last-message "$DISCOVERY_OUTPUT" \
  "Without running commands or changing files, report the exact names of the three repository skills and three project custom agents visible in this trusted fixture project." \
  > "$DISCOVERY_EVENTS" 2>&1; then
  needs_context "Codex could not complete the isolated discovery probe"
fi

for name in extract-topics author-conventions write-blog-article \
            topic-extractor conventions-writer blog-writer; do
  if ! grep -qF -- "$name" "$DISCOVERY_OUTPUT"; then
    fail "Codex discovery output did not expose $name"
    exit 1
  fi
done
pass "Codex discovers all repository skills and project custom agents"

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
