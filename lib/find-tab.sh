#!/usr/bin/env bash
# find-tab.sh — Locate the zellij tab hosting a given worktree, and sketch its panes.
#
# Usage: find-tab.sh [worktree-path]
#   If no path is given, uses $PWD.
#
# Scans every live zellij session, matches panes by cwd (exact match on the
# worktree, or a subdirectory thereof, to tolerate panes that have cd'd deeper).
# Plugin panes are ignored since they don't report a cwd.
#
# On success (exactly one matching tab), prints to stdout:
#
#   <session>\t<tab_id>\t<tab_name>       # line 1: identity (TSV)
#   - <pane command>[ (cwd: <rel>)]       # lines 2+: one bullet per non-plugin pane
#   - ...
#
# Callers that only need the tab identity can `read` the first line and ignore
# the rest. The bullets are markdown-ready for embedding in an archive entry.
#
# Exit codes:
#   0 — exactly one tab matches
#   1 — no tab matches
#   2 — multiple tabs match (details on stderr; caller should ask user)
#   3 — environmental error (zellij/jq missing, no sessions, etc.)

set -euo pipefail

worktree="${1:-$PWD}"
if ! worktree="$(cd "$worktree" 2>/dev/null && pwd -P)"; then
  echo "find-tab: cannot access worktree path: ${1:-$PWD}" >&2
  exit 3
fi

for cmd in zellij jq; do
  if ! command -v "$cmd" >/dev/null; then
    echo "find-tab: $cmd not on PATH" >&2
    exit 3
  fi
done

sessions="$(zellij list-sessions --short --no-formatting 2>/dev/null || true)"
if [[ -z "$sessions" ]]; then
  echo "find-tab: no zellij sessions running" >&2
  exit 3
fi

# Gather unique (session, tab_id, tab_name) tuples matching the worktree,
# keyed by "<session>\t<tab_id>" so we can look up panes afterward.
matches=()
declare -A panes_by_session  # session -> panes_json cache

while IFS= read -r session; do
  [[ -z "$session" ]] && continue
  if ! panes_json="$(zellij -s "$session" action list-panes --json 2>/dev/null)"; then
    continue
  fi
  panes_by_session["$session"]="$panes_json"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    matches+=("$line")
  done < <(
    jq -r --arg cwd "$worktree" --arg session "$session" '
      map(select(
        .pane_cwd != null and
        (.pane_cwd == $cwd or (.pane_cwd | startswith($cwd + "/")))
      ))
      | map({tab_id, tab_name})
      | unique_by(.tab_id)
      | .[] | [$session, (.tab_id | tostring), .tab_name] | @tsv
    ' <<<"$panes_json"
  )
done <<<"$sessions"

case "${#matches[@]}" in
  0)
    echo "find-tab: no tab found with cwd $worktree" >&2
    exit 1
    ;;
  1)
    printf '%s\n' "${matches[0]}"
    IFS=$'\t' read -r session tab_id tab_name <<<"${matches[0]}"
    # Sketch the non-plugin panes in this tab. Prefer pane_command (current
    # foreground process); fall back to terminal_command (launch command).
    jq -r --arg cwd "$worktree" --argjson tab_id "$tab_id" '
      map(select(.tab_id == $tab_id and (.is_plugin // false) == false))
      | .[]
      | (.pane_command // .terminal_command // "?") as $cmd
      | (.pane_cwd // "") as $pcwd
      | (if $pcwd == "" or $pcwd == $cwd then ""
         elif ($pcwd | startswith($cwd + "/")) then " (cwd: ./" + ($pcwd | ltrimstr($cwd + "/")) + ")"
         else " (cwd: " + $pcwd + ")"
         end) as $cwdsuffix
      | "- " + $cmd + $cwdsuffix
    ' <<<"${panes_by_session[$session]}"
    exit 0
    ;;
  *)
    echo "find-tab: multiple tabs match $worktree:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 2
    ;;
esac
