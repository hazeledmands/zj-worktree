---
name: archive
description: Put down the current worktree tab for later. Writes a short summary entry under ~/.claude/archive/ and closes the zellij tab; the worktree and session history typically persist so /dispatch can resume it later, but the skill can also remove the worktree when the context is throwaway (review-only, exploration, merged branch). Use when the user says "archive this", "put this down", "park this tab", "I'm done with this for now", or otherwise wants to stop working on the current tab without losing context.
allowed-tools: Bash(zj-worktree:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git status:*), Bash(git worktree:*), Bash(basename:*), Read
---

# Archive a Worktree Tab

Put down a zellij worktree tab for later. Writes a short entry under
`~/.claude/archive/` (so future `/dispatch` invocations can find it via
`zj-worktree resume`) and then closes the tab. By default the git worktree
and the Claude session history stay put — "unarchiving" is just `/dispatch`
opening a new tab with `--resume`. For throwaway contexts (review-only,
scratch exploration, merged branch) the skill will proactively offer to also
remove the worktree; see *Throwaway contexts* below.

**This is a worker-side skill.** Run it from inside the tab you want to put
down, not from the dispatcher.

## Preflight

Confirm this is a worktree worth archiving.

```bash
git rev-parse --show-toplevel
```

If the current directory is the main checkout (matches `git worktree list
--porcelain | head -1`), stop and tell the user: "`/archive` is meant to be
run from inside a worker worktree, not the main checkout. Run it from the tab
you want to put down." (`zj-worktree archive` enforces this too, but failing
loudly here is friendlier.)

Check whether there are uncommitted changes:

```bash
git status --porcelain
```

If there are, mention them in the archive confirmation — they stay in the
worktree regardless, but it's worth surfacing so the user can choose to
commit/stash first if they want.

## Compose the summary

Write 1–3 sentences from your own context. Cover:

- What was the task?
- What's been done / what's the current state?
- What's blocking or what's the next step if resumed?

The summary is the whole point of the archive — it's what `zj-worktree
resume` matches against and what future-you reads to figure out whether to
pick this thread back up. Make it concrete. Avoid filler like "working on X";
prefer "Found the race in `foo.go:42`, reproduced with `go test -run TestBar`;
next step is to add a mutex around the cache read."

## Write the entry and close the tab

Pipe the summary into `zj-worktree archive`. The CLI fills in the rest of
the entry (frontmatter, tab name from `find-tab.sh`, pane sketch), then closes
the zellij tab hosting this worktree.

```bash
zj-worktree archive <<'BODY'
<your 1–3 sentence summary>
BODY
```

The entry is written to `~/.claude/archive/<repo>-<branch-slug>.md` with
`status: archived`. If a prior entry exists for the same branch (e.g. you
archived this once, resumed, and are archiving again), it's overwritten —
including its `dispatched:` date, which is preserved across the rewrite.

## Throwaway contexts

Default behavior is to leave the worktree on disk so `/dispatch` can resume
it. Skip that default — pass `--remove` to also discard the worktree — when
the context strongly suggests there's nothing to come back to:

- Reviewing someone else's PR (their branch will get deleted upstream).
- Throwaway exploration the user has indicated they're done with.
- Branch already merged.
- Direct user signal: "nothing to resume", "I'm done done", "throwaway",
  "just remove it", "ditch the worktree".

When the trigger is unambiguous **and** the worktree is clean, just go ahead
— don't ask first. The archive entry is written before `wt remove` runs, so
the summary survives even if the worktree directory disappears.

**Always recheck for uncommitted work before passing `--remove`.** Preflight
already ran `git status --porcelain`; if it returned anything, surface those
changes verbatim and require an explicit user confirmation before passing
`--remove`. `wt remove` is conservative (refuses to delete unmerged branches
without a force flag), so misfires are contained — but losing uncommitted
work is still a regression you can prevent by asking.

```bash
zj-worktree archive --remove <<'BODY'
<your 1–3 sentence summary>
BODY
```

## Handling errors from `zj-worktree archive`

The CLI writes the archive entry **first**, then tries to close the tab. So
even if closing fails, the summary is safely on disk. Specific cases the CLI
reports:

- "no tab hosted this worktree" — fine, just say so. The entry is written.
- "multiple tabs host this worktree" — exit 2. Ask the user which to close.
- "wt remove failed" — exit 5 (only with `--remove`). Surface the stderr and
  let the user decide whether to retry without `--remove`, fix the issue, or
  abandon the archive.
- Detached HEAD or no branch — the CLI refuses. Resolve and retry.

This ends the skill — the tab is going away. No closing confirmation needed
beyond what the CLI prints.
