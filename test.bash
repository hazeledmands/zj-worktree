#!/usr/bin/env bash
# Tests for zj-worktree argument parsing and validation.
# Run: bash test.bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/zj-worktree"
failures=0
tests=0

pass() { tests=$((tests + 1)); echo "  PASS: $1"; }
fail() { tests=$((tests + 1)); failures=$((failures + 1)); echo "  FAIL: $1"; }

run() {
    # Run the script, capturing stdout+stderr and exit code.
    local out
    out=$("$SCRIPT" "$@" 2>&1) || true
    echo "$out"
}

echo "=== Argument parsing & validation ==="

# --help should print usage and exit 0
out=$(run --help)
if echo "$out" | grep -q "Usage:"; then
    pass "--help prints usage"
else
    fail "--help prints usage"
fi

# Missing --tab should fail
out=$(run --branch foo 2>&1) || true
if echo "$out" | grep -q "Error: --tab is required"; then
    pass "missing --tab is rejected"
else
    fail "missing --tab is rejected (got: $out)"
fi

# Missing --branch, --pr, and --dir should fail
out=$(run --tab mytab 2>&1) || true
if echo "$out" | grep -q "Error: one of --branch, --pr, or --dir is required"; then
    pass "missing --branch, --pr, and --dir is rejected"
else
    fail "missing --branch, --pr, and --dir is rejected (got: $out)"
fi

# --base without --branch should fail
out=$(ZELLIJ=1 "$SCRIPT" --pr 42 --base foo --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: --base is only valid with --branch"; then
    pass "--base with --pr is rejected"
else
    fail "--base with --pr is rejected (got: $out)"
fi

out=$(ZELLIJ=1 "$SCRIPT" --dir /tmp --base foo --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: --base is only valid with --branch"; then
    pass "--base with --dir is rejected"
else
    fail "--base with --dir is rejected (got: $out)"
fi

# Unknown option should fail
out=$(run --bogus 2>&1) || true
if echo "$out" | grep -q "Error: unknown option: --bogus"; then
    pass "unknown option is rejected"
else
    fail "unknown option is rejected (got: $out)"
fi

# Not inside zellij should fail (ZELLIJ env var unset)
out=$(ZELLIJ="" "$SCRIPT" --branch foo --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: not inside a zellij session"; then
    pass "not inside zellij is rejected"
else
    fail "not inside zellij is rejected (got: $out)"
fi

# --dir with nonexistent directory should fail
out=$(ZELLIJ=1 "$SCRIPT" --dir /tmp/nonexistent-zj-worktree-test --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: directory does not exist"; then
    pass "--dir with nonexistent directory is rejected"
else
    fail "--dir with nonexistent directory is rejected (got: $out)"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All $tests tests passed."
else
    echo "$failures/$tests tests failed."
    exit 1
fi
