#!/usr/bin/env bash
# Tests for zj-worktree argument parsing and validation.
# Run: bash test.bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$REPO_ROOT/zj-worktree"
LIST_TABS="$REPO_ROOT/lib/list-tabs.sh"
MIGRATE="$REPO_ROOT/scripts/migrate-archive.sh"
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

# --- Fake archive dir helpers -------------------------------------------------
#
# mk_archive_dir creates a tmpdir to use as ARCHIVE_DIR.
# mk_entry writes a single .md file with the given frontmatter + body.
# Both die on failure; tests are best-effort and assume basic mktemp/echo work.

mk_archive_dir() {
    mktemp -d "${TMPDIR:-/tmp}/zj-worktree-archive-test-XXXXXX"
}

# mk_entry <archive-dir> <slug> <tab> <branch> <worktree> <repo> \
#          <status> <dispatched> <last_updated> [<archived>] <<<"body"
mk_entry() {
    local dir="$1" slug="$2" tab="$3" branch="$4" worktree="$5" repo="$6"
    local status="$7" dispatched="$8" last_updated="$9" archived="${10:-}"
    local body
    body="$(cat)"
    {
        echo "---"
        echo "tab: $tab"
        echo "branch: $branch"
        echo "worktree: $worktree"
        echo "repo: $repo"
        echo "status: $status"
        echo "dispatched: $dispatched"
        echo "last_updated: $last_updated"
        [[ -n "$archived" ]] && echo "archived: $archived"
        echo "---"
        echo ""
        echo "$body"
    } > "$dir/$slug.md"
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

# --repo with --dir should fail
out=$(ZELLIJ=1 "$SCRIPT" --repo /tmp --dir /tmp --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: --repo and --dir are mutually exclusive"; then
    pass "--repo with --dir is rejected"
else
    fail "--repo with --dir is rejected (got: $out)"
fi

# --repo with nonexistent path should fail
out=$(ZELLIJ=1 "$SCRIPT" --repo /tmp/nonexistent-zj-worktree-test --branch foo --tab bar 2>&1) || true
if echo "$out" | grep -q "Error: --repo path does not exist"; then
    pass "--repo with nonexistent path is rejected"
else
    fail "--repo with nonexistent path is rejected (got: $out)"
fi

# --repo pointing at a non-git directory should fail
nongit_dir=$(mktemp -d)
out=$(ZELLIJ=1 "$SCRIPT" --repo "$nongit_dir" --branch foo --tab bar 2>&1) || true
rmdir "$nongit_dir"
if echo "$out" | grep -q "Error: --repo is not a git repository"; then
    pass "--repo with non-git directory is rejected"
else
    fail "--repo with non-git directory is rejected (got: $out)"
fi

echo ""
echo "=== zj-worktree archive: argument validation ==="

# archive run outside a git repo should fail.
nongit_dir=$(mktemp -d)
out=$(cd "$nongit_dir" && ZELLIJ=1 "$SCRIPT" archive 2>&1) || true
rmdir "$nongit_dir"
if echo "$out" | grep -qi "not.*git repository\|not inside a worktree"; then
    pass "archive outside a git repo is rejected"
else
    fail "archive outside a git repo is rejected (got: $out)"
fi

# archive run from the main checkout of the repo (a worktree itself, but the
# main one) should fail — archive is meant to be run from a secondary worktree.
out=$(cd "$REPO_ROOT" && ZELLIJ=1 "$SCRIPT" archive 2>&1) || true
if echo "$out" | grep -qi "main checkout"; then
    pass "archive in main checkout is rejected"
else
    fail "archive in main checkout is rejected (got: $out)"
fi

echo ""
echo "=== zj-worktree resume: argument validation ==="

# resume without a keyword should fail.
out=$(ZELLIJ=1 "$SCRIPT" resume 2>&1) || true
if echo "$out" | grep -qi "usage\|required\|keyword"; then
    pass "resume without keyword is rejected"
else
    fail "resume without keyword is rejected (got: $out)"
fi

# resume against an empty archive dir should exit non-zero with a clear message.
empty_dir=$(mk_archive_dir)
out=$(ZELLIJ=1 ARCHIVE_DIR="$empty_dir" "$SCRIPT" resume nothing --no-dispatch 2>&1) || true
rmdir "$empty_dir"
if echo "$out" | grep -qi "no matching archive entry\|no match"; then
    pass "resume with no matches exits with clear message"
else
    fail "resume with no matches exits with clear message (got: $out)"
fi

# resume with a unique match should print the entry it would dispatch.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-foo-bar" "foo-bar" "hazel/foo/bar" "/tmp/zjwt-fake/hazel-foo-bar" "hound" archived 2026-04-01 2026-05-01 2026-05-01 <<<"Body about foo-bar work."
mk_entry "$dir" "hound-baz" "baz" "hazel/baz/work" "/tmp/zjwt-fake/hazel-baz-work" "hound" archived 2026-04-02 2026-05-02 2026-05-02 <<<"Body about something else entirely."
out=$(ZELLIJ=1 ARCHIVE_DIR="$dir" "$SCRIPT" resume foo-bar --no-dispatch 2>&1) || true
rm -rf "$dir"
if echo "$out" | grep -q "hazel/foo/bar"; then
    pass "resume with unique match resolves to the right entry"
else
    fail "resume with unique match resolves to the right entry (got: $out)"
fi

# resume with multiple matches should exit non-zero and list candidates.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-foo-one"  "foo-one" "hazel/foo/one"  "/tmp/zjwt-fake/hazel-foo-one"  "hound" archived 2026-04-01 2026-05-01 2026-05-01 <<<"foo one"
mk_entry "$dir" "hound-foo-two"  "foo-two" "hazel/foo/two"  "/tmp/zjwt-fake/hazel-foo-two"  "hound" archived 2026-04-02 2026-05-02 2026-05-02 <<<"foo two"
out=$(ZELLIJ=1 ARCHIVE_DIR="$dir" "$SCRIPT" resume foo --no-dispatch 2>&1) || true
rc=0
ZELLIJ=1 ARCHIVE_DIR="$dir" "$SCRIPT" resume foo --no-dispatch >/dev/null 2>&1 || rc=$?
rm -rf "$dir"
if (( rc == 2 )) && echo "$out" | grep -q "hazel/foo/one" && echo "$out" | grep -q "hazel/foo/two"; then
    pass "resume with multiple matches exits 2 with both candidates"
else
    fail "resume with multiple matches exits 2 with both candidates (rc=$rc, got: $out)"
fi

echo ""
echo "=== lib/list-tabs.sh ==="

# Empty archive dir produces no entries, exits 0.
dir=$(mk_archive_dir)
out=$(ARCHIVE_DIR="$dir" "$LIST_TABS" 2>&1) || true
rc=0
ARCHIVE_DIR="$dir" "$LIST_TABS" >/dev/null 2>&1 || rc=$?
rmdir "$dir"
if (( rc == 0 )) && [[ -z "$out" ]]; then
    pass "list-tabs: empty dir → empty output, exit 0"
else
    fail "list-tabs: empty dir → empty output, exit 0 (rc=$rc, got: $out)"
fi

# Two entries are listed sorted by last_updated descending.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-older" "older" "hazel/older" "/tmp/zjwt-fake/hazel-older" "hound" archived 2026-04-01 2026-04-10 2026-04-10 <<<"older work"
mk_entry "$dir" "hound-newer" "newer" "hazel/newer" "/tmp/zjwt-fake/hazel-newer" "hound" archived 2026-04-05 2026-05-15 2026-05-15 <<<"newer work"
out=$(ARCHIVE_DIR="$dir" "$LIST_TABS" 2>&1) || true
rm -rf "$dir"
first_line=$(echo "$out" | head -1)
second_line=$(echo "$out" | sed -n 2p)
if echo "$first_line" | grep -q "hazel/newer" && echo "$second_line" | grep -q "hazel/older"; then
    pass "list-tabs: sorts by last_updated descending"
else
    fail "list-tabs: sorts by last_updated descending (got: $out)"
fi

# --status active filters out archived entries.
# Use a real worktree path for the active entry so the reaper doesn't flip it.
dir=$(mk_archive_dir)
wt=$(mktemp -d)
mk_entry "$dir" "hound-a" "a" "hazel/a" "$wt"               "hound" active   2026-04-01 2026-05-01 <<<"active entry"
mk_entry "$dir" "hound-b" "b" "hazel/b" "/tmp/zjwt-fake/b" "hound" archived 2026-04-02 2026-05-02 2026-05-02 <<<"archived entry"
out=$(ARCHIVE_DIR="$dir" "$LIST_TABS" --status active 2>&1) || true
rm -rf "$dir" "$wt"
if echo "$out" | grep -q "hazel/a" && ! echo "$out" | grep -q "hazel/b"; then
    pass "list-tabs: --status active filters to active only"
else
    fail "list-tabs: --status active filters to active only (got: $out)"
fi

# --status archived filters out active entries.
dir=$(mk_archive_dir)
wt=$(mktemp -d)
mk_entry "$dir" "hound-a" "a" "hazel/a" "$wt"               "hound" active   2026-04-01 2026-05-01 <<<"active entry"
mk_entry "$dir" "hound-b" "b" "hazel/b" "/tmp/zjwt-fake/b" "hound" archived 2026-04-02 2026-05-02 2026-05-02 <<<"archived entry"
out=$(ARCHIVE_DIR="$dir" "$LIST_TABS" --status archived 2>&1) || true
rm -rf "$dir" "$wt"
if echo "$out" | grep -q "hazel/b" && ! echo "$out" | grep -q "hazel/a"; then
    pass "list-tabs: --status archived filters to archived only"
else
    fail "list-tabs: --status archived filters to archived only (got: $out)"
fi

# --limit N caps the number of entries.
dir=$(mk_archive_dir)
for i in 1 2 3; do
    mk_entry "$dir" "hound-e$i" "e$i" "hazel/e$i" "/tmp/zjwt-fake/e$i" "hound" archived 2026-04-0$i 2026-05-0$i 2026-05-0$i <<<"entry $i"
done
out=$(ARCHIVE_DIR="$dir" "$LIST_TABS" --limit 2 2>&1) || true
rm -rf "$dir"
line_count=$(echo "$out" | wc -l | tr -d ' ')
if (( line_count == 2 )); then
    pass "list-tabs: --limit N caps output"
else
    fail "list-tabs: --limit N caps output (got $line_count lines: $out)"
fi

# Reaper: active entry whose worktree path doesn't exist gets flipped to archived.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-zombie" "zombie" "hazel/zombie" "/tmp/zjwt-this-path-must-not-exist-$$" "hound" active 2026-04-01 2026-05-01 <<<"zombie body"
ARCHIVE_DIR="$dir" "$LIST_TABS" >/dev/null 2>&1 || true
status_line=$(grep '^status:' "$dir/hound-zombie.md" 2>/dev/null || echo "")
rm -rf "$dir"
if echo "$status_line" | grep -q "archived"; then
    pass "list-tabs: reaper flips zombie active entry to archived"
else
    fail "list-tabs: reaper flips zombie active entry to archived (got: $status_line)"
fi

# Reaper: active entry whose worktree path exists is left as active.
dir=$(mk_archive_dir)
existing_wt=$(mktemp -d)
mk_entry "$dir" "hound-live" "live" "hazel/live" "$existing_wt" "hound" active 2026-04-01 2026-05-01 <<<"live body"
ARCHIVE_DIR="$dir" "$LIST_TABS" >/dev/null 2>&1 || true
status_line=$(grep '^status:' "$dir/hound-live.md" 2>/dev/null || echo "")
rm -rf "$dir" "$existing_wt"
if echo "$status_line" | grep -q "active"; then
    pass "list-tabs: reaper leaves live active entry alone"
else
    fail "list-tabs: reaper leaves live active entry alone (got: $status_line)"
fi

echo ""
echo "=== scripts/migrate-archive.sh ==="

# Entry with no status: gets status: archived + last_updated copied from archived:.
dir=$(mk_archive_dir)
cat > "$dir/hound-legacy.md" <<'LEGACY'
---
tab: legacy
branch: hazel/legacy
worktree: /tmp/zjwt-fake/legacy
repo: hound
archived: 2026-04-10
---

Legacy body.
LEGACY
ARCHIVE_DIR="$dir" "$MIGRATE" >/dev/null 2>&1 || true
content=$(cat "$dir/hound-legacy.md")
rm -rf "$dir"
if echo "$content" | grep -q "^status: archived$" && echo "$content" | grep -q "^last_updated: 2026-04-10$"; then
    pass "migrate: legacy entry gets status + last_updated injected"
else
    fail "migrate: legacy entry gets status + last_updated injected (got: $content)"
fi

# Entry with status: archived already is left untouched.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-already" "already" "hazel/already" "/tmp/zjwt-fake/already" "hound" archived 2026-04-01 2026-05-01 2026-05-01 <<<"already migrated"
before=$(cat "$dir/hound-already.md")
ARCHIVE_DIR="$dir" "$MIGRATE" >/dev/null 2>&1 || true
after=$(cat "$dir/hound-already.md")
rm -rf "$dir"
if [[ "$before" == "$after" ]]; then
    pass "migrate: already-migrated entry is untouched"
else
    fail "migrate: already-migrated entry is untouched (diff present)"
fi

# Idempotency: running twice == running once.
dir=$(mk_archive_dir)
cat > "$dir/hound-legacy.md" <<'LEGACY'
---
tab: legacy
branch: hazel/legacy
worktree: /tmp/zjwt-fake/legacy
repo: hound
archived: 2026-04-10
---

Legacy body.
LEGACY
ARCHIVE_DIR="$dir" "$MIGRATE" >/dev/null 2>&1 || true
once=$(cat "$dir/hound-legacy.md")
ARCHIVE_DIR="$dir" "$MIGRATE" >/dev/null 2>&1 || true
twice=$(cat "$dir/hound-legacy.md")
rm -rf "$dir"
if [[ "$once" == "$twice" ]]; then
    pass "migrate: idempotent"
else
    fail "migrate: idempotent (got diff)"
fi

# INDEX.md is removed at end.
dir=$(mk_archive_dir)
echo "# Archive Index" > "$dir/INDEX.md"
ARCHIVE_DIR="$dir" "$MIGRATE" >/dev/null 2>&1 || true
exists=1
[[ ! -e "$dir/INDEX.md" ]] && exists=0
rm -rf "$dir"
if (( exists == 0 )); then
    pass "migrate: INDEX.md is removed"
else
    fail "migrate: INDEX.md is removed"
fi

echo ""
echo "=== agent-friendliness: SIGPIPE + result lines ==="

# `zj-worktree list | head -1` should exit 0, not 141 (SIGPIPE). Use enough
# entries that awk's output overflows the pipe buffer, forcing multiple
# writes — otherwise the first write may flush everything before head closes
# and the bug doesn't trigger.
dir=$(mk_archive_dir)
for i in $(seq 1 2000); do
    mk_entry "$dir" "hound-e$i" "e$i" "hazel/longish-branch-name-for-bulk-$i" \
        "/tmp/zjwt-fake/e$i-some-long-path-here" "hound" archived \
        2026-04-01 2026-05-01 2026-05-01 <<<"entry $i body lorem ipsum dolor sit amet"
done
ARCHIVE_DIR="$dir" "$SCRIPT" list 2>/dev/null | head -1 >/dev/null || true
rc=${PIPESTATUS[0]}
rm -rf "$dir"
if (( rc == 0 )); then
    pass "list piped into head -1 exits 0 (SIGPIPE tolerated)"
else
    fail "list piped into head -1 exits 0 (SIGPIPE tolerated) (rc=$rc)"
fi

# `zj-worktree list` (TTY-style invocation, no closed pipe) should still emit
# the entries normally — broken-pipe tolerance shouldn't swallow real output.
dir=$(mk_archive_dir)
mk_entry "$dir" "hound-a" "a" "hazel/a" "/tmp/zjwt-fake/a" "hound" archived 2026-04-01 2026-05-01 2026-05-01 <<<"entry a"
mk_entry "$dir" "hound-b" "b" "hazel/b" "/tmp/zjwt-fake/b" "hound" archived 2026-04-02 2026-05-02 2026-05-02 <<<"entry b"
out=$(ARCHIVE_DIR="$dir" "$SCRIPT" list 2>&1) || true
rm -rf "$dir"
if echo "$out" | grep -q "hazel/a" && echo "$out" | grep -q "hazel/b"; then
    pass "list still emits all entries when not piped"
else
    fail "list still emits all entries when not piped (got: $out)"
fi

# archive on a non-main worktree path that has no live zellij tab should
# still emit a `result: archived ...` line on stdout, as the last line.
# We invoke archive against a fake worktree by creating a tiny git repo,
# adding a worktree to it, and running archive from that worktree.
maintmp=$(mktemp -d)
(
    cd "$maintmp"
    git init -q
    git commit -q --allow-empty -m "init"
    git worktree add -q -b test-archive-branch wt-test >/dev/null 2>&1
)
adir=$(mk_archive_dir)
out=$(cd "$maintmp/wt-test" && ZELLIJ=1 ARCHIVE_DIR="$adir" "$SCRIPT" archive 2>&1 <<<"test body" || true)
last_line=$(echo "$out" | grep '^result: ' | tail -1)
# Cleanup
git -C "$maintmp" worktree remove -f wt-test 2>/dev/null || true
rm -rf "$maintmp" "$adir"
if echo "$last_line" | grep -q "^result: archived "; then
    pass "archive emits result: archived line on stdout"
else
    fail "archive emits result: archived line on stdout (got last result line: '$last_line', full: $out)"
fi

# Progress `◎` glyphs should not leak onto a captured (non-TTY) stderr.
# We can't exercise --branch end-to-end here (it needs wt/zellij), but
# `progress` is a top-level helper — invoke it via a short subshell that
# sources the script's helper conditionally. The simpler check: run a
# command whose ◎ output would otherwise appear (we don't have one that
# stays inside validation), so verify via direct call instead.
out=$( "$SCRIPT" --help 2>&1 )
if ! echo "$out" | grep -q "◎"; then
    pass "no ◎ glyphs in --help output"
else
    fail "no ◎ glyphs in --help output (got: $out)"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All $tests tests passed."
else
    echo "$failures/$tests tests failed."
    exit 1
fi
