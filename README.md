# zj-worktree

Open a new [zellij](https://zellij.dev/) tab running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a git worktree. Includes Claude Code skills for dispatching work and reviewing PRs.

## Usage

```
zj-worktree --branch <branch> --tab <name> [--prompt <text>]
zj-worktree --branch <branch> --tab <name> --resume
zj-worktree --pr <number> --tab <name> [--prompt <text>]
zj-worktree --dir <path> --tab <name> [--prompt <text>]
```

### Options

| Flag | Description |
|------|-------------|
| `--branch <branch>` | Create a new worktree for this branch (uses `wt switch --create`) |
| `--pr <number>` | Check out a PR's branch with remote tracking (uses `wt switch pr:<N>`) |
| `--dir <path>` | Use an existing worktree directory |
| `--tab <name>` | Name for the new zellij tab (required) |
| `--prompt <text>` | Initial prompt to send to Claude |
| `--resume` | Resume the most recent Claude conversation in the worktree |
| `-h`, `--help` | Show help |

### Examples

Create a new branch and open Claude with a prompt:

```bash
zj-worktree --branch feature/login-fix --tab login-fix --prompt "Fix the login timeout issue"
```

Check out a PR for review:

```bash
zj-worktree --pr 42 --tab auth-refactor --prompt "Summarize PR #42 and wait for questions"
```

Open Claude in an existing worktree directory:

```bash
zj-worktree --dir ~/Projects/myrepo-feature --tab feature-work
```

Resume the last Claude session in a branch's worktree:

```bash
zj-worktree --branch feature/login-fix --tab login-fix --resume
```

## Skills

This repo includes two [Claude Code skills](https://docs.anthropic.com/en/docs/claude-code/skills) that work in any git repository:

### `/dispatch`

Dispatches work to a new worktree tab with its own Claude instance. Handles branch creation, tab naming, prompt crafting, and resume-vs-new decisions. Supports per-repo customization via `.claude/dispatch.md` (see below).

### `/review-assist`

Opens a PR for interactive review — fetches changed files, summarizes the conversation so far (review comments, CI status, linked context), and waits for your questions. Uses `gh` for GitHub API access and auto-detects the repo.

## Dependencies

- [zellij](https://zellij.dev/)
- [wt (worktrunk)](https://worktrunk.dev) — git worktree manager
- [gh](https://cli.github.com/) — GitHub CLI
- [jq](https://jqlang.github.io/jq/)
- [recall](https://github.com/anthropics/recall) — Claude Code conversation search (used by `/dispatch` to check for prior sessions)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- A zellij layout at `~/.config/zellij/layouts/claude-tab.kdl`

## Install

Copy or symlink `zj-worktree` somewhere on your `$PATH`:

```bash
ln -s "$(pwd)/zj-worktree" ~/.local/bin/zj-worktree
```

Install the Claude Code skills:

```bash
for skill in dispatch review-assist; do
    mkdir -p ~/.claude/skills/$skill
    for f in skills/$skill/*; do
        ln -sf "$(pwd)/$f" ~/.claude/skills/$skill/$(basename "$f")
    done
done
```

### Per-repo dispatch instructions

Repos can supply custom dispatch instructions by creating a `.claude/dispatch.md` file. When the `/dispatch` skill runs, it reads this file from the target repo and follows its instructions (environment checks, warnings, worktree primer additions, etc.). If the file doesn't exist, the skill uses generic defaults.
