#!/usr/bin/env bash
# list-tabs.sh — Walk archive entries, run the reaper, emit sorted TSV.
#
# Usage: list-tabs.sh [--status active|archived] [--limit N]
#   ARCHIVE_DIR (env) overrides ~/.claude/archive.
#
# For each .md file (skip INDEX.md):
#   - Parse frontmatter.
#   - If status=active AND `worktree:` path is missing on disk: flip
#     status to archived, stamp `archived:` + `last_updated:` to today.
#     (In-place rewrite.)
#
# TSV columns:
#   status<TAB>last_updated<TAB>repo<TAB>branch<TAB>tab<TAB>worktree<TAB>hook
#
# Sorted by last_updated descending. Hook = first non-blank body line,
# truncated to 140 chars.
#
# Exit codes:
#   0 — success (possibly empty output)
#   2 — bad usage

set -euo pipefail

archive_dir="${ARCHIVE_DIR:-$HOME/.claude/archive}"
status_filter=""
limit=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) status_filter="$2"; shift 2 ;;
        --limit)  limit="$2"; shift 2 ;;
        -h|--help)
            echo "usage: list-tabs.sh [--status active|archived] [--limit N]"
            exit 0
            ;;
        *) echo "list-tabs: unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -d "$archive_dir" ]]; then
    exit 0
fi

today="$(date +%Y-%m-%d)"

parse_field() {
    # parse_field <file> <key> — print the first "<key>: ..." line, stripped of
    # the key prefix, or nothing if absent. Pure bash builtins by design: the
    # naive `sed -n ... | head -1` form forks two procs per call, and this is
    # called ~8x per entry inside the emit loop — so on a 500-entry archive
    # the fork cost alone is multiple seconds.
    local line key="$2"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$key: "* ]]; then
            printf '%s\n' "${line#"$key: "}"
            return
        fi
    done < "$1"
}

reap_entry() {
    # reap_entry <file> — if status=active and worktree missing, flip in place.
    local file="$1"
    local status
    status="$(parse_field "$file" status)"
    [[ "$status" == "active" ]] || return 0
    local worktree
    worktree="$(parse_field "$file" worktree)"
    [[ -n "$worktree" && ! -d "$worktree" ]] || return 0

    local tmp
    tmp="$(mktemp)"
    awk -v today="$today" '
        BEGIN { state = 0; saw_archived = 0; saw_last_updated = 0 }
        # state: 0 = before frontmatter, 1 = inside, 2 = after.
        state == 0 && /^---$/ { state = 1; print; next }
        state == 1 && /^---$/ {
            # Closing frontmatter — inject any missing fields before ---.
            if (!saw_archived) print "archived: " today
            if (!saw_last_updated) print "last_updated: " today
            state = 2
            print
            next
        }
        state == 1 && /^status:/       { print "status: archived"; next }
        state == 1 && /^archived:/     { print "archived: " today; saw_archived = 1; next }
        state == 1 && /^last_updated:/ { print "last_updated: " today; saw_last_updated = 1; next }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

extract_hook() {
    # First non-blank body line (any non-whitespace content), truncated to 140
    # chars. Pure bash builtins — same fork-cost concern as parse_field.
    local line state=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$state" in
            0) [[ "$line" == "---" ]] && state=1 ;;
            1) [[ "$line" == "---" ]] && state=2 ;;
            2)
                if [[ "$line" == *[![:space:]]* ]]; then
                    printf '%s' "${line:0:140}"
                    return
                fi
                ;;
        esac
    done < "$1"
}

# Pass 1: reap each entry in place.
shopt -s nullglob
entries=()
for f in "$archive_dir"/*.md; do
    [[ "$(basename "$f")" == "INDEX.md" ]] && continue
    reap_entry "$f"
    entries+=("$f")
done

(( ${#entries[@]} == 0 )) && exit 0

# Pass 2: emit sorted, filtered, limited TSV.
{
    for f in "${entries[@]}"; do
        status="$(parse_field "$f" status)"
        archived="$(parse_field "$f" archived)"
        last_updated="$(parse_field "$f" last_updated)"
        # Legacy fallback: pre-migration entries had only `archived:`. Treat
        # them as archived (their original meaning) so filters + sort work.
        [[ -z "$status" && -n "$archived" ]] && status="archived"
        [[ -z "$last_updated" && -n "$archived" ]] && last_updated="$archived"

        repo="$(parse_field "$f" repo)"
        branch="$(parse_field "$f" branch)"
        tab="$(parse_field "$f" tab)"
        worktree="$(parse_field "$f" worktree)"
        hook="$(extract_hook "$f")"
        if [[ -n "$status_filter" && "$status" != "$status_filter" ]]; then
            continue
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$status" "$last_updated" "$repo" "$branch" "$tab" "$worktree" "$hook"
    done
} | sort -t$'\t' -k2,2r | { if [[ -n "$limit" ]]; then head -n "$limit"; else cat; fi; }
