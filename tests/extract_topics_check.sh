#!/usr/bin/env bash
#
# Verification for step 02 — topic-extractor agent & extract-topics skill.
#
# Asserts every statically-checkable acceptance criterion from
# specs/steps/02-topic-extractor-agent-and-skill.md:
#   - the extract-topics SKILL.md encodes the full workflow,
#   - the topic-extractor agent prompt is real (not the step-01 stub) and
#     carries the anti-hijack rule,
#   - the redaction helper redacts secret-like patterns and flags them,
#     while passing clean text through unchanged.
#
# Runtime-only criteria (opencode actually invoking the agent, DRAFT->FINAL
# on approval via question, permission enforcement) are covered in the plan's
# Verification section and cannot be asserted from a shell script.
#
# Usage: bash tests/extract_topics_check.sh   (run from anywhere)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SKILL=".opencode/skills/extract-topics/SKILL.md"
AGENT=".opencode/agents/topic-extractor.md"
REDACT=".opencode/skills/extract-topics/scripts/redact.py"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_file()    { if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi; }
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

# assert_absent <file> <substring> <label>
assert_absent() {
  if [ -f "$1" ] && grep -qiF -- "$2" "$1"; then
    fail "$3 (unexpected '$2' in $1)"
  else
    pass "$3"
  fi
}

echo "== Task 1: extract-topics SKILL.md workflow =="
assert_file "$SKILL"
assert_nonempty "$SKILL"
# Frontmatter / discoverability
assert_contains "$SKILL" "extract-topics" "SKILL names the extract-topics skill"
# Step 2: allowlist vs auto-discover
assert_contains "$SKILL" "tracked-projects.txt" "SKILL references the allowlist file"
assert_contains "$SKILL" "SELECT DISTINCT directory" "SKILL includes the auto-discovery query"
assert_contains_ci "$SKILL" "auto-discover" "SKILL documents auto-discovery fallback"
assert_contains "$SKILL" "question" "SKILL confirms discovered projects via question"
# SQL constraints
assert_contains "$SKILL" "sqlite3 -readonly" "SKILL mandates sqlite3 -readonly"
assert_contains "$SKILL" "time_updated" "SKILL filters on time_updated"
# time_updated correction: must NOT claim it is indexed / scan-free
assert_absent "$SKILL" "indexed time_updated" "SKILL does not claim time_updated is indexed"
assert_absent "$SKILL" "no full-table scan" "SKILL does not claim scans are avoided"
# Step 4: session text substance, capped
assert_contains "$SKILL" "part" "SKILL sources text from part data"
assert_contains_ci "$SKILL" "cap" "SKILL caps session text volume"
# Step 5: correlation
assert_contains_ci "$SKILL" "correlat" "SKILL correlates commits and sessions by timestamp"
# Step 6: redaction + Flagged
assert_contains "$SKILL" "client_secret" "SKILL lists client_secret pattern"
assert_contains "$SKILL" "api_key" "SKILL lists api_key pattern"
assert_contains "$SKILL" "bearer" "SKILL lists bearer pattern"
assert_contains "$SKILL" "Flagged" "SKILL marks flagged topics"
assert_contains "$SKILL" "redact.py" "SKILL references the redaction helper"
# Step 8: DRAFT-first + date-stamped filename + overwrite prompt
assert_contains "$SKILL" "Status: DRAFT" "SKILL writes Status: DRAFT"
assert_contains "$SKILL" "FINAL" "SKILL flips to FINAL on approval"
assert_contains "$SKILL" "topics-YYYY-MM-DD.md" "SKILL uses date-stamped filenames"
assert_contains_ci "$SKILL" "run date" "SKILL derives filename from the run date"
assert_contains_ci "$SKILL" "iso week" "SKILL still records the ISO week inside the file"
assert_contains_ci "$SKILL" "overwrite" "SKILL prompts before overwriting today's file"
# Anti-embed rule
assert_contains_ci "$SKILL" "never embed" "SKILL warns never to embed file body in question"
# Empty result rule
assert_contains_ci "$SKILL" "no topics" "SKILL still writes a DRAFT when no topics are found"
# Step 5b: exclude already-published topics
assert_contains "$SKILL" "published-topics.md" "SKILL reads the published-topics ledger"
assert_contains "$SKILL" "topic_key" "SKILL matches topics by topic_key"
assert_contains_ci "$SKILL" "already-published" "SKILL excludes already-published topics"
assert_contains_ci "$SKILL" "drafts do" "SKILL excludes only published (not drafts)"
# Step 8: Generated timestamp line
assert_contains "$SKILL" "Generated" "SKILL records a Generated timestamp"
# Step 7: evaluation + ordering defaults
assert_contains_ci "$SKILL" "reader appeal" "SKILL scores the Reader appeal dimension"
assert_contains_ci "$SKILL" "publishability" "SKILL scores the Publishability dimension"
assert_contains_ci "$SKILL" "overall" "SKILL computes an Overall score"
assert_contains_ci "$SKILL" "highest overall" "SKILL orders topics by descending Overall"

echo "== Task 3: topic-extractor agent prompt =="
assert_file "$AGENT"
assert_nonempty "$AGENT"
assert_contains "$AGENT" "primary" "agent declares mode: primary"
assert_contains "$AGENT" "extract-topics" "agent loads the extract-topics skill"
# Anti-hijack: never writes an article
assert_contains_ci "$AGENT" "never" "agent has an anti-hijack 'never' rule"
assert_contains_ci "$AGENT" "article" "agent anti-hijack mentions articles"
# Stub must be gone
assert_absent "$AGENT" "stub" "agent no longer marked as a stub"
assert_absent "$AGENT" "placeholder" "agent no longer marked as a placeholder"

echo "== Task 2: redaction helper =="
assert_file "$REDACT"
if [ -f "$REDACT" ]; then
  # Secret fixtures should be redacted AND flagged.
  for secret in \
    "here is my client_secret=abcd1234efgh5678" \
    "Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" \
    "api_key: sk-1234567890ABCDEFabcdef" \
    "token=deadbeefdeadbeefdeadbeefdeadbeef1234" \
    "hash 0123456789abcdef0123456789abcdef0123456789abcdef"
  do
    out="$(printf '%s' "$secret" | python3 "$REDACT" 2>/tmp/redact_flag.$$)"
    if printf '%s' "$out" | grep -qF "REDACTED"; then
      pass "redact.py redacts: ${secret%% *}..."
    else
      fail "redact.py did NOT redact: $secret (got: $out)"
    fi
    if grep -qiF "flag" /tmp/redact_flag.$$; then
      pass "redact.py signals a flag for: ${secret%% *}..."
    else
      fail "redact.py did NOT signal a flag for: $secret"
    fi
    rm -f /tmp/redact_flag.$$
  done

  # Clean text passes through unchanged and raises no flag.
  clean="This is a perfectly ordinary sentence about refactoring the parser."
  out="$(printf '%s' "$clean" | python3 "$REDACT" 2>/tmp/redact_flag.$$)"
  if [ "$out" = "$clean" ]; then
    pass "redact.py passes clean text through unchanged"
  else
    fail "redact.py altered clean text (got: $out)"
  fi
  if grep -qiF "flag" /tmp/redact_flag.$$; then
    fail "redact.py raised a flag on clean text"
  else
    pass "redact.py raises no flag on clean text"
  fi
  rm -f /tmp/redact_flag.$$
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
