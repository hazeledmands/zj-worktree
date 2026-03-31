#!/usr/bin/env python3
"""Fetch and display PR review comments in a readable threaded format.

Usage:
    pr-comments.py <pr-number> [--since TIMESTAMP] [--repo OWNER/REPO]

Examples:
    pr-comments.py 31427
    pr-comments.py 31427 --since 2026-03-18T20:23:08Z
    pr-comments.py 31427 --repo honeycombio/hound
"""

import argparse
import json
import subprocess
import sys
from collections import defaultdict


def detect_repo():
    """Detect the GitHub repo from the current git remote."""
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        capture_output=True, text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def fetch_comments(repo, pr_number):
    """Fetch all review comments for a PR, handling pagination."""
    result = subprocess.run(
        [
            "gh", "api",
            f"repos/{repo}/pulls/{pr_number}/comments",
            "--paginate",
            "-q", ".",
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"Error fetching comments: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    # --paginate outputs one JSON array per page, concatenated
    comments = []
    for line in result.stdout.strip().split("\n"):
        if line:
            parsed = json.loads(line)
            if isinstance(parsed, list):
                comments.extend(parsed)
            else:
                comments.append(parsed)
    return comments


def fetch_review_bodies(repo, pr_number):
    """Fetch top-level review bodies (the summary comment on a review)."""
    result = subprocess.run(
        ["gh", "pr", "view", str(pr_number), "--repo", repo, "--json", "reviews"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return {}
    data = json.loads(result.stdout)
    reviews = {}
    for r in data.get("reviews", []):
        if r.get("body", "").strip():
            reviews[r["author"]["login"]] = reviews.get(r["author"]["login"], [])
            reviews[r["author"]["login"]].append({
                "body": r["body"],
                "state": r.get("state", ""),
                "submittedAt": r.get("submittedAt", ""),
            })
    return reviews


def format_comments(comments, since=None):
    """Format comments into readable threaded output."""
    if since:
        comments = [c for c in comments if c["created_at"] > since]

    if not comments:
        print("No comments found" + (f" since {since}" if since else "") + ".")
        return

    # Group by thread: top-level comments and their replies
    threads = defaultdict(list)
    top_level = []

    for c in comments:
        reply_to = c.get("in_reply_to_id")
        if reply_to:
            threads[reply_to].append(c)
        else:
            top_level.append(c)

    # Group top-level comments by file
    by_file = defaultdict(list)
    for c in top_level:
        by_file[c.get("path", "(no file)")].append(c)

    for path in sorted(by_file.keys()):
        print(f"## {path}")
        print()
        for c in sorted(by_file[path], key=lambda x: x.get("original_line") or x.get("line") or 0):
            line = c.get("original_line") or c.get("line") or "?"
            user = c["user"]["login"]
            time = c["created_at"]
            print(f"### L{line} — @{user} ({time})")
            print(c["body"])
            # Print replies indented
            for reply in threads.get(c["id"], []):
                print()
                r_user = reply["user"]["login"]
                r_time = reply["created_at"]
                print(f"  > **@{r_user}** ({r_time}):")
                for reply_line in reply["body"].split("\n"):
                    print(f"  > {reply_line}")
            print()


def main():
    parser = argparse.ArgumentParser(description="Fetch PR review comments")
    parser.add_argument("pr_number", type=int, help="PR number")
    parser.add_argument("--since", help="Only show comments after this ISO timestamp")
    parser.add_argument("--repo", help="GitHub repo (default: auto-detect from git remote)")
    args = parser.parse_args()

    repo = args.repo or detect_repo()
    if not repo:
        print("Error: could not detect GitHub repo. Use --repo OWNER/REPO.", file=sys.stderr)
        sys.exit(1)

    comments = fetch_comments(repo, args.pr_number)
    reviews = fetch_review_bodies(repo, args.pr_number)

    if reviews:
        print("# Review summaries")
        print()
        for user, review_list in reviews.items():
            for r in review_list:
                if args.since and r["submittedAt"] <= args.since:
                    continue
                print(f"**@{user}** — {r['state']} ({r['submittedAt']})")
                print(r["body"])
                print()

    print("# Inline comments")
    print()
    format_comments(comments, since=args.since)


if __name__ == "__main__":
    main()
