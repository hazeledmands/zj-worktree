# zj-worktree

Open a new [zellij](https://zellij.dev/) tab running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a git worktree.

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
zj-worktree --branch hazel/fix/login-bug --tab login-fix --prompt "Fix the login timeout issue"
```

Check out a PR for review:

```bash
zj-worktree --pr 31225 --tab count-datapoints --prompt "Summarize PR #31225 and wait for questions"
```

Open Claude in an existing worktree directory:

```bash
zj-worktree --dir ~/Projects/myrepo-feature --tab feature-work
```

Resume the last Claude session in a branch's worktree:

```bash
zj-worktree --branch hazel/fix/login-bug --tab login-fix --resume
```

## Dependencies

- [zellij](https://zellij.dev/)
- [wt (worktrunk)](https://worktrunk.dev) (git worktree manager)
- [gh](https://cli.github.com/) (GitHub CLI, required for `--pr`)
- [jq](https://jqlang.github.io/jq/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- A zellij layout at `~/.config/zellij/layouts/claude-tab.kdl`

## Install

Copy or symlink `zj-worktree` somewhere on your `$PATH`:

```bash
ln -s "$(pwd)/zj-worktree" ~/.local/bin/zj-worktree
```
