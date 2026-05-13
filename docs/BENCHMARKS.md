# Benchmarks

Numbers captured on **Apple M4 Max / macOS 26.0 / Xcode 26.1.1 / Swift 6.2.1**, release build, with Apple Intelligence enabled and all model caches warm.

## End-to-end `respond(to:)` (single-shot, low latency)

Prompt: `"In one short sentence, what is the capital of France?"`. Temperature = 0. `maximumResponseTokens` set so the model produces ~10 short-sentence output tokens.

| Backend | Product | Model | Load time | `respond(to:)` |
|---|---|---|---|---|
| Apple FM (native) | `PrivateFoundationModelsApple` | Apple Intelligence on-device LLM (3 B) | ≈0 ms (built into OS) | **641 ms** |
| CoreML / ANE | `PrivateFoundationModelsCoreML` | LFM2.5-350M | 2624 ms | **564–847 ms** |
| MLX / GPU | `PrivateFoundationModelsMLX` | Qwen3.5-0.8B 4-bit | 2093 ms | **170 ms** |

Raw logs:
- [`docs/pfm-apple-smoke.log`](pfm-apple-smoke.log)
- [`docs/pfm-verify.log`](pfm-verify.log)
- [`docs/pfm-mlx-smoke.log`](pfm-mlx-smoke.log)

## How to read these numbers

- **Apple FM** has the lowest cold-start cost because the model is shipped with the OS — there's no download and effectively no load-time. Its single-shot `respond(to:)` is fast for a model in its weight class, but the model isn't tunable (you get Apple's on-device LLM, period).
- **CoreML / ANE** trades off a higher cold-start cost (model paging) against a smaller binary footprint per app and a deep Neural-Engine acceleration path. Best for shipping a model your app fully owns.
- **MLX / GPU** has the most flexibility (any `mlx-community/*` repo) at the cost of GPU-shader build steps and a HuggingFace-style download. Best for development, research, and bring-your-own-model production.

## Reproducing

```bash
# Apple FM (macOS 26+, Apple Intelligence on)
swift run -c release pfm-apple-smoke

# CoreML
swift run -c release pfm-verify --model lfm2.5-350m --only generate

# MLX  (xcodebuild — SPM CLI can't compile Metal shaders)
xcodebuild -scheme pfm-mlx-smoke -destination "platform=macOS" -skipMacroValidation -configuration Release build
$(find ~/Library/Developer/Xcode/DerivedData -name pfm-mlx-smoke -type f | head -1)
```

## Caveats

These numbers are preliminary. The prompts and `maximumResponseTokens` differ across the three runs, so the `respond(to:)` cells are **not** apples-to-apples — they're individual ballpark measurements. A proper standardized harness (`pfm-bench` that runs the same prompt × the same token budget × N iterations across the three backends and reports time-to-first-token and tokens-per-second) is on the v0.6 list.

PRs that add numbers for other hardware (iPhone, iPad, M-series Macs other than M4 Max, Apple Vision Pro) are welcome — open one with the raw log appended.
