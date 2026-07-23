#!/usr/bin/env bash
#
# Verification for step 03 — CONVENTIONS.md authoring.
#
# Asserts every statically-checkable acceptance criterion from
# specs/steps/03-conventions-authoring.md:
#   - CONVENTIONS.template.md exists as a pristine starter with all eight
#     labelled sections, using ONLY the canonical <!-- TODO: ... --> marker,
#     naming the allowed MDX component vocabulary, and showing the
#     { id, label:{en,it} } tag shape;
#   - the author-conventions SKILL.md encodes the interactive interview
#     (one focused question at a time), covers all eight sections, the
#     EN->IT bilingual policy, the <!-- TODO: --> marker convention, and the
#     tag shape.
#
# Runtime-only criteria (the interview actually filling CONVENTIONS.md via
# question one area at a time; step 04 treating an all-<!-- TODO: --> file as
# "missing conventions") are covered in the plan's Verification section and
# cannot be asserted from a shell script.
#
# Usage: bash tests/conventions_check.sh   (run from anywhere)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

TEMPLATE="CONVENTIONS.template.md"
SKILL=".opencode/skills/author-conventions/SKILL.md"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

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

# assert_absent <file> <substring> <label>
assert_absent() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    fail "$3 (unexpected '$2' in $1)"
  else
    pass "$3"
  fi
}

# The eight stable, labelled sections the spec requires (in order).
SECTIONS=(
  "Voice & Tone"
  "Article Structure"
  "Bilingual Policy"
  "MDX Conventions"
  "Frontmatter Conventions"
  "Tag Vocabulary"
  "Taboos"
  "Examples"
)

echo "== Task 1: CONVENTIONS.template.md starter =="
assert_file "$TEMPLATE"
assert_nonempty "$TEMPLATE"
# All eight labelled sections present.
for s in "${SECTIONS[@]}"; do
  assert_contains "$TEMPLATE" "$s" "template has section: $s"
done
# Canonical placeholder marker used; legacy _Placeholder_ style must NOT leak.
assert_contains "$TEMPLATE" "<!-- TODO:" "template uses the canonical <!-- TODO: --> marker"
assert_absent   "$TEMPLATE" "_Placeholder" "template does not use the legacy _Placeholder_ marker"
# Allowed MDX component vocabulary named (consistent with the parent spec).
assert_contains "$TEMPLATE" "<Lang" "template names the <Lang> component"
assert_contains "$TEMPLATE" "<TOCInline" "template names the <TOCInline> component"
assert_contains "$TEMPLATE" "lang:filename" "template documents the lang:filename code-fence convention"
# Tag vocabulary in the { id, label:{en,it} } shape.
assert_contains "$TEMPLATE" "id:" "template tag entries have an id field"
assert_contains "$TEMPLATE" "label:" "template tag entries have a label field"
assert_contains "$TEMPLATE" "en:" "template tag labels have an en field"
assert_contains "$TEMPLATE" "it:" "template tag labels have an it field"

echo "== Task 2: author-conventions interview skill =="
assert_file "$SKILL"
assert_nonempty "$SKILL"
assert_contains "$SKILL" "author-conventions" "SKILL names the author-conventions skill"
# One-focused-question-at-a-time interview.
assert_contains "$SKILL" "question" "SKILL drives the interview via the question tool"
assert_contains_ci "$SKILL" "one" "SKILL asks one focused question at a time"
# All eight sections referenced by the interview.
for s in "${SECTIONS[@]}"; do
  assert_contains "$SKILL" "$s" "SKILL covers section: $s"
done
# Bilingual EN->IT policy.
assert_contains_ci "$SKILL" "en" "SKILL documents the English-first bilingual policy"
assert_contains_ci "$SKILL" "translat" "SKILL documents EN->IT translation policy"
# Canonical marker convention referenced (how step 04 detects missing conventions).
assert_contains "$SKILL" "<!-- TODO:" "SKILL references the <!-- TODO: --> marker convention"
# Tag shape.
assert_contains "$SKILL" "label:" "SKILL references the tag label shape"
# DRAFT-first discipline: never embed large markdown in a question.
assert_contains_ci "$SKILL" "never embed" "SKILL warns never to embed large markdown in a question"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
