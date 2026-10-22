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

  assert_contains "$path" "Delegate only to \`$agent\`" \
    "$name delegates only to $agent"
  assert_contains "$path" "The main chat owns every user question" \
    "$name keeps user questions in the main chat"
  assert_contains "$path" "Never ask a custom agent to question the user" \
    "$name forbids delegated user questions"

  for other in topic-extractor blog-writer conventions-writer; do
    if [ "$other" != "$agent" ]; then
      assert_absent "$path" "Delegate only to \`$other\`" \
        "$name does not route to $other"
    fi
  done
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

echo "== Codex command-scoped and custom-agent modes =="
for skill in "$TOPIC_SKILL" "$WRITER_SKILL"; do
  assert_contains "$skill" "## Execution modes" \
    "$skill defines mutually exclusive execution modes"
  assert_contains "$skill" "### Command-scoped mode" \
    "$skill documents direct main-session execution"
  assert_contains "$skill" "### Custom-agent mode" \
    "$skill preserves custom-agent fallback"
  assert_contains "$skill" "partial matching surface" \
    "$skill stops on a partial bridge surface"
  assert_contains "$skill" "cross-role bridge tool" \
    "$skill stops on cross-role bridge exposure"
  assert_contains "$skill" \
    'falls outside the exact four-tool' \
    "$skill stops on every bridge tool outside its exact allowlist"
  assert_contains "$skill" "Never use shell or general filesystem tools" \
    "$skill forbids mutation bypasses"
done

assert_contains "$TOPIC_SKILL" \
  '`discover_projects`, `collect_activity`, `write_topic_draft`, and `finalize_topics`' \
  "topic command mode requires the exact topic tool surface"
assert_contains "$TOPIC_SKILL" \
  'Do not delegate to `topic-extractor` in command-scoped mode.' \
  "topic command mode forbids custom-agent delegation"
assert_contains "$TOPIC_SKILL" \
  'No `blog_writer_bridge` tool is visible' \
  "topic custom-agent mode requires an absent main bridge surface"
for cross_role in write_conventions read_source_file write_article_draft finalize_article publish_article; do
  assert_contains "$TOPIC_SKILL" "\`$cross_role\`" \
    "topic mode names cross-role tool $cross_role"
done

assert_contains "$WRITER_SKILL" \
  '`read_source_file`, `write_article_draft`, `finalize_article`, and `publish_article`' \
  "writer command mode requires the exact writer tool surface"
assert_contains "$WRITER_SKILL" \
  'Do not delegate to `blog-writer` in command-scoped mode.' \
  "writer command mode forbids custom-agent delegation"
assert_contains "$WRITER_SKILL" \
  'No `blog_writer_bridge` tool is visible' \
  "writer custom-agent mode requires an absent main bridge surface"
for cross_role in discover_projects collect_activity write_topic_draft finalize_topics write_conventions; do
  assert_contains "$WRITER_SKILL" "\`$cross_role\`" \
    "writer mode names cross-role tool $cross_role"
done

echo "== Codex project and custom-agent configuration =="
assert_file .codex/config.toml
assert_file .codex/agents/topic-extractor.toml
assert_file .codex/agents/blog-writer.toml
assert_file .codex/agents/conventions-writer.toml

if [ -f .codex/config.toml ]; then
  python3 - <<'PY'
import pathlib
import re
import sys

failed = False

def passed(message):
    print(f"PASS: {message}")

def fail(message):
    global failed
    print(f"FAIL: {message}")
    failed = True

text = pathlib.Path('.codex/config.toml').read_text(encoding='utf-8')
if re.search(r'^sandbox_mode = "read-only"$', text, re.M):
    passed('main Codex sandbox is read-only')
else:
    fail('main Codex sandbox must remain read-only')
if '[mcp_servers.blog_writer_bridge]' in text and '--profile desktop' in text:
    passed('main chat registers the desktop bridge')
else:
    fail('main chat must register the desktop bridge')
if re.search(r'^cwd\s*=', text, re.M):
    fail('desktop startup must not depend on a relative cwd')

sys.exit(1 if failed else 0)
PY
  if [ $? -ne 0 ]; then FAIL=1; fi
fi

python3 - <<'PY'
import ast
import pathlib
import re
import sys

expected = {
    'topic-extractor': {
        'description': 'Analyzes bounded Codex and Git activity and persists reviewed topic files through the topic bridge profile.',
        'profile': 'topic',
    },
    'blog-writer': {
        'description': 'Fact-checks approved sources and performs scoped article draft, finalization, and publication operations.',
        'profile': 'writer',
    },
    'conventions-writer': {
        'description': 'Persists approved writing conventions through the conventions bridge profile.',
        'profile': 'conventions',
    },
}
failed = False

def passed(message):
    print(f"PASS: {message}")

def fail(message):
    global failed
    print(f"FAIL: {message}")
    failed = True

for role, wanted in expected.items():
    path = pathlib.Path('.codex/agents') / f'{role}.toml'
    if not path.is_file():
        continue
    text = path.read_text(encoding='utf-8')
    match = re.fullmatch(
        r'name = "(?P<name>[^"\n]+)"\n'
        r'description = "(?P<description>[^"\n]+)"\n'
        r'developer_instructions = """\n(?P<instructions>.*?)\n"""\n'
        r'sandbox_mode = "(?P<sandbox>[^"\n]+)"\n\n'
        r'\[mcp_servers\.(?P<server>[^\]\n]+)\]\n'
        r'command = "(?P<command>[^"\n]+)"\n'
        r'args = (?P<args>\[[^\n]+\])\n?',
        text,
        flags=re.DOTALL,
    )
    if match is None:
        fail(f'{path} does not use the supported static TOML shape')
        continue
    passed(f'{path} uses the supported static TOML shape')

    if match.group('name') == role:
        passed(f'{role} has the exact name')
    else:
        fail(f'{role} must declare name = {role!r}')

    if match.group('description') == wanted['description']:
        passed(f'{role} has the exact description')
    else:
        fail(f'{role} description is not exact')

    instructions = match.group('instructions')
    if instructions.strip():
        passed(f'{role} has developer instructions')
        for required in (
            'Never ask the user questions',
            'Return a concise structured result to the parent',
        ):
            if required in instructions:
                passed(f'{role} instructions include: {required}')
            else:
                fail(f'{role} instructions missing: {required}')
    else:
        fail(f'{role} must have non-empty developer_instructions')

    if match.group('sandbox') == 'read-only':
        passed(f'{role} sandbox is read-only')
    else:
        fail(f'{role} sandbox must be read-only')

    if match.group('server') == 'blog_writer_bridge':
        passed(f'{role} uses the canonical bridge registration name')
    else:
        fail(f'{role} must name its MCP registration blog_writer_bridge')

    if match.group('command') == 'node':
        passed(f'{role} starts the bridge with node')
    else:
        fail(f'{role} bridge command must be node')

    wanted_args = [
        'codex-bridge/src/server.mjs',
        '--profile',
        wanted['profile'],
    ]
    try:
        actual_args = ast.literal_eval(match.group('args'))
    except (SyntaxError, ValueError):
        actual_args = None
    if actual_args == wanted_args:
        passed(f"{role} is isolated to the {wanted['profile']} profile")
    else:
        fail(f'{role} bridge args must be {wanted_args!r}')

sys.exit(1 if failed else 0)
PY
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
