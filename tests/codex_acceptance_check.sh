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

# scan_forbidden_ingestion <path>...
# Reject implementation-shaped local SQLite and ChatGPT-history ingestion while
# allowing negative/out-of-scope prose in skills and agent instructions.
scan_forbidden_ingestion() {
  python3 - "$@" <<'PY'
from pathlib import Path
import re
import sys

PATTERNS = (
    (
        "SQLite module or CLI",
        re.compile(
            r"(?:\b(?:from|import)\s*\(?\s*['\"](?:node:sqlite|better-sqlite3|sqlite3)['\"]|"
            r"\brequire\s*\(\s*['\"](?:node:sqlite|better-sqlite3|sqlite3)['\"]\s*\)|"
            r"['\"]sqlite3['\"]|"
            r"(?<![-\w])sqlite3\s+(?:-|['\"$~/]))",
            re.I,
        ),
    ),
    (
        "internal Codex SQLite path",
        re.compile(
            r"(?:~|\$HOME|/)[^\s'\"`]*\.codex[^\s'\"`]*"
            r"\.(?:db|sqlite|sqlite3)\b",
            re.I,
        ),
    ),
    (
        "SQLite filename literal",
        re.compile(r"['\"][^'\"]*\.(?:db|sqlite|sqlite3)['\"]", re.I),
    ),
    (
        "ChatGPT history endpoint",
        re.compile(r"https?://(?:chat\.openai\.com|chatgpt\.com)/(?:backend-api|api)/", re.I),
    ),
    (
        "ChatGPT history connector symbol",
        re.compile(
            r"\bchatgpt[_-](?:web[_-])?(?:history|conversations?)"
            r"[_-](?:client|connector|reader|ingest(?:er|ion)?|fetch(?:er)?|import(?:er)?)\b|"
            r"\b(?:fetch|read|load|import|get)ChatGPT(?:Web)?(?:History|Conversations?)\b",
            re.I,
        ),
    ),
    (
        "ChatGPT local-history path",
        re.compile(r"(?:~|\$HOME|/)[^\s'\"`]*\.chatgpt(?:/|\b)", re.I),
    ),
)

SQLITE_PROHIBITION = re.compile(
    r"^\s*(?:[-*]\s+)?(?:do not|don't|never)\s+"
    r"(?:use|run|invoke|execute)\s+"
    r"[^=;{}()]*?(?:['\"`]sqlite3['\"`]|\bsqlite3\b)"
    r"[^=;{}()]*[.!]?\s*$",
    re.I,
)

def allowed_sqlite_prohibition(line):
    return (
        SQLITE_PROHIBITION.fullmatch(line) is not None
        and "//" not in line
        and "&&" not in line
        and "||" not in line
    )

violations = []
for raw_root in sys.argv[1:]:
    root = Path(raw_root)
    files = [root] if root.is_file() else sorted(path for path in root.rglob("*") if path.is_file())
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(lines, 1):
            for label, pattern in PATTERNS:
                if pattern.search(line):
                    if label == "SQLite module or CLI" and allowed_sqlite_prohibition(line):
                        continue
                    violations.append(f"{path}:{number}: {label}")

if violations:
    print("\n".join(violations))
    raise SystemExit(1)
PY
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
  .codex/config.toml; do
  assert_file "$path"
done
assert_contains .codex/config.toml 'sandbox_mode = "read-only"' \
  "Codex main session is read-only"
assert_contains .codex/config.toml '[mcp_servers.blog_writer_bridge]' \
  "Codex main session registers the bounded desktop bridge"

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

if scan_forbidden_ingestion .agents/skills .codex codex-bridge/src; then
  pass "Codex surfaces contain no forbidden SQLite or ChatGPT-history ingestion"
else
  fail "Codex surfaces contain forbidden SQLite or ChatGPT-history ingestion"
fi

INGESTION_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/codex-ingestion-guard.XXXXXX")"
printf '%s\n' \
  'Do not use the "sqlite3" executable to read internal Codex history.' \
  'ChatGPT web history is unsupported.' \
  > "$INGESTION_FIXTURE/allowed.md"
if scan_forbidden_ingestion "$INGESTION_FIXTURE/allowed.md"; then
  pass "forbidden-ingestion guard permits negative/out-of-scope documentation"
else
  fail "forbidden-ingestion guard rejects negative/out-of-scope documentation"
fi
printf '%s\n' \
  "import Database from 'better-sqlite3'; // never log database contents" \
  'const source = "https://chatgpt.com/backend-api/conversations"; // works without browser state' \
  > "$INGESTION_FIXTURE/forbidden.mjs"
if scan_forbidden_ingestion "$INGESTION_FIXTURE/forbidden.mjs" >/dev/null 2>&1; then
  fail "forbidden-ingestion guard missed synthetic SQLite/ChatGPT connectors"
else
  pass "forbidden-ingestion guard rejects synthetic SQLite/ChatGPT connectors"
fi
printf '%s\n' "const executable = 'sqlite3'; // never log database contents" \
  > "$INGESTION_FIXTURE/sqlite-cli.mjs"
if scan_forbidden_ingestion "$INGESTION_FIXTURE/sqlite-cli.mjs" >/dev/null 2>&1; then
  fail "forbidden-ingestion guard missed a quoted sqlite3 executable"
else
  pass "forbidden-ingestion guard rejects a quoted sqlite3 executable"
fi
rm -r -- "$INGESTION_FIXTURE"

echo "== AC-09 through AC-14: shared formats and scoped operations =="
assert_contains .opencode/skills/extract-topics/SKILL.md 'inputs/topics-YYYY-MM-DD.md' \
  "OpenCode topic skill uses the run-date filename"
assert_contains .agents/skills/extract-topics/SKILL.md 'inputs/topics-YYYY-MM-DD.md' \
  "Codex topic skill uses the run-date filename"
assert_contains .opencode/skills/extract-topics/SKILL.md 'Status: DRAFT' \
  ".opencode/skills/extract-topics/SKILL.md preserves DRAFT topics"
assert_contains .agents/skills/extract-topics/SKILL.md '| Status | DRAFT |' \
  ".agents/skills/extract-topics/SKILL.md preserves DRAFT topics"
for skill in .opencode/skills/extract-topics/SKILL.md .agents/skills/extract-topics/SKILL.md; do
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
LIVE_CHECK=tests/codex_live_check.sh
assert_file "$LIVE_CHECK"
assert_contains "$LIVE_CHECK" 'CODEX_ACCEPTANCE_RUNTIME' \
  "live Codex checks are explicitly gated"
assert_contains "$LIVE_CHECK" 'mktemp -d' \
  "live Codex checks create an isolated fixture project"
assert_contains "$LIVE_CHECK" 'CODEX_HOME' \
  "live Codex checks isolate Codex history"
assert_file tests/codex_runtime_probe.py
for contract in 'mcpServerStatus/list' 'thread/start' 'turn/start' 'mcpToolCall' 'normalize_app_server_events'; do
  assert_contains tests/codex_runtime_probe.py "$contract" "app-server probe records $contract"
done
assert_contains "$LIVE_CHECK" 'desktop' "live verifier exercises desktop configuration"
assert_absent "$LIVE_CHECK" 'verify_agent_events' "obsolete custom-agent verifier removed"
assert_file tests/codex_live_events_check.py
if python3 tests/codex_live_events_check.py; then
  pass "offline structured-event fixtures enforce parent-session live evidence"
else
  fail "offline structured-event fixtures reject live-event correlation behavior"
fi

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

echo "== AC-20 through AC-23: command-scoped Codex workflows =="
assert_file bin/blog-writer-codex
if [ -x bin/blog-writer-codex ]; then
  pass "command-scoped launcher is executable"
else
  fail "command-scoped launcher must be executable"
fi
assert_file tests/codex_launcher_check.sh
if bash tests/codex_launcher_check.sh; then
  pass "launcher behavior and fixed-profile argv pass deterministically"
else
  fail "launcher behavior checks failed"
fi
assert_contains tests/run_all.sh 'tests/codex_launcher_check.sh' \
  "default suite includes launcher checks"
assert_absent tests/run_all.sh 'tests/codex_live_check.sh' \
  "default suite still excludes live Codex checks"

for skill in .agents/skills/extract-topics/SKILL.md .agents/skills/write-blog-article/SKILL.md; do
  assert_contains "$skill" '### Command-scoped mode' "$skill retains narrow mode"
  assert_contains "$skill" '### Desktop mode' "$skill supports direct desktop routing"
  assert_contains "$skill" 'Missing, partial, or unexpected' "$skill rejects invalid catalogs"
done
assert_contains "$LIVE_CHECK" 'verify_command_events' "live verifier checks parent-session evidence"
assert_contains "$LIVE_CHECK" 'CODEX_LIVE_COMMAND_EVENT_FIXTURE' "parent-session verifier has offline fixtures"

for doc in README.md docs/acceptance.md; do
  assert_contains "$doc" './bin/blog-writer-codex topics "last week"' \
    "$doc documents the reliable topic command"
  assert_contains "$doc" './bin/blog-writer-codex article "topic 2"' \
    "$doc documents the reliable article command"
  assert_contains "$doc" '--no-daemon' \
    "$doc documents daemon isolation"
  assert_contains_ci "$doc" 'desktop' \
    "$doc documents direct desktop invocation"
  assert_contains_ci "$doc" 'does not publish' \
    "$doc keeps finalization separate from publication"
  assert_contains "$doc" 'Use extract-topics to find topics from last week.' \
    "$doc provides a direct desktop prompt"
  assert_contains "$doc" 'nine' "$doc documents the desktop catalog size"
  assert_contains_ci "$doc" 'manual file moves' "$doc explains manual publication bookkeeping"
  assert_contains_ci "$doc" 'desktop restart and smoke test' \
    "$doc distinguishes desktop verification from app-server evidence"
  assert_absent "$doc" 'Conditional custom-agent' "$doc removes obsolete fallback guidance"
done

assert_contains AGENTS.md 'desktop' "project instructions describe desktop bridge routing"
assert_absent AGENTS.md 'registers no privileged MCP bridge' "project instructions remove obsolete registration claim"
assert_contains docs/architecture/map.md 'codex-bridge/src/server.mjs' "architecture map includes bridge entrypoint"
assert_contains docs/architecture/map.md 'tests/codex_runtime_probe.py' "architecture map includes runtime verifier"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
