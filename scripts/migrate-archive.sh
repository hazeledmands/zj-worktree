#!/usr/bin/env bash
# migrate-archive.sh — One-off backfill for legacy archive entries.
#
# For each ~/.claude/archive/*.md (skipping INDEX.md):
#   - If the frontmatter has no `status:` line, inject:
#       status: archived
#       last_updated: <existing archived: value, or "unknown">
#   - Otherwise leave the file alone.
#
# Then remove INDEX.md (no longer canonical state — lib/list-tabs.sh
# computes the same view from the per-tab files on demand).
#
# Idempotent: running it a second time is a no-op.
#
# Usage: migrate-archive.sh
#   ARCHIVE_DIR (env) overrides ~/.claude/archive.

set -euo pipefail

archive_dir="${ARCHIVE_DIR:-$HOME/.claude/archive}"
if [[ ! -d "$archive_dir" ]]; then
    echo "migrate-archive: $archive_dir does not exist; nothing to do" >&2
    exit 0
fi

shopt -s nullglob
migrated=0
for f in "$archive_dir"/*.md; do
    [[ "$(basename "$f")" == "INDEX.md" ]] && continue

    if grep -q '^status:' "$f"; then
        continue
    fi

    tmp="$(mktemp)"
    awk '
        BEGIN { state = 0; archived_value = "" }
        state == 0 && /^---$/ { state = 1; print; next }
        state == 1 && /^---$/ {
            print "status: archived"
            print "last_updated: " (archived_value != "" ? archived_value : "unknown")
            state = 2; print; next
        }
        state == 1 && /^archived: / {
            v = substr($0, 11)
            sub(/[[:space:]]+$/, "", v)
            archived_value = v
            print; next
        }
        { print }
    ' "$f" > "$tmp"
    mv "$tmp" "$f"
    migrated=$((migrated + 1))
done

if [[ -f "$archive_dir/INDEX.md" ]]; then
    rm "$archive_dir/INDEX.md"
fi

echo "migrate-archive: backfilled $migrated entries; INDEX.md removed if present."
