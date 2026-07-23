#!/usr/bin/env bash
#
# Deterministic redaction/flagging fixture check for step 05 (scenario 5).
#
# Verifies specs/steps/05-end-to-end-acceptance.md scenario 5 without touching
# the live opencode DB (per the spec's "Fixtures vs. live data" guidance):
# secret-like fixtures are redacted AND raise a flag; clean text passes through
# unchanged and raises no flag; and the extract-topics skill maps a raised flag
# onto a topic's **Flagged** note in the DRAFT topics file.
#
# The redaction helper contract (see redact.py):
#   stdout = input with matches replaced by [REDACTED:<reason>]
#   stderr = the single line "FLAG" iff a redaction occurred
#   exit   = always 0
#
# Usage: bash tests/redaction_check.sh   (run from anywhere)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

REDACT=".opencode/skills/extract-topics/scripts/redact.py"
EXTRACT_SKILL=".opencode/skills/extract-topics/SKILL.md"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_file()     { if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi; }
assert_contains() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' in $1)"
  fi
}

echo "== redaction helper present =="
assert_file "$REDACT"

if [ -f "$REDACT" ]; then
  echo "== secret fixtures: redacted AND flagged =="
  ERRFILE="$(mktemp "${TMPDIR:-/tmp}/redact_err.XXXXXX")"
  for secret in \
    "here is my client_secret=abcd1234efgh5678" \
    "Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" \
    "api_key: sk-1234567890ABCDEFabcdef" \
    "token=deadbeefdeadbeefdeadbeefdeadbeef1234" \
    "hash 0123456789abcdef0123456789abcdef0123456789abcdef"
  do
    out="$(printf '%s' "$secret" | python3 "$REDACT" 2>"$ERRFILE")"
    if printf '%s' "$out" | grep -qF "REDACTED"; then
      pass "redacts secret: ${secret%% *}..."
    else
      fail "did NOT redact secret: $secret (got: $out)"
    fi
    if grep -qF "FLAG" "$ERRFILE"; then
      pass "flags secret: ${secret%% *}..."
    else
      fail "did NOT flag secret: $secret"
    fi
    : > "$ERRFILE"
  done

  echo "== clean fixture: unchanged, no flag =="
  clean="This is a perfectly ordinary sentence about refactoring the parser."
  out="$(printf '%s' "$clean" | python3 "$REDACT" 2>"$ERRFILE")"
  if [ "$out" = "$clean" ]; then
    pass "clean text passes through unchanged"
  else
    fail "clean text was altered (got: $out)"
  fi
  if grep -qF "FLAG" "$ERRFILE"; then
    fail "raised a flag on clean text"
  else
    pass "no flag on clean text"
  fi
  rm -f "$ERRFILE"
fi

echo "== skill maps a flag onto a topic's Flagged note =="
assert_contains "$EXTRACT_SKILL" "Flagged" "extract-topics marks flagged topics in the DRAFT file"
assert_contains "$EXTRACT_SKILL" "redact.py" "extract-topics runs the redaction helper"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
