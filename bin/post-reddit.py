#!/usr/bin/env python3
"""Post the v0.9 launch threads to r/swift and r/iOSProgramming.

Reddit's official API uses OAuth 2.0 password grant for script apps.
From https://www.reddit.com/prefs/apps, create a "script" app and
collect: client id + client secret. Then set env vars:

  REDDIT_CLIENT_ID
  REDDIT_CLIENT_SECRET
  REDDIT_USERNAME
  REDDIT_PASSWORD
  REDDIT_USER_AGENT   — recommended, e.g. "pfm-launch/0.9 by yourname"

Usage:
  pip install praw
  ./bin/post-reddit.py           # posts to both subs
  ./bin/post-reddit.py swift     # just r/swift
  ./bin/post-reddit.py iOSProgramming

Dry-run mode (no creds set) prints what it WOULD post, then exits 0.
"""
import os
import sys

DEFAULT_TITLE = (
    "PrivateFoundationModels v0.9 — Apple FoundationModels on iOS 18+, "
    "plus the full OpenAI API surface (chat / tools / vision / embeddings) over HTTP"
)
DEFAULT_BODY = """The same Apple-FM-shaped Swift call site that runs against CoreML on iOS 18 now also runs against Apple's actual native FoundationModels on iOS 26 — and the same backend is reachable from any language via an OpenAI-compatible HTTP server.

Verified end-to-end on macOS 26.0 with the official `openai` Python SDK:

- chat completions (unary + streaming SSE)
- function calling (`tools[]` + `tool_calls[]` round-trip)
- vision (OpenAI content arrays with `data:image/...;base64,...`)
- embeddings (MLX-backed, experimental)

Two-line swap on the client:

```python
client = OpenAI(
    base_url="http://127.0.0.1:11434/v1",
    api_key="not-required",
)
```

Three backends share the same surface — Apple FoundationModels (native, iOS 26+), CoreML (iOS 18+), MLX (iOS 17+, any `mlx-community/*` model including VLMs). MIT, SPM only.

Repo: https://github.com/john-rocky/PrivateFoundationModels"""

SUBREDDITS = ["swift", "iOSProgramming"]


def main() -> int:
    targets = sys.argv[1:] if len(sys.argv) > 1 else SUBREDDITS

    creds = {
        "client_id":     os.environ.get("REDDIT_CLIENT_ID"),
        "client_secret": os.environ.get("REDDIT_CLIENT_SECRET"),
        "username":      os.environ.get("REDDIT_USERNAME"),
        "password":      os.environ.get("REDDIT_PASSWORD"),
        "user_agent":    os.environ.get("REDDIT_USER_AGENT", "pfm-launch/0.9"),
    }
    missing = [k for k, v in creds.items() if k != "user_agent" and not v]
    if missing:
        print(f"DRY RUN — Reddit env vars not set: {missing}")
        print("Would have posted to:", targets)
        print()
        print("TITLE:", DEFAULT_TITLE)
        print()
        print("BODY:")
        print("-" * 60)
        print(DEFAULT_BODY)
        print("-" * 60)
        return 0

    try:
        import praw
    except ImportError:
        print("Missing dependency: `pip install praw`", file=sys.stderr)
        return 1

    reddit = praw.Reddit(**creds)
    for sub in targets:
        submission = reddit.subreddit(sub).submit(
            title=DEFAULT_TITLE, selftext=DEFAULT_BODY
        )
        print(f"r/{sub}: {submission.url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
