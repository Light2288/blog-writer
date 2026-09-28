#!/usr/bin/env bash
#
# End-to-end static acceptance verification for step 05.
#
# Asserts the system-wide, statically-verifiable acceptance criteria from
# specs/steps/05-end-to-end-acceptance.md in a single pass, on top of the
# artifacts delivered by steps 01-04. Groups checks by acceptance scenario:
#
#   Scenario 1     fresh-clone readiness (required tree; optional allowlist)
#   Scenarios 2/6  extractor DRAFT-first (Status: DRAFT -> FINAL)
#   Scenarios 7/10 blog-writer DRAFT-first (draft: true -> draft: false)
#   Scenarios 8/9  bilingual output + allowed MDX component vocabulary
#   Scenarios 3/4  auto-discovery fallback vs tracked-projects.txt allowlist
#   Scenario 15    read-only DB access filtered on time_updated (no bare sqlite3)
#   Coverage       docs/acceptance.md references every scenario + every verifier
#
# Runtime-only scenarios (agent conversations, live DRAFT->FINAL approvals,
# permission enforcement, destructive-command denial) are proven by
# tests/permission_check.sh and documented as a manual script in
# docs/acceptance.md; they cannot be asserted from this static script.
#
# Usage: bash tests/acceptance_check.sh   (run from anywhere)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

EXTRACT_SKILL=".opencode/skills/extract-topics/SKILL.md"
WRITE_SKILL=".opencode/skills/write-blog-article/SKILL.md"
CONV_SKILL=".opencode/skills/author-conventions/SKILL.md"
EXTRACT_AGENT=".opencode/agents/topic-extractor.md"
WRITE_AGENT=".opencode/agents/blog-writer.md"
ACCEPTANCE_DOC="docs/acceptance.md"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_dir()      { if [ -d "$1" ]; then pass "dir exists: $1"; else fail "dir missing: $1"; fi; }
assert_file()     { if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi; }
assert_nonempty() { if [ -s "$1" ]; then pass "file non-empty: $1"; else fail "file empty/missing: $1"; fi; }

# assert_contains <file> <substring> <label>
assert_contains() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' in $1)"
  fi
}

# assert_contains_ci <file> <substring> <label>  (case-insensitive)
assert_contains_ci() {
  if [ -f "$1" ] && grep -qiF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' case-insensitively in $1)"
  fi
}

echo "== Scenario 1: fresh-clone readiness =="
assert_dir inputs
assert_dir drafts
assert_dir published
assert_file inputs/.gitkeep
assert_file drafts/.gitkeep
assert_file published/.gitkeep
assert_file AGENTS.md
assert_file README.md
assert_file CONVENTIONS.template.md
assert_file .opencode/opencode.json
assert_file "$EXTRACT_AGENT"
assert_file "$WRITE_AGENT"
assert_file "$EXTRACT_SKILL"
assert_file "$WRITE_SKILL"
assert_file "$CONV_SKILL"
# tracked-projects.txt is OPTIONAL: pass whether present or absent.
if [ -e tracked-projects.txt ]; then
  pass "tracked-projects.txt present (optional allowlist)"
else
  pass "tracked-projects.txt absent (optional; auto-discovery applies)"
fi

echo "== Scenarios 2 & 6: extractor DRAFT-first =="
assert_nonempty "$EXTRACT_SKILL"
assert_contains "$EXTRACT_AGENT" "inputs/topics-YYYY-MM-DD.md" \
  "topic-extractor agent uses the run-date filename"
if grep -qF -- "inputs/topics-YYYY-Www.md" "$EXTRACT_AGENT"; then
  fail "topic-extractor agent retains the obsolete ISO-week filename"
else
  pass "topic-extractor agent has no ISO-week filename contradiction"
fi
assert_contains "$EXTRACT_SKILL" "Status: DRAFT" "extract-topics writes Status: DRAFT"
assert_contains "$EXTRACT_SKILL" "FINAL" "extract-topics flips to FINAL on approval"
assert_contains_ci "$EXTRACT_SKILL" "never embed" "extract-topics never embeds the file body in a question"

echo "== Scenarios 7 & 10: blog-writer DRAFT-first =="
assert_nonempty "$WRITE_SKILL"
assert_contains "$WRITE_SKILL" "draft: true" "write-blog-article writes draft: true"
assert_contains "$WRITE_SKILL" "draft: false" "write-blog-article flips draft: false on approval"
assert_contains_ci "$WRITE_SKILL" "never embed" "write-blog-article never embeds the body in a question"
assert_contains "$WRITE_SKILL" "CONVENTIONS.md" "write-blog-article reads CONVENTIONS.md"

echo "== Scenarios 8 & 9: bilingual output + allowed MDX vocabulary =="
assert_contains "$WRITE_SKILL" '<Lang value="en"' "write-blog-article emits the English <Lang> block"
assert_contains "$WRITE_SKILL" '<Lang value="it"' "write-blog-article emits the Italian <Lang> block"
assert_contains_ci "$WRITE_SKILL" "english" "write-blog-article drafts English first"
assert_contains_ci "$WRITE_SKILL" "translat" "write-blog-article translates EN -> IT"
assert_contains "$WRITE_SKILL" "<TOCInline" "write-blog-article names the <TOCInline> component"
assert_contains "$WRITE_SKILL" "lang:filename" "write-blog-article documents the lang:filename code-fence convention"
assert_contains "$WRITE_SKILL" "label:" "write-blog-article uses the { id, label:{en,it} } tag shape"
# English-first ordering: 'english' anchor appears before the first 'translat' anchor.
if [ -f "$WRITE_SKILL" ]; then
  en_line="$(grep -niE 'english' "$WRITE_SKILL" | head -1 | cut -d: -f1)"
  it_line="$(grep -niE 'translat' "$WRITE_SKILL" | head -1 | cut -d: -f1)"
  if [ -n "$en_line" ] && [ -n "$it_line" ] && [ "$en_line" -le "$it_line" ]; then
    pass "write-blog-article orders English drafting before translation"
  else
    fail "write-blog-article does not clearly order English before translation (en=$en_line it=$it_line)"
  fi
fi

echo "== Scenarios 3 & 4: auto-discovery fallback vs allowlist =="
assert_contains "$EXTRACT_SKILL" "tracked-projects.txt" "extract-topics references the allowlist file"
assert_contains "$EXTRACT_SKILL" "SELECT DISTINCT directory" "extract-topics includes the auto-discovery query"
assert_contains_ci "$EXTRACT_SKILL" "auto-discover" "extract-topics documents the auto-discovery fallback"
assert_contains "$EXTRACT_SKILL" "question" "extract-topics confirms discovered projects via question"

echo "== Scenario 5 (static anchor): redaction/flagging =="
assert_contains "$EXTRACT_SKILL" "Flagged" "extract-topics marks flagged topics"
assert_file ".opencode/skills/extract-topics/scripts/redact.py"

echo "== Scenario 15: read-only DB filtered on time_updated =="
assert_contains "$EXTRACT_SKILL" "sqlite3 -readonly" "extract-topics mandates sqlite3 -readonly"
assert_contains "$EXTRACT_SKILL" "time_updated" "extract-topics filters on time_updated"
# No sqlite3 invocation anywhere in tracked files may omit -readonly.
# Inspect every line that calls sqlite3 and ensure it also mentions -readonly.
bad_sqlite="$(grep -rInE 'sqlite3[[:space:]]' \
  --include='*.md' --include='*.sh' --include='*.py' --include='*.json' . 2>/dev/null \
  | grep -v -- '-readonly' \
  | grep -v 'tests/acceptance_check.sh' \
  | grep -v 'tests/codex_acceptance_check.sh' || true)"
if [ -z "$bad_sqlite" ]; then
  pass "every sqlite3 invocation in tracked files uses -readonly"
else
  fail "found sqlite3 invocation(s) without -readonly:"
  printf '%s\n' "$bad_sqlite" | sed 's/^/       /'
fi

echo "== Coverage: docs/acceptance.md references every scenario + verifier =="
assert_file "$ACCEPTANCE_DOC"
if [ -f "$ACCEPTANCE_DOC" ]; then
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if grep -qE "(^|[^0-9])$n([^0-9]|\$)" "$ACCEPTANCE_DOC"; then
      pass "acceptance doc references scenario $n"
    else
      fail "acceptance doc does not reference scenario $n"
    fi
  done
  for s in scaffold_check.sh extract_topics_check.sh conventions_check.sh \
           blog_writer_check.sh permission_check.sh redaction_check.sh \
           codex_scaffold_check.sh codex_acceptance_check.sh \
           codex_live_check.sh; do
    assert_contains "$ACCEPTANCE_DOC" "$s" "acceptance doc names verifier: $s"
  done
  assert_contains "$ACCEPTANCE_DOC" "npm test --prefix codex-bridge" \
    "acceptance doc names the bridge unit/integration verifier"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
