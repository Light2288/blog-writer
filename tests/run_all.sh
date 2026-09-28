#!/usr/bin/env bash
#
# Convenience runner for the whole Blog-Writer mechanical verification suite.
#
# Runs every tests/*_check.sh in a stable order, prints each script's result,
# and exits non-zero if any script failed. A script that only reports SKIP
# lines (e.g. the opt-in live runtime cases in permission_check.sh) still exits
# 0 and is treated as a pass here.
#
# Usage: bash tests/run_all.sh   (run from anywhere)
# Exit code 0 = every check script passed; non-zero = at least one failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# Stable order: preserve the complete OpenCode suite first.
LEGACY_SCRIPTS=(
  "tests/scaffold_check.sh"
  "tests/extract_topics_check.sh"
  "tests/conventions_check.sh"
  "tests/blog_writer_check.sh"
  "tests/acceptance_check.sh"
  "tests/permission_check.sh"
  "tests/redaction_check.sh"
)

FAIL=0
declare -a RESULTS=()

run_script() {
  local s="$1"
  if [ ! -f "$s" ]; then
    printf 'MISSING: %s\n' "$s"
    RESULTS+=("MISSING  $s")
    FAIL=1
    return
  fi
  printf '\n########## %s ##########\n' "$s"
  if bash "$s"; then
    RESULTS+=("PASS     $s")
  else
    RESULTS+=("FAIL     $s")
    FAIL=1
  fi
}

for s in "${LEGACY_SCRIPTS[@]}"; do
  run_script "$s"
done

# Additive Codex checks remain offline and deterministic. The live Codex
# verifier is intentionally excluded; run it explicitly with its env gate.
run_script "tests/codex_scaffold_check.sh"

printf '\n########## npm test --prefix codex-bridge ##########\n'
if npm test --prefix codex-bridge; then
  RESULTS+=("PASS     npm test --prefix codex-bridge")
else
  RESULTS+=("FAIL     npm test --prefix codex-bridge")
  FAIL=1
fi

run_script "tests/codex_acceptance_check.sh"

printf '\n================ SUITE SUMMARY ================\n'
for r in "${RESULTS[@]}"; do
  printf '%s\n' "$r"
done

echo
if [ "$FAIL" -eq 0 ]; then
  echo "SUITE PASSED"
  exit 0
else
  echo "SUITE FAILED"
  exit 1
fi
