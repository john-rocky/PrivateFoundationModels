# Python client examples — `openai` SDK against pfm-serve

The `pfm-serve-*` family speaks the OpenAI HTTP shape closely enough that the **official `openai` Python SDK works unchanged**. No proxy, no monkey-patch, no PFM-specific client. Just point `base_url` at your local server and go.

## Quick start

```bash
# 1. In one shell, run a PFM server (Apple FM shown; coreml / mlx also work).
swift run -c release pfm-serve-apple

# 2. In another shell, install the openai SDK and run the demo.
python3 -m venv .venv && source .venv/bin/activate
pip install openai
python openai_sdk_demo.py
```

## Real output

Captured against Apple's on-device LLM on macOS 26.0 / Apple M4 Max:

```
============================================================
Non-streaming chat completion via openai SDK
============================================================
Async/await in Swift is a concurrency feature that allows asynchronous code to be
written in a synchronous style, enabling cleaner and more readable asynchronous
operations.

============================================================
Streaming chat completion via openai SDK (stream=True)
============================================================
Swift provides several concurrency primitives that allow developers to handle
asynchronous tasks efficiently. Here are three key ones:

1. **Task**:
   - `Task` is a higher-order type that represents an asynchronous operation.
   ...

============================================================
Listing models via openai SDK
============================================================
  - apple-fm  (owned_by=pfm)
```

## What it proves

- `client.chat.completions.create(...)` — full OpenAI shape, system + user roles, `max_tokens`, `temperature`.
- `client.chat.completions.create(stream=True)` — chunk iteration with `chunk.choices[0].delta.content` matches the official SDK's expected `chat.completion.chunk` shape.
- `client.models.list()` — model directory.

If your existing Python project already targets the OpenAI API, you can flip it onto Apple's on-device model by changing two lines:

```python
client = OpenAI(
    base_url="http://127.0.0.1:11434/v1",   # was: https://api.openai.com/v1
    api_key="not-required",                 # was: your OpenAI key
)
```
