#!/usr/bin/env bash
#
# Verification for step 04 — blog-writer agent & write-blog-article skill.
#
# Asserts every statically-checkable acceptance criterion from
# specs/steps/04-blog-writer-agent-and-skill.md:
#   - the write-blog-article SKILL.md encodes the full authoring workflow:
#     load-conventions guard (refuse on missing/placeholder), topic resolution
#     from inputs/topics-*.md or free text, English-first drafting with
#     draft: true, iterate-then-translate to a single bilingual .mdx with both
#     <Lang> blocks, the allowed MDX component vocabulary, publish-on-command
#     (move drafts/ -> published/), tags drawn from the CONVENTIONS vocabulary,
#     and the DRAFT-first "never embed the body in a question" discipline;
#   - the blog-writer agent declares mode: primary, loads the
#     write-blog-article skill, carries the anti-hijack rules (never edit
#     source projects, never commit, never push), and no longer reads as a
#     stub/placeholder.
#
# Runtime-only criteria (actually reading a real CONVENTIONS.md and refusing on
# a placeholder one, iterating via question without embedding the body,
# flipping draft: on approval, moving the file on "publish <slug>") are covered
# in the plan's Verification section and cannot be asserted from a shell
# script.
#
# Usage: bash tests/blog_writer_check.sh   (run from anywhere)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SKILL=".opencode/skills/write-blog-article/SKILL.md"
AGENT=".opencode/agents/blog-writer.md"

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

# assert_absent_ci <file> <substring> <label>  (case-insensitive)
assert_absent_ci() {
  if [ -f "$1" ] && grep -qiF -- "$2" "$1"; then
    fail "$3 (unexpected '$2' in $1)"
  else
    pass "$3"
  fi
}

echo "== Task 1: write-blog-article skill workflow =="
assert_file "$SKILL"
assert_nonempty "$SKILL"
# YAML frontmatter names the skill.
assert_contains "$SKILL" "write-blog-article" "SKILL names the write-blog-article skill"
# Step 1: load conventions + refuse on missing/placeholder.
assert_contains "$SKILL" "CONVENTIONS.md" "SKILL reads CONVENTIONS.md"
assert_contains_ci "$SKILL" "refuse" "SKILL refuses to draft without real conventions"
assert_contains_ci "$SKILL" "placeholder" "SKILL treats an all-placeholder conventions file as missing"
# Step 2: topic resolution.
assert_contains "$SKILL" "topics-" "SKILL resolves a topic from inputs/topics-*.md"
assert_contains_ci "$SKILL" "free" "SKILL accepts a free-text topic"
# Step 3: slug + target path.
assert_contains "$SKILL" "drafts/" "SKILL targets drafts/<slug>.mdx"
assert_contains_ci "$SKILL" "slug" "SKILL derives a slug"
# Step 4-5: English first + draft marker.
assert_contains_ci "$SKILL" "english" "SKILL drafts the English body first"
assert_contains "$SKILL" "draft: true" "SKILL writes the frontmatter draft: true marker"
# Step 6-7: bilingual assembly, both Lang blocks.
assert_contains "$SKILL" '<Lang value="en"' "SKILL emits the English <Lang> block"
assert_contains "$SKILL" '<Lang value="it"' "SKILL emits the Italian <Lang> block"
assert_contains_ci "$SKILL" "translat" "SKILL translates the approved English to Italian"
# Allowed MDX component vocabulary.
assert_contains "$SKILL" "<TOCInline" "SKILL names the <TOCInline> component"
assert_contains "$SKILL" "lang:filename" "SKILL documents the lang:filename code-fence convention"
# Tags drawn from the CONVENTIONS vocabulary, in { id, label:{en,it} } shape.
assert_contains "$SKILL" "label:" "SKILL uses the tag label shape"
assert_contains_ci "$SKILL" "vocabulary" "SKILL ties tags to the CONVENTIONS tag vocabulary"
# Step 8: approval flips draft: to false.
assert_contains "$SKILL" "draft: false" "SKILL flips draft: to false on approval"
# Step 9: publish on command.
assert_contains_ci "$SKILL" "publish" "SKILL publishes on explicit command"
assert_contains "$SKILL" "published/" "SKILL moves the file into published/"
# Topic traceability: topic_key frontmatter + ledger append on publish.
assert_contains "$SKILL" "topic_key" "SKILL writes a topic_key frontmatter field"
assert_contains "$SKILL" "published-topics.md" "SKILL appends to the published-topics ledger on publish"
# DRAFT-first discipline: never embed the body in a question.
assert_contains_ci "$SKILL" "never embed" "SKILL warns never to embed the body in a question"

echo "== Task 2: blog-writer agent prompt =="
assert_file "$AGENT"
assert_nonempty "$AGENT"
assert_contains "$AGENT" "mode: primary" "agent declares mode: primary"
assert_contains "$AGENT" "write-blog-article" "agent loads the write-blog-article skill"
# Anti-hijack rules.
assert_contains_ci "$AGENT" "never" "agent carries a hard 'never' anti-hijack rule"
assert_contains_ci "$AGENT" "source project" "agent never edits source projects"
assert_contains_ci "$AGENT" "commit" "agent never commits"
assert_contains_ci "$AGENT" "push" "agent never pushes"
# No longer a step-01 stub. (Do not forbid the bare word "placeholder": the
# agent legitimately uses it to describe the missing/all-placeholder
# CONVENTIONS.md guard. Target the stub self-description precisely instead.)
assert_absent_ci "$AGENT" "stub" "agent no longer reads as a stub"
assert_absent_ci "$AGENT" "minimal placeholder" "agent no longer self-describes as a minimal placeholder"
assert_absent_ci "$AGENT" "step 04" "agent no longer defers its body to step 04"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
