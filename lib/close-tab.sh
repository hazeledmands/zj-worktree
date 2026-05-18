#!/usr/bin/env bash
# close-tab.sh — Close the zellij tab hosting a given worktree.
#
# Usage: close-tab.sh [--remove] [<worktree-path>]
#   If no path is given, uses $PWD.
#   --remove also discards the worktree via `wt remove` before closing the
#     tab. Bails (does not close the tab) if `wt remove` fails, so you can
#     investigate. `wt remove` is conservative — it refuses to delete an
#     unmerged branch unless told otherwise — so the misfire blast radius
#     is small even if --remove is passed in error.
#
# Resolves the tab via find-tab.sh (cwd-match verification is inherited), and
# closes it with `zellij action close-tab-by-id`. Only closes on a unique
# match — never a tab that doesn't host the worktree you named.
#
# Exit codes (first three propagated from find-tab.sh):
#   0 — tab closed (and worktree removed if --remove)
#   1 — no tab hosts this worktree
#   2 — multiple tabs host this worktree (find-tab prints them on stderr)
#   3 — environmental error (zellij/jq missing, no sessions, etc.)
#   4 — close-tab-by-id itself failed
#   5 — `wt remove` failed (with --remove); tab not closed

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

remove=0
if [[ "${1:-}" == "--remove" ]]; then
  remove=1
  shift
fi
worktree="${1:-$PWD}"

# find-tab exits non-zero on no-match / ambiguous / env-error;
# set -e propagates the exact code up.
result="$("$here/find-tab.sh" "$worktree")"

IFS=$'\t' read -r session tab_id tab_name <<<"$result"

if (( remove )); then
  # cd out of the worktree so wt's cwd remains valid after removal,
  # and so this script's own cwd doesn't go stale before zellij action runs.
  if ! ( cd "$HOME" && wt -C "$worktree" remove ); then
    echo "close-tab: wt remove failed for $worktree; not closing tab" >&2
    exit 5
  fi
fi

if ! zellij -s "$session" action close-tab-by-id "$tab_id"; then
  echo "close-tab: close-tab-by-id failed for $tab_name (session=$session tab_id=$tab_id)" >&2
  exit 4
fi
