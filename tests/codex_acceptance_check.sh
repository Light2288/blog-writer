#!/usr/bin/env bash
#
# Deterministic cross-runtime acceptance checks for Codex support.
# This script inspects repository artifacts and synthetic-test contracts only.
# It never invokes Codex, a model, or the user's real Codex history.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_file() {
  if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi
}

assert_contains() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' in $1)"
  fi
}

assert_contains_ci() {
  if [ -f "$1" ] && grep -qiF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' case-insensitively in $1)"
  fi
}

assert_absent() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    fail "$3 (unexpected '$2' in $1)"
  else
    pass "$3"
  fi
}

echo "== AC-01: OpenCode remains intact =="
for path in \
  .opencode/opencode.json \
  .opencode/agents/topic-extractor.md \
  .opencode/agents/blog-writer.md \
  .opencode/skills/extract-topics/SKILL.md \
  .opencode/skills/author-conventions/SKILL.md \
  .opencode/skills/write-blog-article/SKILL.md \
  .opencode/skills/extract-topics/scripts/redact.py; do
  assert_file "$path"
done

echo "== AC-02 through AC-04: Codex discovery and profile isolation =="
for path in \
  .agents/skills/extract-topics/SKILL.md \
  .agents/skills/author-conventions/SKILL.md \
  .agents/skills/write-blog-article/SKILL.md \
  .codex/agents/topic-extractor.toml \
  .codex/agents/conventions-writer.toml \
  .codex/agents/blog-writer.toml \
  .codex/config.toml; do
  assert_file "$path"
done
assert_contains .codex/config.toml 'sandbox_mode = "read-only"' \
  "Codex main session is read-only"
assert_absent .codex/config.toml '[mcp_servers' \
  "Codex main session has no privileged bridge registration"

if node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { PROFILE_TOOL_NAMES } from './codex-bridge/src/profiles.mjs';

assert.deepEqual(PROFILE_TOOL_NAMES.topic, [
  'discover_projects',
  'collect_activity',
  'write_topic_draft',
  'finalize_topics',
]);
assert.deepEqual(PROFILE_TOOL_NAMES.conventions, ['write_conventions']);
assert.deepEqual(PROFILE_TOOL_NAMES.writer, [
  'read_source_file',
  'write_article_draft',
  'finalize_article',
  'publish_article',
]);
NODE
then
  pass "bridge profiles expose only their exact role tool lists"
else
  fail "bridge profile tool lists are not exactly role-isolated"
fi

echo "== AC-05 through AC-08 and AC-15: fixture-only activity ingestion =="
for path in \
  codex-bridge/test/fixtures/rollouts/supported.jsonl \
  codex-bridge/test/fixtures/rollouts/duplicate.jsonl \
  codex-bridge/test/fixtures/rollouts/malformed.jsonl \
  codex-bridge/test/fixtures/rollouts/unsupported.jsonl \
  codex-bridge/test/history.test.mjs \
  codex-bridge/test/git.test.mjs \
  codex-bridge/test/activity.test.mjs; do
  assert_file "$path"
done
assert_contains codex-bridge/test/history.test.mjs 'mkdtemp' \
  "history tests create isolated temporary Codex homes"
assert_contains codex-bridge/test/history.test.mjs 'process.env.CODEX_HOME = home.root' \
  "history tests override CODEX_HOME with a fixture home"
assert_contains codex-bridge/test/history.test.mjs 'fails_closed_for_missing_or_zero_supported_history' \
  "history tests cover wholly unsupported history"
assert_contains codex-bridge/test/history.test.mjs 'malformed' \
  "history tests cover malformed rollout records"
assert_contains codex-bridge/test/activity.test.mjs 'async function codexHome(t)' \
  "activity tests use a fixture Codex home"
assert_contains codex-bridge/test/git.test.mjs 'without_mutation' \
  "Git collection tests assert read-only behavior"

if ! grep -rEi '(\.codex/[^[:space:]]*(sqlite|\.db)|codex[^[:space:]]*\.(sqlite|db))' \
  .agents/skills >/dev/null 2>&1; then
  pass "Codex skills contain no internal Codex SQLite/database path"
else
  fail "Codex skills reference an internal Codex SQLite/database path"
fi

echo "== AC-09 through AC-14: shared formats and scoped operations =="
assert_contains .opencode/skills/extract-topics/SKILL.md 'inputs/topics-YYYY-MM-DD.md' \
  "OpenCode topic skill uses the run-date filename"
assert_contains .agents/skills/extract-topics/SKILL.md 'inputs/topics-YYYY-MM-DD.md' \
  "Codex topic skill uses the run-date filename"
for skill in .opencode/skills/extract-topics/SKILL.md .agents/skills/extract-topics/SKILL.md; do
  assert_contains "$skill" 'Status: DRAFT' "$skill preserves DRAFT topics"
  assert_contains "$skill" 'FINAL' "$skill preserves FINAL transition"
done
for skill in .opencode/skills/write-blog-article/SKILL.md .agents/skills/write-blog-article/SKILL.md; do
  assert_contains "$skill" 'draft: true' "$skill preserves DRAFT articles"
  assert_contains "$skill" 'draft: false' "$skill preserves article finalization"
  assert_contains "$skill" '<Lang value="en"' "$skill preserves English MDX"
  assert_contains "$skill" '<Lang value="it"' "$skill preserves Italian MDX"
  assert_contains "$skill" 'topic_key' "$skill preserves topic keys"
done
for path in \
  codex-bridge/test/topics.test.mjs \
  codex-bridge/test/conventions.test.mjs \
  codex-bridge/test/source-files.test.mjs \
  codex-bridge/test/articles.test.mjs; do
  assert_file "$path"
  assert_contains "$path" 'symlink' "$path covers symlink boundaries"
done
assert_contains codex-bridge/test/articles.test.mjs 'restores_draft_ledger_and_no_published_duplicate' \
  "article tests cover recoverable publication"
assert_contains codex-bridge/test/articles.test.mjs 'idempotent' \
  "article tests cover idempotent publication ledger updates"

echo "== Dependency contract =="
if python3 - codex-bridge/package-lock.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    lock = json.load(handle)

root = lock["packages"][""]["dependencies"]["@modelcontextprotocol/sdk"]
package = lock["packages"]["node_modules/@modelcontextprotocol/sdk"]["version"]
if root != "1.30.1" or package != "1.30.1":
    raise SystemExit(1)
PY
then
  pass "package lock pins @modelcontextprotocol/sdk 1.30.1 exactly"
else
  fail "package lock does not pin @modelcontextprotocol/sdk 1.30.1 exactly"
fi

echo "== AC-16 and AC-17: deterministic default and opt-in live verification =="
assert_contains tests/run_all.sh 'tests/codex_scaffold_check.sh' \
  "default suite includes Codex scaffold checks"
assert_contains tests/run_all.sh 'npm test --prefix codex-bridge' \
  "default suite includes bridge tests"
assert_contains tests/run_all.sh 'tests/codex_acceptance_check.sh' \
  "default suite includes Codex acceptance checks"
assert_absent tests/run_all.sh 'tests/codex_live_check.sh' \
  "default suite excludes live Codex checks"
assert_file tests/codex_live_check.sh
assert_contains tests/codex_live_check.sh 'CODEX_ACCEPTANCE_RUNTIME' \
  "live Codex checks are explicitly gated"
assert_contains tests/codex_live_check.sh 'mktemp -d' \
  "live Codex checks create an isolated fixture project"
assert_contains tests/codex_live_check.sh 'CODEX_HOME' \
  "live Codex checks isolate Codex history"

echo "== AC-18: dual-runtime setup and privacy documentation =="
for doc in README.md docs/acceptance.md; do
  assert_contains "$doc" 'OpenCode' "$doc names OpenCode"
  assert_contains "$doc" 'Codex' "$doc names Codex"
  assert_contains "$doc" 'npm install --prefix codex-bridge' \
    "$doc documents bridge installation"
  assert_contains_ci "$doc" 'trust' "$doc documents Codex project trust"
  assert_contains_ci "$doc" 'restart' "$doc documents runtime restart"
  assert_contains "$doc" '~/.codex/sessions' \
    "$doc describes the local rollout adapter path"
  assert_contains "$doc" 'bash tests/run_all.sh' \
    "$doc documents deterministic verification"
  assert_contains "$doc" 'CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh' \
    "$doc documents opt-in live Codex verification"
  assert_contains_ci "$doc" 'ChatGPT web history' \
    "$doc states that ChatGPT web history is out of scope"
  assert_contains_ci "$doc" 'general shell tool' \
    "$doc documents the bridge capability boundary"
done

echo "== AC-19: corrected shared contracts =="
assert_contains .opencode/agents/topic-extractor.md 'inputs/topics-YYYY-MM-DD.md' \
  "active OpenCode topic agent uses the run-date filename"
assert_absent .opencode/agents/topic-extractor.md 'inputs/topics-YYYY-Www.md' \
  "active OpenCode topic agent has no ISO-week filename contradiction"
assert_contains AGENTS.md 'placeholder-only' \
  "project guidance rejects placeholder-only conventions"
assert_contains AGENTS.md 'not indexed' \
  "project guidance states time_updated is not indexed"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
