# Frequently asked questions

## Is this affiliated with Apple?

No. *Foundation Models* is Apple's trademark; this project is a community-maintained, source-compatible alternative. The goal is to let developers ship the same call site on iOS 18 (where Apple's framework isn't available) and on iOS 26 (where the same code can either route through PFM's CoreML / MLX backends or pass straight through to Apple's native model).

## Why not just wait for iOS 26?

Three reasons:
1. **Installed base.** iOS 26 won't reach majority share for ~12 months after release. PFM lets you build Apple-FM-shaped code today against the ~80% of devices that are on iOS 18 or older.
2. **Model choice.** Apple's framework is locked to Apple's 3 B on-device LLM. PFM lets you swap that for Gemma 4 / Qwen3.5 / LFM2.5 / Llama 3.2 / any `mlx-community/*` model.
3. **Adapter / fine-tune support.** Apple's framework allows limited adapters; PFM lets you bring your own LoRA / fine-tune freely.

## Does it work on iPhone / iPad / Vision Pro?

Yes. The CoreML backend is the one designed for iPhone — it runs on the Apple Neural Engine and is what `Examples/PFMSwitcher` ships. MLX works on any Apple Silicon device. The Apple FM passthrough works on iOS 26+ / macOS 26+ / visionOS 26+ devices with Apple Intelligence enabled.

## Can I use my own model?

Three paths:
1. **Convert it to CoreML** with [`john-rocky/CoreML-LLM`](https://github.com/john-rocky/CoreML-LLM)'s conversion scripts, publish to HuggingFace as `<your-name>/<model>-coreml`, and use `CoreMLLanguageModel.load(.custom("..."))`.
2. **Use an `mlx-community/*` MLX repo** directly via `MLXLanguageModel.load(.custom("..."))`. No conversion needed if it's already on the Hub.
3. **Implement `LanguageModelBackend`** yourself — protocol has two methods (`generate`, `streamGenerate`) plus an availability property. Useful for routing to llama.cpp, a remote API, or your own runtime.

## What about Gemma / Llama / Qwen / Mistral?

All work today.

- **Gemma 4 (E2B / E4B)**: CoreML, multimodal on E2B. `CoreMLLanguageModel.load(.gemma4E2B)`.
- **Qwen3.5 (0.8B / 2B)**: CoreML via `Qwen35MLKVGenerator`. `CoreMLLanguageModel.load(.qwen3_5_0_8B)`.
- **Qwen3-VL (2B Stateful)**: CoreML. Vision input on session API.
- **LFM2.5-350M**: CoreML. Smallest catalog model, fast on ANE.
- **FunctionGemma, EmbeddingGemma**: CoreML.
- **Llama 3.2, Qwen3, Gemma 2, Mistral 7B, Phi 3.5**: MLX via `MLXLanguageModel.load(.llama3_2_3B_4bit)` etc.
- **Qwen2.5-VL, Qwen2-VL**: MLX. Vision input. `.qwen25_VL_7B_4bit` / `.qwen2_VL_7B_4bit`.

## Does `@Generable` work on Apple's native model?

Yes, since v0.4.1. PFM translates its JSON-Schema-shaped `GenerationSchema` into Apple's `DynamicGenerationSchema` and feeds it through Apple's `respond(to:schema:)` path. The same `respond(to:generating: MyType.self)` call site that decodes JSON on CoreML / MLX decodes through Apple's native LLM on iOS 26+. See [`pfm-apple-deep`](Sources/PFMAppleDeep/main.swift) for the matrix and [`docs/pfm-apple-deep.log`](docs/pfm-apple-deep.log) for the result.

## Does `Tool` calling work on Apple's native model?

Yes, since v0.5.0. PFM `Tool` instances are wrapped at runtime in `PFMToolAdapter` (which conforms to `FoundationModels.Tool` with `Arguments = GeneratedContent`) and registered with Apple's session at construction. Apple's tool loop invokes the adapter; the adapter routes each `call(arguments:)` back through PFM's `AnyTool.invoke`, which JSON-decodes the model-supplied arguments into your PFM `Generable` struct and calls your `func call(arguments:)` exactly as the CoreML / MLX backends do.

Since v0.5.1, the per-turn `.toolCall` / `.toolOutput` entries are also reconstructed in PFM's `session.transcript` (Apple's loop is opaque, but its post-call `Transcript` snapshot exposes the entries — we translate them back).

## Why not include a llama.cpp backend?

It's on the v0.6 list. The current backends cover the Apple-runtime cases (ANE, GPU, native FM); adding llama.cpp would unlock the broader GGUF model ecosystem (`unsloth/*`, `bartowski/*`, etc.) and runtimes like `llama-cpp-swift`. PRs welcome.

## How do I prevent the model from making up JSON?

PFM today uses prompt-injection + post-process JSON extraction for `@Generable`. On Apple's native model, the schema is enforced via Apple's grammar-constrained sampler (`includeSchemaInPrompt: true` plus internal logit shaping). On CoreML / MLX, output is best-effort parsed; small models occasionally produce malformed JSON, which surfaces as `GenerationError.decodingFailure`. A proper grammar-constrained sampler (Outlines / LM Format Enforcer style) for CoreML / MLX is on the v0.6 list.

## What's the difference between "MODEL" and "FAIL" in your test reports?

- **PASS** — the API surface worked and the content matches the test's expectation.
- **MODEL** — the API surface worked, but the model's content didn't match expectation. Could be a small model declining to use a tool, producing an off-by-one number, or returning a different city name than the test fixture. Not a framework regression.
- **FAIL** — the API surface broke. Framework or backend regression. Zero is the only acceptable count.

## How is this related to `CoreML-LLM` / `mlx-swift-lm` / Apple's `FoundationModels`?

PFM is a thin Apple-FM-shaped layer on top of those:

```
PrivateFoundationModels  (this package — shapes the API)
  ├─ PrivateFoundationModelsApple  → FoundationModels.framework  (Apple)
  ├─ PrivateFoundationModelsCoreML → john-rocky/CoreML-LLM      (community)
  └─ PrivateFoundationModelsMLX    → ml-explore/mlx-swift-lm    (Apple's MLX team)
```

The backends do all the model-running work; PFM glues them to a unified Apple-FM-shaped surface.

## Can I run this on the simulator?

CoreML and MLX backends both work on the simulator (slow — the Neural Engine isn't available there, so CoreML falls back to CPU). The Apple FM backend requires a physical Apple Intelligence-eligible device on iOS 26+.

## Where do I report a bug?

[Open an issue](https://github.com/john-rocky/PrivateFoundationModels/issues/new). Include the backend, the model, the deep-harness output if you can produce one, and your hardware / OS / Xcode version.

## Where do I report a hot take about the design?

Same place. Strong opinions on the API shape are welcome; the goal is to stay byte-compatible with Apple's FoundationModels, but if Apple ships a new variation we'll mirror it.
