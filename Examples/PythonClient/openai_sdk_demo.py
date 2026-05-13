"""Verify pfm-serve is byte-compatible with the official OpenAI Python SDK."""
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:11434/v1", api_key="not-required")

print("=" * 60)
print("Non-streaming chat completion via openai SDK")
print("=" * 60)
resp = client.chat.completions.create(
    model="apple-fm",
    messages=[
        {"role": "system", "content": "Be brief."},
        {"role": "user", "content": "In one sentence, what is async/await in Swift?"},
    ],
    max_tokens=60,
    temperature=0.0,
)
print(resp.choices[0].message.content)
print()

print("=" * 60)
print("Streaming chat completion via openai SDK (stream=True)")
print("=" * 60)
stream = client.chat.completions.create(
    model="apple-fm",
    messages=[{"role": "user", "content": "List three Swift concurrency primitives."}],
    max_tokens=120,
    temperature=0.0,
    stream=True,
)
for chunk in stream:
    if chunk.choices and chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
print()

print()
print("=" * 60)
print("Listing models via openai SDK")
print("=" * 60)
models = client.models.list()
for m in models.data:
    print(f"  - {m.id}  (owned_by={m.owned_by})")
