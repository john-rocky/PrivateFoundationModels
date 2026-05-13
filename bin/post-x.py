#!/usr/bin/env python3
"""Post the v0.9 launch tweet to X via the v2 API.

Set these env vars from your X developer portal (the v2 Free tier
allows ~500 posts/month with OAuth 1.0a user context):

  X_CONSUMER_KEY        — "API Key"
  X_CONSUMER_SECRET     — "API Secret"
  X_ACCESS_TOKEN        — generated against your account
  X_ACCESS_TOKEN_SECRET — same

Usage:
  pip install tweepy
  ./bin/post-x.py            # uses the canonical v0.9 tweet
  ./bin/post-x.py "alt copy" # custom text

Dry-run mode (no creds set) prints what it WOULD post, then exits 0.
"""
import os
import sys

DEFAULT_TWEET = """Same Qwen3.5-0.8B model. Same prompt. Apple M4 Max.

· CoreML / ANE  — 526 ms TTFT, 158 chars/sec
· MLX / GPU 4b  — 43 ms TTFT, 781 chars/sec

12× TTFT, 5× throughput. One PrivateFoundationModels call site routes between them.

github.com/john-rocky/PrivateFoundationModels"""


def main() -> int:
    text = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_TWEET

    creds = {
        "consumer_key":        os.environ.get("X_CONSUMER_KEY"),
        "consumer_secret":     os.environ.get("X_CONSUMER_SECRET"),
        "access_token":        os.environ.get("X_ACCESS_TOKEN"),
        "access_token_secret": os.environ.get("X_ACCESS_TOKEN_SECRET"),
    }
    missing = [k for k, v in creds.items() if not v]

    if missing:
        print(f"DRY RUN — X env vars not set: {missing}")
        print("Would have posted:")
        print("-" * 60)
        print(text)
        print("-" * 60)
        print(f"\nLength: {len(text)} chars ({280 - len(text)} left of free-tier 280 limit)")
        return 0

    try:
        import tweepy
    except ImportError:
        print("Missing dependency: `pip install tweepy`", file=sys.stderr)
        return 1

    client = tweepy.Client(**creds)
    resp = client.create_tweet(text=text)
    if hasattr(resp, "data") and resp.data:
        tweet_id = resp.data.get("id")
        print(f"Posted: https://twitter.com/i/web/status/{tweet_id}")
    else:
        print(f"Unexpected response: {resp!r}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
