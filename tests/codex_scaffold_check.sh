#!/usr/bin/env bash
#
# Static verification for the Codex skills, custom agents, and project config.
# Run from anywhere; exit 0 means every scoped-routing check passed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_file() {
  if [ -f "$1" ]; then
    pass "file exists: $1"
  else
    fail "file missing: $1"
  fi
}

assert_contains() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' in $1)"
  fi
}

assert_absent() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    fail "$3 (unexpected '$2' in $1)"
  else
    pass "$3"
  fi
}

check_skill() {
  local path="$1"
  local name="$2"
  local description="$3"
  local agent="$4"

  assert_file "$path"
  [ -f "$path" ] || return

  local actual_name actual_description
  actual_name="$(sed -n 's/^name: //p' "$path" | head -1)"
  actual_description="$(sed -n 's/^description: //p' "$path" | head -1)"

  if [ "$actual_name" = "$name" ]; then
    pass "$name skill has exact metadata name"
  else
    fail "$name skill metadata name is '$actual_name'"
  fi

  if [ "$actual_description" = "$description" ]; then
    pass "$name skill has exact metadata description"
  else
    fail "$name skill metadata description is not exact"
  fi

  assert_contains "$path" "The main chat owns every user question" \
    "$name keeps user questions in the main chat"
  assert_contains "$path" "### Desktop mode" "$name supports desktop execution"
  assert_contains "$path" "exactly these nine" "$name validates the complete desktop catalog"
  assert_contains "$path" "Missing, partial, or unexpected" "$name rejects invalid catalogs"
  assert_contains "$path" "Unrelated MCP servers" "$name scopes catalog validation"
  assert_contains "$path" "Never use shell or general filesystem tools" "$name forbids bridge bypasses"
  assert_absent "$path" "Delegate only to" "$name has no agent fallback"

}

echo "== Codex skill discovery and routing =="
check_skill \
  .agents/skills/extract-topics/SKILL.md \
  extract-topics \
  "Use when the user asks to extract, surface, or find candidate blog topics from recent Codex and Git activity." \
  topic-extractor
check_skill \
  .agents/skills/write-blog-article/SKILL.md \
  write-blog-article \
  "Use when the user asks to draft, revise, finalize, or publish a bilingual blog article." \
  blog-writer
check_skill \
  .agents/skills/author-conventions/SKILL.md \
  author-conventions \
  "Use when the user asks to create or update the project's writing conventions through a focused interview." \
  conventions-writer

TOPIC_SKILL=.agents/skills/extract-topics/SKILL.md
CONVENTIONS_SKILL=.agents/skills/author-conventions/SKILL.md
WRITER_SKILL=.agents/skills/write-blog-article/SKILL.md

assert_contains "$TOPIC_SKILL" "Follow these ten steps in order" \
  "topic skill preserves the ten-step workflow"
assert_contains "$TOPIC_SKILL" "normalized activity" \
  "topic skill consumes normalized bridge activity"
assert_contains "$TOPIC_SKILL" "Resolve relative entries against the workflow" \
  "topic skill normalizes relative allowlist entries"
assert_contains "$TOPIC_SKILL" "| Status | DRAFT |" \
  "topic skill writes DRAFT first"
assert_contains "$TOPIC_SKILL" "finalize_topics" \
  "topic skill uses marker-only finalization"
assert_contains "$TOPIC_SKILL" "warnings" \
  "topic skill carries bridge warnings into its appendix"
assert_contains "$TOPIC_SKILL" "flagged" \
  "topic skill carries redaction flags into review"
assert_absent "$TOPIC_SKILL" "sqlite3" \
  "topic skill does not depend on SQLite"
assert_absent "$TOPIC_SKILL" "opencode.db" \
  "topic skill does not depend on the OpenCode database"

assert_contains "$CONVENTIONS_SKILL" "one focused question at a time" \
  "conventions skill preserves the focused interview"
assert_contains "$CONVENTIONS_SKILL" '<!-- TODO:' \
  "conventions skill preserves placeholder rules"
assert_contains "$CONVENTIONS_SKILL" "write_conventions" \
  "conventions skill delegates scoped persistence"
assert_contains "$CONVENTIONS_SKILL" "After each answer, assemble the complete updated document" \
  "conventions skill preserves incremental persistence"
assert_contains "$CONVENTIONS_SKILL" "final review" \
  "conventions skill keeps final review in the main chat"

assert_contains "$WRITER_SKILL" "CONVENTIONS.md" \
  "article skill checks conventions"
assert_contains "$WRITER_SKILL" "placeholder-only" \
  "article skill rejects placeholder-only conventions"
assert_contains "$WRITER_SKILL" "English body first" \
  "article skill preserves English-first drafting"
assert_contains "$WRITER_SKILL" '<Lang value="en">' \
  "article skill preserves the English MDX block"
assert_contains "$WRITER_SKILL" '<Lang value="it">' \
  "article skill preserves the Italian MDX block"
assert_contains "$WRITER_SKILL" "read_source_file" \
  "article skill delegates bounded fact checks"
assert_contains "$WRITER_SKILL" "publish_article" \
  "article skill delegates explicit publication"
assert_contains "$WRITER_SKILL" "Published-slug replacement is unsupported" \
  "article skill stops safely on published collisions"
assert_absent "$WRITER_SKILL" "previously dated or published article" \
  "article skill does not claim published-article editing"
assert_contains "$WRITER_SKILL" "Never invent components outside this set" \
  "article skill preserves the controlled MDX vocabulary"

echo "== Codex direct execution modes =="
for skill in "$TOPIC_SKILL" "$WRITER_SKILL"; do
  assert_contains "$skill" "### Command-scoped mode" "$skill retains narrow command mode"
  assert_contains "$skill" "explicitly selected" "$skill requires explicit narrow-mode selection"
  assert_contains "$skill" "exact four-tool" "$skill rejects wider catalogs in command mode"
done
assert_contains "$CONVENTIONS_SKILL" "### Conventions-only mode" "conventions retains its narrow profile"

echo "== Codex project configuration =="
python3 - <<'PYCHECK'
import json
import pathlib
import re
p = pathlib.Path('.codex/config.toml')
s = p.read_text()
assert re.search(r'^sandbox_mode = "read-only"$', s, re.M)
assert s.count('[mcp_servers.') == 1
assert '[mcp_servers.blog_writer_bridge]' in s
assert json.loads(re.search(r'^command = (".*")$', s, re.M)[1]) == '/bin/sh'
assert json.loads(re.search(r'^args = (\[.*\])$', s, re.M)[1]) == [
    '-c', 'set -eu; bridge_code_root=$(git rev-parse --show-toplevel); exec node "$bridge_code_root/codex-bridge/src/server.mjs" --profile desktop'
]
assert not re.search(r'^cwd\s*=', s, re.M)
assert '[agents]' not in s and '[features]' not in s
for role in ('topic-extractor', 'blog-writer', 'conventions-writer'):
    assert not pathlib.Path(f'.codex/agents/{role}.toml').exists()
print('PASS: parent desktop registration, fixed startup, read-only sandbox, and obsolete-agent removal')
PYCHECK
if [ $? -ne 0 ]; then FAIL=1; fi

echo "== Runtime-neutral project guidance =="
assert_contains AGENTS.md "## OpenCode runtime" \
  "AGENTS.md retains explicit OpenCode guidance"
assert_contains AGENTS.md "## Codex runtime" \
  "AGENTS.md documents Codex skill/custom-agent routing"
assert_contains AGENTS.md "placeholder-only" \
  "AGENTS.md rejects placeholder-only conventions"
assert_contains AGENTS.md "not indexed" \
  "AGENTS.md correctly describes OpenCode time_updated"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi

echo "SOME CHECKS FAILED"
exit 1
