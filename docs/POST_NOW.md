# Post now — v0.9.0 launchers

Each link below opens the target platform's compose form **with the title, body, and URL already filled in**. Click → review → press Post. No copy-paste.

> View this file on GitHub if your browser blocks `file://` link clicks: <https://github.com/john-rocky/PrivateFoundationModels/blob/main/docs/POST_NOW.md>

## 1. X (recommended first move)

### v0.10.2 — runtime comparison hook (recommended for follow-up tweet)

[**→ Post the runtime-comparison tweet on X**](https://twitter.com/intent/tweet?text=Same%20Qwen3.5-0.8B%20model.%20Same%20prompt.%20Apple%20M4%20Max.%0A%0A%C2%B7%20CoreML%20%2F%20ANE%20%20%E2%80%94%20526%20ms%20TTFT%2C%20158%20chars%2Fsec%0A%C2%B7%20MLX%20%2F%20GPU%204b%20%20%E2%80%94%2043%20ms%20TTFT%2C%20781%20chars%2Fsec%0A%0A12%C3%97%20TTFT%2C%205%C3%97%20throughput.%20One%20PrivateFoundationModels%20call%20site%20routes%20between%20them.%0A%0Agithub.com%2Fjohn-rocky%2FPrivateFoundationModels)

(251字 / 280字。 attach: [`docs/media/runtime-comparison-m4max.png`](media/runtime-comparison-m4max.png) — the bar-chart PNG is the punch.)

### v0.9 surface hook (original)

[**→ Post the v0.9 launch tweet on X**](https://twitter.com/intent/tweet?text=PrivateFoundationModels%20v0.9%20%E2%80%94%20Apple%20Intelligence%20behind%20an%20OpenAI-compatible%20local%20API.%0A%0AThe%20official%20openai%20SDK%20works%20unchanged%3A%0Aclient%20%3D%20OpenAI%28base_url%3D%22http%3A%2F%2F127.0.0.1%3A11434%2Fv1%22%29%0A%0A%E2%9C%93%20chat%20%28SSE%29%0A%E2%9C%93%20tools%0A%E2%9C%93%20vision%0A%E2%9C%93%20embeddings%0A%0Agithub.com%2Fjohn-rocky%2FPrivateFoundationModels)

(253字 / 280字, X 無料枠ぴったり。)

Attach a 8-15 second screen-record of `Examples/PythonClient/openai_tools_demo.py` running — that's the most credible visual we have (the OpenAI SDK calling Apple's on-device model + invoking a Swift-defined tool round-trip).

## 2. Hacker News

[**→ Submit to HN**](https://news.ycombinator.com/submitlink?u=https%3A%2F%2Fgithub.com%2Fjohn-rocky%2FPrivateFoundationModels&t=PrivateFoundationModels%3A%20Apple%20Intelligence%20behind%20an%20OpenAI-compatible%20local%20API)

Title pre-filled: *PrivateFoundationModels: Apple Intelligence behind an OpenAI-compatible local API*

Best window: weekday 7-9 am Pacific.

## 3. Reddit r/swift

[**→ Submit to r/swift**](https://www.reddit.com/r/swift/submit?title=PrivateFoundationModels%20v0.9%20%E2%80%94%20Apple%20FoundationModels%20on%20iOS%2018%2B%2C%20plus%20the%20full%20OpenAI%20API%20surface%20%28chat%20%2F%20tools%20%2F%20vision%20%2F%20embeddings%29%20over%20HTTP&text=The%20same%20Apple-FM-shaped%20Swift%20call%20site%20that%20runs%20against%20CoreML%20on%20iOS%2018%20now%20also%20runs%20against%20Apple%27s%20actual%20native%20FoundationModels%20on%20iOS%2026%20%E2%80%94%20and%20the%20same%20backend%20is%20reachable%20from%20any%20language%20via%20an%20OpenAI-compatible%20HTTP%20server.%0A%0AVerified%20end-to-end%20on%20macOS%2026.0%20with%20the%20official%20openai%20Python%20SDK%3A%0A%0A-%20chat%20completions%20%28unary%20%2B%20streaming%20SSE%29%0A-%20function%20calling%20%28tools%5B%5D%20%2B%20tool_calls%5B%5D%20round-trip%29%0A-%20vision%20%28OpenAI%20content%20arrays%20with%20data%3Aimage%2F...%3Bbase64%2C...%29%0A-%20embeddings%20%28MLX-backed%2C%20experimental%29%0A%0ATwo-line%20swap%20on%20the%20client%3A%0A%0A%20%20%20%20client%20%3D%20OpenAI%28%0A%20%20%20%20%20%20%20%20base_url%3D%22http%3A%2F%2F127.0.0.1%3A11434%2Fv1%22%2C%0A%20%20%20%20%20%20%20%20api_key%3D%22not-required%22%2C%0A%20%20%20%20%29%0A%0AThree%20backends%20share%20the%20same%20surface%20%E2%80%94%20Apple%20FoundationModels%20%28native%2C%20iOS%2026%2B%29%2C%20CoreML%20%28iOS%2018%2B%29%2C%20MLX%20%28iOS%2017%2B%2C%20any%20mlx-community%2F%2A%20model%20including%20VLMs%29.%20MIT%2C%20SPM%20only.%0A%0ARepo%3A%20https%3A%2F%2Fgithub.com%2Fjohn-rocky%2FPrivateFoundationModels&kind=self)

## 4. Reddit r/iOSProgramming

[**→ Submit to r/iOSProgramming**](https://www.reddit.com/r/iOSProgramming/submit?title=PrivateFoundationModels%20v0.9%20%E2%80%94%20Apple%20FoundationModels%20on%20iOS%2018%2B%2C%20plus%20the%20full%20OpenAI%20API%20surface%20%28chat%20%2F%20tools%20%2F%20vision%20%2F%20embeddings%29%20over%20HTTP&text=The%20same%20Apple-FM-shaped%20Swift%20call%20site%20that%20runs%20against%20CoreML%20on%20iOS%2018%20now%20also%20runs%20against%20Apple%27s%20actual%20native%20FoundationModels%20on%20iOS%2026%20%E2%80%94%20and%20the%20same%20backend%20is%20reachable%20from%20any%20language%20via%20an%20OpenAI-compatible%20HTTP%20server.%0A%0AVerified%20end-to-end%20on%20macOS%2026.0%20with%20the%20official%20openai%20Python%20SDK%3A%0A%0A-%20chat%20completions%20%28unary%20%2B%20streaming%20SSE%29%0A-%20function%20calling%20%28tools%5B%5D%20%2B%20tool_calls%5B%5D%20round-trip%29%0A-%20vision%20%28OpenAI%20content%20arrays%20with%20data%3Aimage%2F...%3Bbase64%2C...%29%0A-%20embeddings%20%28MLX-backed%2C%20experimental%29%0A%0ATwo-line%20swap%20on%20the%20client%3A%0A%0A%20%20%20%20client%20%3D%20OpenAI%28%0A%20%20%20%20%20%20%20%20base_url%3D%22http%3A%2F%2F127.0.0.1%3A11434%2Fv1%22%2C%0A%20%20%20%20%20%20%20%20api_key%3D%22not-required%22%2C%0A%20%20%20%20%29%0A%0AThree%20backends%20share%20the%20same%20surface%20%E2%80%94%20Apple%20FoundationModels%20%28native%2C%20iOS%2026%2B%29%2C%20CoreML%20%28iOS%2018%2B%29%2C%20MLX%20%28iOS%2017%2B%2C%20any%20mlx-community%2F%2A%20model%20including%20VLMs%29.%20MIT%2C%20SPM%20only.%0A%0ARepo%3A%20https%3A%2F%2Fgithub.com%2Fjohn-rocky%2FPrivateFoundationModels&kind=self)

## 5. Apple Developer Forums

Apple's forum doesn't expose a pre-fillable submit URL, so this one's a manual paste:

- Open: <https://developer.apple.com/forums/create-content?tags=foundation-models>
- Title + body in [`docs/apple-developer-forums-post.md`](apple-developer-forums-post.md)

---

## Why I can't post these myself

This Claude Code session doesn't have a Playwright MCP / X API / Reddit API / HN client wired in. ToolSearch over the deferred-tool list returns only WebFetch (read-only) and Google Drive auth. The pre-fill-and-click pattern above is the closest one-click hand-off I can produce from here.

If you want me to actually post end-to-end in a future session, add one of these to your Claude Code MCP config:

- `@playwright/mcp` (browser automation — fully scripted post)
- A custom Twitter MCP using your OAuth token
- `mcp-reddit` / `mcp-hn`

Then I can drive the form fills + submit clicks without you ever touching a keyboard.
