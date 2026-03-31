---
name: review-assist
description: Assists with reviewing GitHub PRs — opens files, summarizes changes, fetches threaded review comments, checks CI. Use when reviewing a PR, re-reviewing after updates, or needing to see discussion history on a PR. Triggers on PR numbers, GitHub PR URLs, or phrases like "review this PR", "look at PR 1234", "what's the status of this PR", "re-review", "check the comments on". Takes a PR number or URL as an argument.
allowed-tools: Bash(python3 ~/.claude/skills/review-assist/pr-comments.py:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(zed:*)
---

# PR Review Assistant

When invoked with a PR number or URL (e.g. `/review-assist 31225` or `/review-assist https://github.com/org/repo/pull/31225`), extract the PR number and perform the following steps.

If this is a **re-review** (the user mentions "re-review", "changes since last review", or similar), look up the user's last review timestamp with `gh pr view <number> --json reviews` and pass `--since <timestamp>` to the comments script to filter to only new discussion.

## 1. Open changed files in Zed

```bash
zed . $(gh pr view <number> --json files --jq '.files[].path')
```

## 2. Orient the user to the conversation so far

Before diving into the code, give context on:

- **Who is involved** — author, reviewers, anyone mentioned
- **Broader context** — if the PR description links to tickets, Slack threads, or other PRs, follow those links and summarize the relevant context
- **Urgency** — is it blocking something? does the description mention a deadline?
- **Existing discussion** — fetch and summarize review comments:

```bash
# All comments (auto-detects repo from git remote)
python3 ~/.claude/skills/review-assist/pr-comments.py <number>

# Only comments after a specific time (useful for re-reviews)
python3 ~/.claude/skills/review-assist/pr-comments.py <number> --since <ISO-timestamp>

# For a different repo
python3 ~/.claude/skills/review-assist/pr-comments.py <number> --repo owner/repo
```

The script outputs:
- **Review summaries** — top-level review bodies (APPROVED, CHANGES_REQUESTED, etc.)
- **Inline comments** — grouped by file, sorted by line number, with threaded replies nested under parent comments

## 3. Check CI status

```bash
gh pr checks <number>
```

If there are failures, describe them at a high level and include links to the error output.

## 4. Summarize the code changes

List the files changed and the key changes in each. Use `gh pr diff` and `gh pr view --json body` for full context.

## 5. Wait for questions

Present the summary and wait for the user to ask questions or give direction.
