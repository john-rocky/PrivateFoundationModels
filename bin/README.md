# bin/ — promotion automation

Three scripts that get the v0.9 launch out the door with as little human friction as possible.

## `post-tabs.sh` — zero-credential, fast

```bash
./bin/post-tabs.sh
```

Opens all four pre-filled launchers (X, HN, r/swift, r/iOSProgramming) as browser tabs at once. Each tab has the title + body already populated; you click Submit / Post and you're done. No API keys, no Python, no auth. Pulls the launcher URLs from [`docs/POST_NOW.md`](../docs/POST_NOW.md) so they stay current with each release.

This is the recommended path for the first push.

## `post-x.py` — fully automated X posting (opt-in)

If you have X v2 API credentials in your developer portal:

```bash
export X_CONSUMER_KEY=...
export X_CONSUMER_SECRET=...
export X_ACCESS_TOKEN=...
export X_ACCESS_TOKEN_SECRET=...

pip install tweepy
./bin/post-x.py
```

Posts the canonical v0.9 launch tweet via the v2 API. Pass a string argument to override the copy.

If env vars aren't set, the script prints what it *would* have posted and exits 0 — so it's safe to wire into CI as a dry-run sanity check.

## `post-reddit.py` — fully automated Reddit posting (opt-in)

If you have a Reddit "script" app at <https://www.reddit.com/prefs/apps>:

```bash
export REDDIT_CLIENT_ID=...
export REDDIT_CLIENT_SECRET=...
export REDDIT_USERNAME=...
export REDDIT_PASSWORD=...
export REDDIT_USER_AGENT="pfm-launch/0.9 by yourname"

pip install praw
./bin/post-reddit.py           # both subs
./bin/post-reddit.py swift     # just one
```

Same dry-run-without-creds pattern as `post-x.py`.

## What's not automated

- **Hacker News submission.** HN has no public submit API; the only path is the web form. `post-tabs.sh` covers the pre-filled HN tab so it's one click.
- **Apple Developer Forums.** Same — no submit API. See [`docs/apple-developer-forums-post.md`](../docs/apple-developer-forums-post.md) for the title + body to paste.

## What it would take to push further

A `@playwright/mcp` server wired into Claude Code would let the next session drive every form fill + click end-to-end (X, HN, Reddit, Apple Forums) from one prompt. Until then this is the bound.
