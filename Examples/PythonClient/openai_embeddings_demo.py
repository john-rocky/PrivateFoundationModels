"""Verify /v1/embeddings against pfm-serve-mlx (with an embedder loaded).

Start the server pointed at any mlx-community/* embedder, then run this:

    # Build via xcodebuild (MLX uses Metal shaders):
    xcodebuild -scheme pfm-serve-mlx -configuration Release \\
        -destination "platform=macOS" -skipMacroValidation build

    # Launch the MLX server with an embedding model:
    $(find ~/Library/Developer/Xcode/DerivedData -name pfm-serve-mlx -path "*Release*" -type f | head -1) \\
        --model mlx-community/Qwen3.5-0.8B-MLX-4bit \\
        --embedding-model mlx-community/gemma-3-1b-it-qat-4bit

    # Then drive it through the openai SDK:
    python openai_embeddings_demo.py
"""
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:11434/v1", api_key="not-required")

texts = [
    "Swift is Apple's modern programming language.",
    "GPT models are autoregressive transformers.",
    "FoundationModels exposes on-device LLMs to iOS 26 apps.",
]

resp = client.embeddings.create(model="mlx-embedder", input=texts)
print(f"Got {len(resp.data)} vectors, dim={len(resp.data[0].embedding)}")
print(f"Model: {resp.model}")
print()
print("First 8 components of each vector:")
for i, datum in enumerate(resp.data):
    head = ", ".join(f"{x:+.4f}" for x in datum.embedding[:8])
    print(f"  {i}: [{head}, ...]")
