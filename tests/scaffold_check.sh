#!/usr/bin/env bash
#
# Scaffold verification for step 01 — Project Scaffold & Permissions.
#
# Asserts every acceptance criterion from
# specs/steps/01-project-scaffold-and-permissions.md that is checkable
# statically (file existence, content, and opencode.json structure).
#
# Runtime-only criteria (opencode actually enforcing the permission
# boundary, agent selectability after restart) are documented in the plan's
# Verification section and cannot be asserted from a shell script; this
# script asserts the *config* that drives them.
#
# Usage: bash tests/scaffold_check.sh   (run from the project root)
# Exit code 0 = all checks pass; non-zero = at least one failure.

set -u

# Resolve project root as the parent of this script's tests/ directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_dir()  { if [ -d "$1" ]; then pass "dir exists: $1"; else fail "dir missing: $1"; fi; }
assert_file() { if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi; }

assert_nonempty() {
  if [ -s "$1" ]; then pass "file non-empty: $1"; else fail "file empty/missing: $1"; fi
}

# assert_contains <file> <substring> <label>
assert_contains() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (expected '$2' in $1)"
  fi
}

echo "== Task 1: directory skeleton + allowlist =="
assert_dir inputs
assert_dir drafts
assert_dir published
assert_file inputs/.gitkeep
assert_file drafts/.gitkeep
assert_file published/.gitkeep
assert_file tracked-projects.txt
# tracked-projects.txt must contain ONLY comment/blank lines (no real paths).
if [ -f tracked-projects.txt ]; then
  if grep -vE '^\s*(#.*)?$' tracked-projects.txt >/dev/null 2>&1; then
    fail "tracked-projects.txt contains non-comment lines (should be comments only)"
  else
    pass "tracked-projects.txt contains only comment/blank lines"
  fi
fi

echo "== Task 2: placeholder CONVENTIONS.md =="
assert_file CONVENTIONS.md
assert_nonempty CONVENTIONS.md
assert_contains CONVENTIONS.md "placeholder" "CONVENTIONS.md marked as placeholder/stub"

echo "== Task 3: AGENTS.md + README.md =="
assert_file AGENTS.md
assert_nonempty AGENTS.md
assert_contains AGENTS.md "topic-extractor" "AGENTS.md mentions topic-extractor"
assert_contains AGENTS.md "blog-writer" "AGENTS.md mentions blog-writer"
assert_file README.md
assert_nonempty README.md
assert_contains README.md 'sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"' \
  "README.md documents the DB prereq check command"
assert_contains README.md "restart" "README.md mentions restarting opencode"
assert_contains README.md "OPENCODE_DISABLE_PROJECT_CONFIG" \
  "README.md documents the config escape hatch"
assert_contains README.md "tracked-projects.txt" "README.md mentions the optional allowlist"

echo "== Task 4: agent stubs =="
assert_file .opencode/agents/topic-extractor.md
assert_nonempty .opencode/agents/topic-extractor.md
assert_contains .opencode/agents/topic-extractor.md "primary" \
  "topic-extractor stub declares mode: primary"
assert_file .opencode/agents/blog-writer.md
assert_nonempty .opencode/agents/blog-writer.md
assert_contains .opencode/agents/blog-writer.md "primary" \
  "blog-writer stub declares mode: primary"

echo "== Task 5/6: opencode.json permissions + external_directory =="
assert_file .opencode/opencode.json
if [ -f .opencode/opencode.json ]; then
  python3 - <<'PY'
import json, sys

FAIL = False
def pass_(m): print("PASS: " + m)
def fail_(m):
    global FAIL
    print("FAIL: " + m)
    FAIL = True

with open(".opencode/opencode.json") as f:
    try:
        cfg = json.load(f)
        pass_("opencode.json is valid JSON")
    except Exception as e:
        print("FAIL: opencode.json is not valid JSON: %s" % e)
        sys.exit(1)

if cfg.get("$schema") == "https://opencode.ai/config.json":
    pass_("$schema declared correctly")
else:
    fail_("$schema missing or wrong")

agent = cfg.get("agent", {})

def rule_action(rules, pattern):
    """Return the action a last-match-wins object assigns to an exact pattern key."""
    if isinstance(rules, str):
        return rules
    if isinstance(rules, dict):
        return rules.get(pattern)
    return None

def check_edit(name, allowed, must_default_deny=True):
    perm = agent.get(name, {}).get("permission", {})
    edit = perm.get("edit")
    if edit is None:
        fail_("%s: edit permission missing" % name); return
    if isinstance(edit, dict):
        # default deny expressed via "**": "deny" (or a bare string form handled below)
        default = edit.get("**") or edit.get("*")
        if must_default_deny and default != "deny":
            fail_("%s: edit lacks default deny (** => deny)" % name)
        else:
            pass_("%s: edit default-denies" % name)
        for a in allowed:
            if edit.get(a) == "allow":
                pass_("%s: edit allows %s" % (name, a))
            else:
                fail_("%s: edit does not allow %s" % (name, a))
        # ensure nothing outside 'allowed' is allowed
        extra = [k for k, v in edit.items()
                 if v == "allow" and k not in allowed]
        if extra:
            fail_("%s: edit allows unexpected paths: %s" % (name, extra))
        else:
            pass_("%s: edit allows nothing outside the intended set" % name)
    else:
        fail_("%s: edit is not an object rule" % name)

def check_bash(name, extra_allows=()):
    perm = agent.get(name, {}).get("permission", {})
    bash = perm.get("bash")
    if not isinstance(bash, dict):
        fail_("%s: bash permission missing/not an object" % name); return
    def has_allow(sub):
        return any(k for k, v in bash.items() if v == "allow" and sub in k)
    def has_deny(sub):
        return any(k for k, v in bash.items() if v == "deny" and sub in k)
    for label, sub in (("git *", "git "), ("sqlite3 -readonly", "sqlite3")):
        if has_allow(sub): pass_("%s: bash allows %s" % (name, label))
        else: fail_("%s: bash does not allow %s" % (name, label))
    for label, sub in (("git push", "git push"),
                       ("git commit --amend", "git commit --amend"),
                       ("rm -rf", "rm -rf")):
        if has_deny(sub): pass_("%s: bash denies %s" % (name, label))
        else: fail_("%s: bash does not deny %s" % (name, label))
    for sub in extra_allows:
        if has_allow(sub): pass_("%s: bash allows %s" % (name, sub))
        else: fail_("%s: bash does not allow %s" % (name, sub))

check_edit("topic-extractor", ["inputs/**"])
check_edit("blog-writer", ["drafts/**", "inputs/**", "published/**"])
check_bash("topic-extractor")
check_bash("blog-writer", extra_allows=["mv drafts"])

# read allow anywhere for both
for name in ("topic-extractor", "blog-writer"):
    perm = agent.get(name, {}).get("permission", {})
    read = perm.get("read")
    if read == "allow" or (isinstance(read, dict) and (read.get("**") == "allow" or read.get("*") == "allow")):
        pass_("%s: read allows anywhere" % name)
    else:
        fail_("%s: read does not allow anywhere" % name)

# external_directory: allow ~/** + DB dir, deny sensitive set
def find_ext():
    # may live at top-level permission or per-agent permission
    tops = cfg.get("permission", {})
    if isinstance(tops, dict) and "external_directory" in tops:
        return tops["external_directory"]
    for name in ("topic-extractor", "blog-writer"):
        p = agent.get(name, {}).get("permission", {})
        if isinstance(p, dict) and "external_directory" in p:
            return p["external_directory"]
    return None

ext = find_ext()
if not isinstance(ext, dict):
    fail_("external_directory missing or not an object rule")
else:
    allow_keys = [k for k, v in ext.items() if v == "allow"]
    deny_keys = [k for k, v in ext.items() if v == "deny"]
    if any(k.startswith("~") or k.startswith("/Users") or "**" in k for k in allow_keys):
        pass_("external_directory has a broad home allow")
    else:
        fail_("external_directory lacks a broad home allow")
    for d in ("~/.ssh/**", "~/.aws/**", "~/.gnupg/**", "~/.config/**", "**/.env"):
        if d in deny_keys:
            pass_("external_directory denies %s" % d)
        else:
            fail_("external_directory does not deny %s" % d)

sys.exit(1 if FAIL else 0)
PY
  if [ $? -ne 0 ]; then FAIL=1; fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
