---
name: dispatch
description: Dispatch work to a new worktree tab with its own Claude instance. Use when the user wants to send a task to a separate worktree or work on something in parallel. Triggers on "dispatch this", "work on this in a new tab", "create a worktree for this", "open a tab for", or when the user describes a task they want handled in a separate session.
allowed-tools: Bash(zj-worktree:*), Bash(wt list:*), Bash(git branch:*), Bash(git log:*), Bash(git fetch:*), Bash(gh pr view:*), Bash(git rev-parse:*), Bash(git worktree list:*), Bash(recall:*), Bash(basename:*), Bash(cat:*)
---

# Dispatch to Worktree

Send a task to a new git worktree in a dedicated zellij tab with its own Claude instance.

**Always create a worktree**, even for pure research or investigation tasks. The isolated folder is valuable regardless of whether code changes are expected.

**Note:** `zj-worktree` should be on your `$PATH` (typically symlinked from `~/.local/bin/zj-worktree`). The source repo is at [hazeledmands/zj-worktree](https://github.com/hazeledmands/zj-worktree).

## Process

### 1. Understand the task

If the user provided a task description (as an argument or in conversation), use it directly. Otherwise, ask what they want done.

**Don't pre-fetch URLs.** If the user pastes a Slack link, GitHub URL, or other reference, do NOT follow it yourself to gather context. Just include the URL in the worker prompt and let the dispatched agent fetch it. This avoids the temptation to "just quickly check" something and then end up doing the work yourself instead of dispatching.

### 2. Determine the repo context

Identify which git repository the dispatch targets. Derive the main checkout path and repo name:

```bash
# The main worktree is always the first entry
git worktree list --porcelain | head -1 | sed 's/^worktree //'
```

```bash
basename "$(git rev-parse --show-toplevel)"
```

### 3. Fetch latest main

When starting a **new branch** (not resuming an existing one or checking out a PR branch), fetch and update the main branch so the worktree starts from the latest upstream state:

```bash
git fetch origin main:main
```

Skip this step when dispatching to an existing branch or PR — those already have their own history.

### 4. Pick a branch name

**When the task relates to an existing PR or branch**, use that branch rather than creating a new one. The worker needs to see the existing changes, and any resulting commits belong on that branch. For PRs, look up the `headRefName` to get the branch.

**When starting new work**, follow user specifications or existing conventions for branch names if you can. Check existing branches for patterns:

```bash
git branch --list '*/*' | tail -20
```

### 5. Pick a tab name

Choose a short, descriptive name (1-2 words, enough to disambiguate from other tabs). The tab name should describe the **feature area or branch**, not the specific sub-task being performed. This keeps the tab name useful if the scope of work on that branch evolves.

- Derive the tab name from the branch name's description, not from the immediate task.
- Do NOT include task-specific terms like "fix", "ci", PR numbers, or ticket IDs in the tab name.

Examples:
- Branch `feature/fix-auth-bug` → tab `auth-bug` (not `ci-fix-auth`)
- Branch `user/rebalancer/sync-metrics` → tab `sync-metrics` (not `fix-30456`)
- Branch `user/ci/lint-migrations` → tab `lint-migrations`

### 6. Choose: resume or new prompt

**Check for prior conversation history** — When dispatching to an existing branch, use `recall` to
check whether there's a meaningful prior session to resume:

```bash
# Search for sessions in the worktree directory for this branch
# Use the main checkout path with the worktree suffix appended
recall search "<branch-name-keywords>" --cwd <main-checkout>.<worktree-suffix> --limit 3 --context 1
```

If the worktree doesn't exist yet (new branch), skip this check — there's nothing to resume.

Use the results to decide:

- **Substantial prior session exists + user just wants to pick up where they left off** → `--resume`
- **Substantial prior session exists + user has new/different instructions** → `--prompt` with the new context (the worker will still have its prior conversation via resume, but a fresh prompt ensures the new task is front and center)
- **No prior session or only trivial history (e.g., a quick lookup that's done)** → `--prompt` with a fresh task description, even if the branch exists
- **Unclear** → default to `--resume` if the branch exists, `--prompt` if it's new

**Resuming existing work** — When using `--resume`, the worker picks up from its last conversation.
If the user has additional instructions beyond just "open this branch", pass those as `--prompt`
instead so the worker has the new context.

**New work** — When starting fresh work on a new branch, craft a worker prompt:

- State what needs to be done concisely
- Include any relevant context the user mentioned (file paths, error messages, ticket numbers)
- NOT include instructions about branch creation or worktree management (that's already handled)
- Be self-contained — the worker Claude won't have access to this conversation
- Do NOT prescribe specific output mechanisms (e.g. "save to this file path"). Let the worker Claude use its own built-in tools for plans, summaries, etc. Just describe the desired outcome.

### 7. Load per-repo dispatch instructions

Check for repo-specific dispatch instructions:

```bash
cat "<main-checkout-path>/.claude/dispatch.md" 2>/dev/null
```

If the file exists, read and follow its contents. These instructions may specify:
- Environment checks to run before dispatching
- Warnings or confirmations to present to the user
- Additional context to include in the worktree primer

If the file does not exist, skip this step entirely.

### 8. Build worktree primer and dispatch

**Append** a one-liner worktree context note to the end of the worker prompt:

```
(You are in a git worktree of <repo-name>. Read code from your current working directory, NOT from <main-checkout-path>/.)
```

If per-repo dispatch instructions (step 6) specified additional primer content, append that too.

For resuming existing work:
```bash
zj-worktree --branch "<branch-name>" --tab "<tab-name>" --resume
```

For new work:
```bash
zj-worktree --branch "<branch-name>" --tab "<tab-name>" --prompt "<worker-prompt>"
```

### 9. Confirm

Tell the user:
- What branch was used
- What tab name was used
- Whether it resumed an existing conversation or started fresh
- A brief summary of what the worker Claude was asked to do (if a prompt was given)

## Examples

### New work
User: "Can you fix the flaky test in TestConnectionPool? It's timing out intermittently."

1. **Branch**: `fix/flaky-connection-pool-test` (or whatever matches repo conventions)
2. **Tab**: `connection-pool`
3. **Prompt**: "The test TestConnectionPool is flaky — it times out intermittently. Investigate the test, identify the timing issue, and fix it."
4. **Command**: `zj-worktree --branch fix/flaky-connection-pool-test --tab "connection-pool" --prompt "<prompt>"`

### Reviewing a PR
When the user wants to review a PR authored by someone else, the default is an **interactive reading session** — the worker summarizes the PR and waits for questions. Do NOT have the worker perform a full code review unless the user explicitly asks for one.

Use `--pr <number>` instead of `--branch` so the worktree tracks the remote branch (important for seeing the actual PR changes, not just an empty branch off main).

The worker prompt should instruct the agent to run `/review-assist` for the given PR number, then wait for the user's questions.

User: "I'd like to review PR 42"

1. **Tab**: derive from PR title/topic
2. **Prompt**: "The user wants to review PR #42. Run /review-assist 42 to get oriented, then wait for the user's questions."
3. **Command**: `zj-worktree --pr 42 --tab "<topic>" --prompt "<prompt>"`

### Resuming existing work
User: "Open a tab for the connection-pool-refactor branch"

1. **Branch**: `feature/connection-pool-refactor` (existing)
2. **Tab**: `connection-pool`
3. **Command**: `zj-worktree --branch feature/connection-pool-refactor --tab "connection-pool" --resume`
