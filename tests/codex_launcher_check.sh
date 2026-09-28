#!/usr/bin/env bash
# Deterministic behavior checks for the command-scoped Codex launcher.

set -u

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LAUNCHER="$ROOT/bin/blog-writer-codex"
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

if [ ! -f "$LAUNCHER" ]; then
  fail "launcher exists: bin/blog-writer-codex"
  exit 1
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/blog-writer-launcher.XXXXXX")"
CAPTURE="$SCRATCH/capture"
FAKE_BIN="$SCRATCH/fake-bin"
mkdir -p "$CAPTURE" "$FAKE_BIN"

cleanup() {
  rm -r -- "$SCRATCH"
}
trap cleanup EXIT HUP INT TERM

cat > "$FAKE_BIN/codex" <<'SH'
#!/bin/bash
printf '%s\n' "$PWD" > "$CAPTURE_DIR/cwd"
: > "$CAPTURE_DIR/args"
for arg in "$@"; do
  printf '%s\0' "$arg" >> "$CAPTURE_DIR/args"
done
: > "$CAPTURE_DIR/launched"
exit "${FAKE_CODEX_EXIT:-0}"
SH
chmod +x "$FAKE_BIN/codex"
ln -s "$(command -v node)" "$FAKE_BIN/node"

reset_capture() {
  rm -f "$CAPTURE/args" "$CAPTURE/cwd" "$CAPTURE/launched"
}

expect_prelaunch_failure() {
  local label="$1" expected="$2"
  shift 2
  reset_capture
  local output status
  output="$("$@" 2>&1)"
  status=$?
  if [ "$status" -ne 0 ] && [[ "$output" == *"$expected"* ]] && [ ! -e "$CAPTURE/launched" ]; then
    pass "$label"
  else
    fail "$label (status=$status output=$output)"
  fi
}

expect_usage_failure() {
  local label="$1"
  shift
  reset_capture
  local output status
  output="$(PATH="$FAKE_BIN:$PATH" CAPTURE_DIR="$CAPTURE" /bin/bash "$LAUNCHER" "$@" 2>&1)"
  status=$?
  if [ "$status" -ne 0 ] &&
     [[ "$output" == *'blog-writer-codex topics [time-window words...]'* ]] &&
     [[ "$output" == *'blog-writer-codex article <topic reference or free-text subject...>'* ]] &&
     [ ! -e "$CAPTURE/launched" ]; then
    pass "$label"
  else
    fail "$label (status=$status output=$output)"
  fi
}

run_capture() {
  reset_capture
  PATH="$FAKE_BIN:$PATH" CAPTURE_DIR="$CAPTURE" /bin/bash "$LAUNCHER" "$@"
}

validate_capture() {
  local mode="$1" prompt_fragment="$2" prompt_data="${3:-}"
  python3 - "$CAPTURE/args" "$CAPTURE/cwd" "$ROOT" "$mode" "$prompt_fragment" "$prompt_data" <<'PY'
import pathlib
import sys

args_path, cwd_path, root, mode, prompt_fragment, prompt_data = sys.argv[1:]
args = pathlib.Path(args_path).read_bytes().split(b"\0")
if args[-1] == b"":
    args.pop()
args = [value.decode("utf-8") for value in args]

profile = "topic" if mode == "topics" else "writer"
skill = "extract-topics" if mode == "topics" else "write-blog-article"
expected = [
    "--no-daemon",
    "--strict-config",
    "--sandbox",
    "read-only",
    "--cd",
    root,
    "-c",
    'mcp_servers.blog_writer_bridge.command="node"',
    "-c",
    f'mcp_servers.blog_writer_bridge.args=["codex-bridge/src/server.mjs","--profile","{profile}"]',
]
assert args[:10] == expected, (args, expected)
assert len(args) == 11, args
prompt = args[10]
assert skill in prompt
assert "command-scoped mode" in prompt
assert "Do not delegate to a custom agent" in prompt
assert prompt_fragment in prompt
if prompt_data:
    assert prompt_data in prompt
assert "--model" not in args
assert "--ephemeral" not in args
other = "writer" if profile == "topic" else "topic"
assert f'"--profile","{other}"' not in "\n".join(args[:10])
assert pathlib.Path(cwd_path).read_text(encoding="utf-8").strip() == root
PY
}

make_fixture() {
  local name="$1" include_entrypoint="$2" include_sdk="$3"
  local fixture="$SCRATCH/$name"
  mkdir -p "$fixture/bin" "$fixture/codex-bridge/src"
  cp "$LAUNCHER" "$fixture/bin/blog-writer-codex"
  chmod +x "$fixture/bin/blog-writer-codex"
  if [ "$include_entrypoint" = "yes" ]; then
    : > "$fixture/codex-bridge/src/server.mjs"
  fi
  if [ "$include_sdk" = "yes" ]; then
    mkdir -p "$fixture/codex-bridge/node_modules/@modelcontextprotocol/sdk"
  fi
  printf '%s\n' "$fixture"
}

expect_usage_failure "missing subcommand fails before launch"
expect_usage_failure "unknown subcommand fails before launch" unsupported
expect_usage_failure "missing article subject fails before launch" article

ONLY_CODEX="$SCRATCH/only-codex"
mkdir -p "$ONLY_CODEX"
ln -s "$FAKE_BIN/codex" "$ONLY_CODEX/codex"
expect_prelaunch_failure \
  "missing node reports an actionable prerequisite" \
  "Node.js 'node' was not found on PATH" \
  env PATH="$ONLY_CODEX" CAPTURE_DIR="$CAPTURE" /bin/bash "$LAUNCHER" topics

ONLY_NODE="$SCRATCH/only-node"
mkdir -p "$ONLY_NODE"
ln -s "$FAKE_BIN/node" "$ONLY_NODE/node"
expect_prelaunch_failure \
  "missing Codex reports an actionable prerequisite" \
  "Codex CLI 'codex' was not found on PATH" \
  env PATH="$ONLY_NODE" CAPTURE_DIR="$CAPTURE" /bin/bash "$LAUNCHER" topics

NO_ENTRYPOINT="$(make_fixture no-entrypoint no yes)"
expect_prelaunch_failure \
  "missing bridge entrypoint fails before launch" \
  "bridge entrypoint is missing" \
  env PATH="$FAKE_BIN" CAPTURE_DIR="$CAPTURE" /bin/bash "$NO_ENTRYPOINT/bin/blog-writer-codex" topics

NO_SDK="$(make_fixture no-sdk yes no)"
expect_prelaunch_failure \
  "missing bridge dependencies fail before launch" \
  "bridge dependencies are missing; run npm install --prefix codex-bridge" \
  env PATH="$FAKE_BIN" CAPTURE_DIR="$CAPTURE" /bin/bash "$NO_SDK/bin/blog-writer-codex" topics

if run_capture topics; then
  validate_capture topics "seven-day default" && pass "topics defaults to seven days with the topic profile" || fail "topics default invocation is invalid"
else
  fail "topics default invocation exits zero"
fi

if run_capture topics last week; then
  validate_capture topics "Requested time window (user data): last week" "last week" && pass "topics carries the requested window only as prompt data" || fail "topics window invocation is invalid"
else
  fail "topics window invocation exits zero"
fi

if run_capture article topic 2; then
  validate_capture article "Requested article subject (user data): topic 2" "topic 2" && pass "article uses only the writer profile" || fail "article invocation is invalid"
else
  fail "article invocation exits zero"
fi

ADVERSARIAL=$'quote " line\n$(touch should-not-exist) --profile writer mcp_servers.blog_writer_bridge.args=["evil"]'
if (cd "$SCRATCH" && run_capture topics "$ADVERSARIAL"); then
  if validate_capture topics "Requested time window (user data):" "$ADVERSARIAL" && [ ! -e "$SCRATCH/should-not-exist" ]; then
    pass "adversarial window text cannot alter argv or execute shell text"
  else
    fail "adversarial window text escaped the prompt argument"
  fi
else
  fail "adversarial window invocation exits zero"
fi

ALIAS_DIR="$SCRATCH/external-alias"
mkdir -p "$ALIAS_DIR"
ln -s "$LAUNCHER" "$ALIAS_DIR/blog-writer-codex"
reset_capture
if PATH="$FAKE_BIN:$PATH" CAPTURE_DIR="$CAPTURE" /bin/bash "$ALIAS_DIR/blog-writer-codex" topics; then
  validate_capture topics "seven-day default" && pass "external launcher symlink resolves the canonical repository root" || fail "external launcher symlink used the wrong repository root"
else
  fail "external launcher symlink starts the workflow"
fi

reset_capture
PATH="$FAKE_BIN:$PATH" CAPTURE_DIR="$CAPTURE" FAKE_CODEX_EXIT=23 /bin/bash "$LAUNCHER" topics >/dev/null 2>&1
status=$?
if [ "$status" -eq 23 ]; then
  pass "launcher propagates the Codex exit status"
else
  fail "launcher returned $status instead of Codex exit 23"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "ALL LAUNCHER CHECKS PASSED"
  exit 0
fi

echo "LAUNCHER CHECKS FAILED"
exit 1
