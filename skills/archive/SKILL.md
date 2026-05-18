---
name: archive
description: Put down the current worktree tab for later. Writes a short summary entry to ~/.claude/archive/ and closes the zellij tab; the worktree and session history typically persist so /dispatch can resume it later, but the skill can also remove the worktree when the context is throwaway (review-only, exploration, merged branch). Use when the user says "archive this", "put this down", "park this tab", "I'm done with this for now", or otherwise wants to stop working on the current tab without losing context.
allowed-tools: Bash(git branch:*), Bash(git worktree:*), Bash(git rev-parse:*), Bash(git status:*), Bash(basename:*), Bash(~/.claude/skills/archive/find-tab.sh:*), Bash(~/.claude/skills/archive/close-tab.sh:*), Bash(~/.claude/skills/archive/save-archive.sh:*), Bash(ls:*), Read
---

# Archive a Worktree Tab

Put down a zellij worktree tab for later. Writes a short entry under `~/.claude/archive/` (so future `/dispatch` invocations can find it) and then closes the tab. By default the git worktree and the Claude session history stay put — "unarchiving" is just `/dispatch` opening a new tab with `--resume`. For throwaway contexts (review-only, scratch exploration, merged branch) the skill will proactively offer to also remove the worktree; see *(Optional) Remove the worktree* below.

**This is a worker-side skill.** Run it from inside the tab you want to put down, not from the dispatcher.

**Permissions gotcha:** the `find-tab.sh` / `close-tab.sh` / `save-archive.sh` invocations below are pre-approved literally. Do **not** embed `$(...)` command substitution in them — the permission matcher treats the nested command as unapproved and prompts. Instead, either rely on `$PWD` defaults, or run `git rev-parse --show-toplevel` / `git branch --show-current` / etc. as separate bash calls and paste the resulting string in as a literal argument when invoking the script.

## Preflight

Before doing anything, confirm this is a worktree worth archiving.

```bash
git rev-parse --show-toplevel
```

If the current directory is the main checkout (no worktree suffix — matches `git worktree list --porcelain | head -1`), stop and tell the user: "`/archive` is meant to be run from inside a worker worktree, not the main checkout. Run it from the tab you want to put down."

Also check whether there are uncommitted changes:

```bash
git status --porcelain
```

If there are, mention them to the user once as part of the archive confirmation — they stay in the worktree regardless, but it's worth surfacing so the user can choose to commit/stash first if they want.

## Gather state

Collect the bits that go into the archive entry:

- **Branch**: `git branch --show-current`
- **Worktree path**: `git rev-parse --show-toplevel`
- **Repo**: `basename` of the main checkout (first entry of `git worktree list --porcelain`)
- **Tab info + pane sketch**: run `~/.claude/skills/archive/find-tab.sh` with no argument (it defaults to `$PWD`, which is the worktree). First line is `<session>\t<tab_id>\t<tab_name>` — use the `<tab_name>` as the canonical tab name (beats deriving from the branch). Lines 2+ are markdown bullets, one per non-plugin pane, ready to paste into the archive body. Handle non-zero exit codes per the Close-the-tab section below.
- **Date**: today, in `YYYY-MM-DD` format
- **Summary**: 1–3 sentences, written by you from your own context. Cover:
  - What was the task?
  - What's been done / what's the current state?
  - What's blocking or what's the next step if resumed?

The summary is the whole point of the archive — it's the only thing `/dispatch` sees without loading the full session. Make it concrete. Avoid filler like "working on X"; prefer "Found the race in `foo.go:42`, reproduced with `go test -run TestBar`; next step is to add a mutex around the cache read."

## Write the archive entry

Use `~/.claude/skills/archive/save-archive.sh`. It takes the frontmatter fields as positional arguments and reads the entry body from stdin. **All five positional args must be literal strings** — substitute the values you gathered in the previous step directly into the command, do not use `$(...)` command substitution:

```bash
~/.claude/skills/archive/save-archive.sh "deletion-check" "hazel/hound-deletion-check/fix" "/Users/hazel/Projects/hound.hazel-hound-deletion-check-fix" "hound" "2026-04-24" <<'BODY'
<summary, 1–3 sentences — the first non-blank line becomes the INDEX hook>

**Tab state at archive:**
<pane-sketch lines from find-tab.sh, one bullet per line>
BODY
```

The script writes `~/.claude/archive/<repo>-<branch-slug>.md` (overwriting if it exists — that's how re-archiving bumps to the top), then prepends a hook line to `~/.claude/archive/INDEX.md`, dedupes any prior entry for the same `(repo, branch)`, and trims the index to 20 lines.

Notes:
- Omit the "Tab state at archive" section from the body if `find-tab.sh` produced no pane lines.
- The first non-blank line of the body becomes the INDEX hook (truncated to ~140 chars), so lead with the most load-bearing sentence.

## (Optional) Remove the worktree

Default behavior is to leave the worktree on disk so `/dispatch` can resume it. Skip that default — proactively offer to remove the worktree — when the context strongly suggests there's nothing to come back to:

- Reviewing someone else's PR (the branch isn't yours; it'll likely be deleted on merge upstream).
- Throwaway exploration / scratch work the user has indicated they're done with.
- Branch already merged upstream.
- Direct user signal: "nothing to resume", "I'm done done", "throwaway", "just remove it", "ditch the worktree".

When the trigger is unambiguous **and** the worktree is clean, just go ahead — don't ask first. The archive entry has already been written, so the writeup (including the "Tab state at archive" section) survives the removal. Only the worktree directory and the live Claude session history go away; `/dispatch` resume won't work after this, but the summary remains discoverable in `~/.claude/archive/INDEX.md`. Tell the user what you did in one line after — they can object if it was wrong, and `wt remove` is conservative enough (won't delete an unmerged branch) that the blast radius of a misfire is small.

**Always recheck for uncommitted work before removing.** Preflight already ran `git status --porcelain`. If it returned anything (or has changed since), do *not* proceed silently — surface those changes verbatim and require an explicit user confirmation that they really want to discard them before invoking the remove path. Do not pass `--force` or any equivalent flag without that confirmation. The "just go ahead" path is conditioned on the worktree being clean.

When you decide to remove, do *not* invoke `wt` directly. The remove step is folded into the *Close the tab* helper via its `--remove` flag — see below. That keeps the whole skill running through pre-approved scripts, with no separate `wt` permission needed.

## Close the tab

Use the helper `~/.claude/skills/archive/close-tab.sh`. Invoke it with no argument — it defaults to `$PWD` (the worktree). The helper looks up the tab via `find-tab.sh` (matching panes by cwd), verifies the match is unique, and closes by ID — so it will never close a tab that doesn't actually host the worktree you named.

```bash
~/.claude/skills/archive/close-tab.sh
```

If you decided to remove the worktree per the optional section above, pass `--remove`. The helper runs `wt remove` first (after `cd "$HOME"` so cwd stays valid), and only proceeds to close the tab on success. If `wt remove` fails (e.g. unmerged branch, dirty tree it doesn't accept), it bails with exit 5 and leaves the tab open so you can investigate. Doing the remove this way avoids needing a separate `wt` permission.

```bash
~/.claude/skills/archive/close-tab.sh --remove
```

Handle non-zero exits explicitly — do **not** fall back to bare `zellij action close-tab`, which closes whichever tab is focused regardless of identity:

- Exit 1 (no tab hosts this worktree): the archive entry is written, but the tab wasn't located. Tell the user and move on.
- Exit 2 (multiple tabs host this worktree): stop and ask the user which one to close. The candidates are on stderr as `<session>\t<tab_id>\t<tab_name>`. Once picked, invoke `find-tab.sh` / `close-tab.sh` again in the narrowed scope, or ask the user to close the remaining tab manually.
- Exit 3 (environment error — zellij/jq missing, no sessions): archive entry is written; tell the user and stop.
- Exit 4 (close-tab-by-id itself failed): rare; report it to the user.
- Exit 5 (`--remove` only — `wt remove` failed): the worktree was *not* removed and the tab was *not* closed. Surface the stderr from `wt` to the user and let them decide whether to retry without `--remove`, fix the underlying issue, or abandon the archive.

This ends the skill — no confirmation message is needed since the tab is going away. The archive entry itself is the confirmation.

## Failure modes

- **Not in a worktree**: stop and tell the user (see Preflight).
- **No branch (detached HEAD)**: ask the user what identifier to file it under, or abort.
- **Tab lookup fails** (`find-tab.sh` exits non-zero): see the close-tab section above for per-exit-code behavior. Never fall back to bare `zellij action close-tab` — it closes whichever tab is focused, which may not be the one you meant.
