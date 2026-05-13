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

## Embeddings (experimental)

`openai_embeddings_demo.py` calls `/v1/embeddings` via the official SDK:

```python
resp = client.embeddings.create(model="mlx-embedder", input=texts)
```

Requires `pfm-serve-mlx --embedding-model <repo>` so an MLX-backed `EmbeddingBackend` is installed. The endpoint returns 503 with a clear message when no embedder is configured. The MLX embedder is **experimental** — built and wired, but the per-model preprocessing (padding / mask / pooling) hasn't been verified against every `mlx-community/*` embedding repo yet. Report bugs.

## Tool calling (function calling)

`openai_tools_demo.py` drives a two-turn function-calling interaction against `pfm-serve-apple`:

```
Round 1: assistant turn — tool_calls
  Tool call: add({'a': 17, 'b': 25})  →  42
Round 2: final answer — 42
```

The script passes a tool definition (`add(a, b)`) in the standard OpenAI `tools` shape, executes the tool locally when the model decides to call it, sends the result back as a `role: "tool"` message, and prints the model's final answer. All using the official SDK.

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
