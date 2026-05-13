# PrivateFoundationModels

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjohn-rocky%2FPrivateFoundationModels%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/john-rocky/PrivateFoundationModels)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjohn-rocky%2FPrivateFoundationModels%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/john-rocky/PrivateFoundationModels)
[![CI](https://github.com/john-rocky/PrivateFoundationModels/actions/workflows/ci.yml/badge.svg)](https://github.com/john-rocky/PrivateFoundationModels/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**One call site. Three backends. On iOS 26 it runs Apple's native FoundationModels; on iOS 18 it runs your CoreML or MLX model.**

<p align="center">
  <img src="docs/media/pfm.gif" alt="PFMSwitcher demo: same LanguageModelSession code switching between Apple FoundationModels and LFM2.5-350M on the Neural Engine" width="320">
</p>

```swift
import PrivateFoundationModels
import PrivateFoundationModelsApple   // ← iOS 26+: Apple's native on-device model
import PrivateFoundationModelsCoreML  // ← iOS 18+: CoreML / Apple Neural Engine
import PrivateFoundationModelsMLX     // ← iOS 17+: mlx-community/* / Apple GPU

if #available(iOS 26.0, macOS 26.0, *), AppleFoundationModel.isAvailable {
    SystemLanguageModel.default = SystemLanguageModel(
        backend: AppleFoundationModel.load()           // Apple's real model
    )
} else {
    SystemLanguageModel.default = SystemLanguageModel(
        backend: try await CoreMLLanguageModel.load(.lfm2_5_350M)  // your fallback
    )
}

let session = LanguageModelSession(instructions: "Be brief.")
let reply = try await session.respond(to: "Capital of France?")
print(reply.content)
```

That `session.respond(to:)` is byte-for-byte the Apple FoundationModels call site. **On macOS 26 it returns "The capital of France is Paris." in 1.2 s through Apple's actual native LLM** (verified — see [`docs/pfm-apple-smoke.log`](docs/pfm-apple-smoke.log)). On iOS 18 the same call runs through CoreML (LFM2.5 / Gemma 4 / Qwen3.5 on the ANE) or MLX (any `mlx-community/*` model on the GPU). The application code never changes.

**Three runtimes — same `LanguageModelSession` surface, picked at install time**

| Backend | Product | Runtime | iOS / macOS | Model |
|---|---|---|---|---|
| Apple FoundationModels | `PrivateFoundationModelsApple` | Apple Intelligence native | **iOS 26 / macOS 26 / visionOS 26** | Apple's 3 B on-device LLM (locked) |
| CoreML | `PrivateFoundationModelsCoreML` | Apple Neural Engine | iOS 18 / macOS 15 / visionOS 2 | Gemma 4 / Qwen3.5 / Qwen3-VL / LFM2.5 / FunctionGemma / EmbeddingGemma |
| MLX | `PrivateFoundationModelsMLX` | Apple GPU (Metal) | iOS 17 / macOS 14 / visionOS 1 | any `mlx-community/*` repo — Llama, Qwen, Gemma, Mistral, Phi, VLMs |

**Verified on Mac, not aspirational** — five harnesses run green against real on-device models:

- [`docs/pfm-apple-smoke.log`](docs/pfm-apple-smoke.log) — Apple's native FoundationModels through PFM's API (load 0 s, respond 1.2 s, stream ✓)
- [`docs/pfm-verify.log`](docs/pfm-verify.log) — every public API path against CoreML LFM2.5 (10/10)
- [`docs/PORTABILITY.md`](docs/PORTABILITY.md) — Apple-FM-shaped call sites compile and run unchanged (8/8)
- [`docs/pfm-deep.log`](docs/pfm-deep.log) — Generable × Tool × Multimodal × PromptBuilder against CoreML (**PASS 7 / MODEL 4 / FAIL 0**)
- [`docs/pfm-mlx-deep.log`](docs/pfm-mlx-deep.log) — same matrix against MLX `mlx-community/Qwen3.5-0.8B-MLX-4bit` (**PASS 9 / MODEL 5 / FAIL 0**)

**Drop-in source compatibility with Apple `FoundationModels`** — the same code that uses Apple's framework on iOS 26 compiles unchanged against `PrivateFoundationModels` on iOS 18. The only diff is the `import` line plus a one-line backend install at app startup.

**First call downloads the CoreML / MLX model. No prep required.** `CoreMLLanguageModel.load(.lfm2_5_350M)` writes ~810 MB to `~/Library/Application Support/PrivateFoundationModels/lfm2.5-350m-coreml/` over a foreground URLSession; MLX uses HuggingFace's standard `~/.cache/huggingface/hub/` cache. The Apple FM backend uses no download — the model is built into the OS.

---

## Why this exists

Apple's `FoundationModels` framework is great. It also has three real constraints:

| | Apple `FoundationModels` (native) | `PrivateFoundationModels` |
|---|---|---|
| **Minimum OS** | iOS 26 / macOS 26 / visionOS 26 | iOS 18 / macOS 15 / visionOS 2 (CoreML), or iOS 26 (native passthrough) |
| **Model** | Apple's 3 B on-device model, locked | Any CoreML / MLX / GGUF bundle, *or* Apple's own when available |
| **Adapter support** | Limited, ~90% context budget burned by adapter | Bring your own LoRA / fine-tune |
| **Domain coverage** | Apple-recommended only — coding, math, general Q&A all officially discouraged | Whatever your chosen model is good at |
| **API surface** | `LanguageModelSession` / `Instructions` / `Tool` / `Generable` | Same names, same shapes — and on iOS 26 the same calls reach Apple's native model |

PFM is not a competitor to Apple FoundationModels; it's the **iOS 18 polyfill that becomes a runtime passthrough on iOS 26**. The day your deployment target jumps to iOS 26 you can either delete PFM (`s/PrivateFoundationModels/FoundationModels/`) or keep it for the older-OS support, the CoreML / MLX fallback, and the bring-your-own-model story.

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/john-rocky/PrivateFoundationModels", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "PrivateFoundationModels",        package: "PrivateFoundationModels"),
            .product(name: "PrivateFoundationModelsCoreML", package: "PrivateFoundationModels"),
        ]
    )
]
```

Four products:

- **`PrivateFoundationModels`** — the API surface (`LanguageModelSession`, `Instructions`, …). Zero runtime deps. Import this everywhere.
- **`PrivateFoundationModelsApple`** — passthrough to Apple's native FoundationModels framework on iOS 26+ / macOS 26+. Zero runtime deps beyond the system framework. Full feature parity with the CoreML / MLX backends: text + streaming text + `@Generable` structured output + streaming Generable + `Tool` calling via runtime adapter.
- **`PrivateFoundationModelsCoreML`** — CoreML / ANE backend. Depends on [`john-rocky/CoreML-LLM`](https://github.com/john-rocky/CoreML-LLM), which runs Gemma 4 / Qwen3.5 / Qwen3-VL / LFM2.5 / FunctionGemma / EmbeddingGemma on the Apple Neural Engine. Import only in the target that wires `SystemLanguageModel.default`.
- **`PrivateFoundationModelsMLX`** — MLX backend. Depends on [`ml-explore/mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm), which runs any `mlx-community/*` model — Llama, Qwen, Gemma, Mistral, Phi — on Apple Silicon GPU. Same `LanguageModelSession.respond(...)` API as the CoreML and Apple backends.

All four are pure SPM. No CocoaPods. No special build phase. No model files in the repo — CoreML / MLX backends download on first call; the Apple backend uses the OS-bundled model.

You can also wire your own `LanguageModelBackend` (llama.cpp, a remote API, etc.) — see [Bring your own backend](#bring-your-own-backend) below.

### Apple FoundationModels backend (iOS 26+ / macOS 26+ / visionOS 26+)

When your deployment target reaches iOS 26 — or when you ship an app that supports both iOS 18 and iOS 26 — the same call site can route to **Apple's actual on-device model** (the one that powers Apple Intelligence rewriting, summarization, and smart reply) without any code change beyond the install line:

```swift
import PrivateFoundationModels
import PrivateFoundationModelsApple

if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *),
   AppleFoundationModel.isAvailable {
    SystemLanguageModel.default = SystemLanguageModel(
        backend: AppleFoundationModel.load()
    )
}

let session = LanguageModelSession(instructions: Instructions("Be brief."))
print(try await session.respond(to: "Capital of France?").content)
// "The capital of France is Paris."  — from Apple's native model in 1.2 s
```

`AppleFoundationModel.availability` mirrors Apple's `SystemLanguageModel.default.availability` (`available`, `unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`) so app code can branch on it without importing FoundationModels directly.

**`@Generable` structured output and `Tool` calling both work on Apple's native model.** PFM's `GenerationSchema` (JSON-Schema-shaped) is translated into Apple's `DynamicGenerationSchema` and fed into `respond(to:schema:)`. PFM `Tool` instances are wrapped in a runtime `PFMToolAdapter` that conforms to `FoundationModels.Tool` and routes each `call(arguments:)` back through PFM's `AnyTool.invoke`. The same `respond(to:generating:tools:)` call site that runs against CoreML on iOS 18 runs against Apple's native LLM on iOS 26+:

```swift
@Generable
struct Address {
    let city: String
    let country: String
}

let response = try await session.respond(
    to: "Pick one famous landmark and return its city and country.",
    generating: Address.self
)
print(response.content)  // Address(city: "Paris", country: "France") — from Apple's model
```

Verified on macOS 26.0 — `pfm-apple-deep` runs **PASS 14 / MODEL 0 / FAIL 0** across the full Generable × Tool × Multimodal × PromptBuilder matrix. See [`docs/pfm-apple-deep.log`](docs/pfm-apple-deep.log). The throwing-tool scenario specifically proves the bridge: Apple's session called PFM's `boom` tool with the model-supplied arguments, the tool threw `Boom`, Apple wrapped it in `ToolCallError`, the backend unwrapped to `underlyingError`, and PFM saw `GenerationError.backend(Boom)` — identical to CoreML / MLX.

The Apple backend also reconstructs the per-turn audit trail: it snapshots `session.transcript` before and after the call, translates the new Apple-side `.toolCalls` / `.toolOutput` entries back into PFM `Transcript.Entry` values, and returns them via `BackendGeneration.transcriptDelta`. The session appends those before recording the final `.response`, so `session.transcript` looks the same on all three backends after a tool turn:

```
[prompt: "What is 17 + 25?", toolCall: add({"a":17,"b":25}), toolOutput: "42", response: "17 plus 25 is 42."]
```

### MLX backend (alternative)

If you'd rather route generation to MLX-Swift instead of CoreML — same API, different runtime:

```swift
import PrivateFoundationModels
import PrivateFoundationModelsMLX

SystemLanguageModel.default = SystemLanguageModel(
    backend: try await MLXLanguageModel.load(.qwen3_4B_4bit)
)

let session = LanguageModelSession(instructions: "Be brief.")
print(try await session.respond(to: "Capital of France?").content)
```

Text-only catalog: `.qwen3_4B_4bit`, `.llama3_2_3B_4bit`, `.gemma2_2B_4bit`, `.mistral7B_4bit`, `.phi3_5_mini_4bit`. Vision-language catalog (lit up by linking MLXVLM, requires no extra import in app code): `.qwen25_VL_7B_4bit`, `.qwen2_VL_7B_4bit`. Anything else goes through `.custom("mlx-community/<repo>")` — `loadModelContainer(id:)` tries the VLM factory first and falls back to the LLM factory, so vision-capable repos auto-route correctly. First call downloads via the HuggingFace Hub client (the standard `~/.cache/huggingface/hub/` cache); subsequent calls resolve from disk.

End-to-end smoke test on Apple M4 Max, against `mlx-community/Qwen3.5-0.8B-MLX-4bit`: load 2.0 s, `respond(to:)` 1.4 s, `streamResponse(to:)` works. See [`docs/pfm-mlx-smoke.log`](docs/pfm-mlx-smoke.log). The full Generable × Tool × Multimodal × PromptBuilder matrix in [`pfm-mlx-deep`](Sources/PFMMLXDeep/main.swift) (the same scenarios `pfm-deep` runs against CoreML) returns **PASS 9 / MODEL 5 / FAIL 0** on the MLX side — including 7 incremental snapshots from streaming `Generable`. See [`docs/pfm-mlx-deep.log`](docs/pfm-mlx-deep.log).

> **Build note:** MLX-Swift uses Metal shader compilation, which the SPM CLI (`swift run`) can't perform. Build executables that import `PrivateFoundationModelsMLX` with `xcodebuild` or from inside Xcode. iOS / macOS apps built via Xcode are unaffected.

### Model download

`CoreMLLanguageModel.load(...)` populates the model directory on the first call using a foreground URLSession; the second call sees every file already on disk and skips straight to the load step.

```swift
let backend = try await CoreMLLanguageModel.load(
    .lfm2_5_350M,
    cacheDirectory: nil,           // optional override; defaults to Application Support
    hfToken: nil,                  // optional, for gated repos
    onProgress: { print($0) }      // per-file events ("[3/12] hf_model/tokenizer.json (4.5 MB)")
)
```

Default cache path: `~/Library/Application Support/PrivateFoundationModels/<repo-basename>/`.

You don't need `huggingface-cli` installed, you don't need to pre-populate anything, and you don't need an iOS app context — the fetcher is a vanilla foreground `URLSession`. The CoreML-LLM upstream's background-`URLSession` downloader (which doesn't work from a plain CLI / Xcode Preview / unit-test process) is bypassed entirely.

If a download is interrupted, re-running picks up where it left off — files whose on-disk size matches the HuggingFace-reported size are skipped per-file.

---

## Quick tour

### Stateful chat

```swift
let session = LanguageModelSession(instructions: "Be terse.")

_ = try await session.respond(to: "Who wrote The Tale of Genji?")
_ = try await session.respond(to: "And in what century?")
// The second call sees the first in `session.transcript`.
```

### Streaming

```swift
let stream = session.streamResponse(to: "Write a haiku about autumn.")
for try await snapshot in stream {
    print(snapshot.content) // cumulative, not deltas
}
let final = try await stream.collect()
```

`streamResponse(to:generating:)` emits **partial decodes of the Generable** as soon as enough of the JSON is on the wire to parse a prefix — fields populate one at a time, optionals stay `nil` until they're written, mirroring Apple's `Snapshot<T>` cadence. See [`PartialJSONParserTests.streamingGenerableEmitsIncrementalSnapshots`](Tests/PrivateFoundationModelsTests/PartialJSONParserTests.swift) for the exact emission semantics.

### Vision input (multimodal)

```swift
import UIKit  // or AppKit

let backend = try await CoreMLLanguageModel.load(.gemma4E2B)
SystemLanguageModel.default = SystemLanguageModel(backend: backend)

let session = LanguageModelSession(instructions: "Describe images precisely.")
let image: CGImage = UIImage(named: "scene")!.cgImage!

let reply = try await session.respond(to: "What's in this photo?", image: image)
// or stream it:
for try await snapshot in session.streamResponse(to: "Describe.", image: image) {
    print(snapshot.content)
}
```

`respond(to:image:)` and `streamResponse(to:image:)` plumb a `CGImage` through to backends that override the multimodal entry point. Text-only backends (Apple FM on iOS 26, LFM2.5, the Qwen3.5 text family) fall back to a text-only completion silently — the `image:` argument is ignored. Vision-capable backends in v0.2: Gemma 4 E2B (the multimodal build of `mlboydaisuke/gemma-4-E2B-coreml`). Qwen3-VL routing lands in v0.3.

### Structured output

```swift
@Generable
struct CityReport {
    @Guide(description: "City name")
    let city: String
    let temperatureCelsius: Double
    let conditions: String
}

let report = try await session.respond(
    to: "Make up plausible weather for Tokyo in November.",
    generating: CityReport.self
)
print(report.content.temperatureCelsius)
```

`@Generable` is the same macro shape Apple ships in `FoundationModels` — it walks stored properties, picks a JSON-Schema type per field, drops `Optional` fields out of `required`, and recurses into nested `@Generable` types. `@Guide(description:)` is also supported. If you prefer to write the schema by hand (no macro), conform to `Generable` and supply `static var generationSchema` directly.

**Reliability:** if the model returns text that doesn't parse as `T` on the first try, `respond(to:generating:)` automatically retries up to `maximumRetries` more times (default 2) with a tightened schema-reminder prompt. Override with `maximumRetries: 0` to lock in single-shot Apple-FM-strict behavior. Apple's native backend rarely trips this because its constrained sampler enforces the schema directly; the CoreML and MLX backends benefit when small models occasionally emit invalid JSON.

### Tools

```swift
struct LookupTool: Tool {
    struct Arguments: Generable {
        let city: String
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: ["city": .init(type: "string")],
                required: ["city"]
            )
        }
    }
    let name = "lookup_weather"
    let description = "Returns the current temperature in °C for a city."
    func call(arguments: Arguments) async throws -> String {
        // Hit your real API here.
        "22"
    }
}

let session = LanguageModelSession(
    tools: [LookupTool()],
    instructions: "Use lookup_weather when asked about temperature."
)
let reply = try await session.respond(to: "How warm is it in Tokyo?")
```

Tool calls and tool outputs are recorded in `session.transcript` as `.toolCall` / `.toolOutput` entries so the conversation survives serialization.

### Persisting and restoring

```swift
let json = try session.transcript.serialized()
try json.write(to: url)
// ... later ...
let restored = try Transcript(serialized: Data(contentsOf: url))
let session = LanguageModelSession(transcript: restored)
```

### Sampling

```swift
let options = GenerationOptions(
    sampling: .random(top: 40, probabilityThreshold: 0.95, seed: 42),
    temperature: 0.7,
    maximumResponseTokens: 256
)
let answer = try await session.respond(to: "Tell me a story.", options: options)
```

---

## Model catalog

The CoreML backend ships with these defaults (see [`CoreMLLanguageModel.Catalog`](Sources/PrivateFoundationModelsCoreML/CoreMLLanguageModel.swift)):

| Catalog case | HuggingFace repo | Size | iPhone 17 Pro decode | Status |
|---|---|---|---|---|
| `.lfm2_5_350M` | `mlboydaisuke/lfm2.5-350m-coreml` | 810 MB | ~52 tok/s | ✅ verified |
| `.gemma4E2B` | `mlboydaisuke/gemma-4-E2B-coreml` | 5.4 GB | ~34 tok/s | ✅ chunked path |
| `.gemma4E4B` | `mlboydaisuke/gemma-4-E4B-coreml` | 5.5 GB | ~14 tok/s | ✅ chunked path |
| `.qwen3_5_0_8B` | `mlboydaisuke/qwen3.5-0.8B-CoreML` | 1.2 GB | ~48 tok/s | ✅ verified (v0.2, via `Qwen35MLKVGenerator`) |
| `.qwen3_5_2B` | `mlboydaisuke/qwen3.5-2B-CoreML` | 2.8 GB | ~27 tok/s | ✅ same path as 0.8B |
| `.qwen3VL2BStateful` | `mlboydaisuke/qwen3-vl-2b-stateful-coreml` | 2.3 GB | ~24 tok/s | ⚠ needs vision input on session API (v0.3) |

Numbers from CoreML-LLM's published benchmarks. Any other CoreML bundle that CoreML-LLM can load via `CoreMLLLM.load(repo:)` works via `.custom("user/repo-coreml")`. The Qwen3.5 family is served by `Qwen3Backend`, which wraps `Qwen35MLKVGenerator` and pulls the tokenizer from the source HuggingFace repo (the mlboydaisuke CoreML repos don't ship tokenizer files).

---

## Bring your own backend

`SystemLanguageModel` doesn't care how text is generated — it talks to a `LanguageModelBackend`. Implement two methods (`generate(...)` and `streamGenerate(...)`), and an `availability` property, and you can route the same Apple-FM-shaped surface to MLX-Swift, llama.cpp, a private inference server, or a remote API.

```swift
struct MyMLXBackend: LanguageModelBackend {
    let modelIdentifier = "mlx/my-finetune"
    var availability: SystemLanguageModel.Availability { .available }

    func prewarm() async { /* ... */ }

    func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        let text = try await myMLXEngine.run(prompt: render(transcript))
        return BackendGeneration(text: text)
    }

    func streamGenerate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> AsyncThrowingStream<BackendDelta, Error> {
        AsyncThrowingStream { /* ... */ }
    }
}

SystemLanguageModel.default = SystemLanguageModel(backend: MyMLXBackend())
```

The session takes care of the transcript, the tool-call loop, and the `Generable` decode. Backends only have to render → run → emit text or a `toolCalls` array.

---

## Compatibility with `FoundationModels`

This package mirrors the public API surface of `FoundationModels` (iOS 26+) as of WWDC 2025 and the documentation available at the time of writing. Type names, initializer shapes, and method signatures match. A non-exhaustive list of what's implemented:

- `LanguageModelSession` — `respond(to:)`, `respond(to:generating:)`, `streamResponse(to:)`, `streamResponse(to:generating:)`, `prewarm()`, `transcript`, `isResponding`
- `Instructions`, `GenerationOptions`, `SamplingMode`
- `Response<Content>`, `ResponseStream<Content>` (AsyncSequence with `Snapshot`)
- `Transcript` + `Transcript.Entry` (Codable)
- `Tool` protocol, `AnyTool` type-erased wrapper
- `Generable` protocol with `GenerationSchema`
- `SystemLanguageModel` with `Availability` / `UnavailableReason`
- `GenerationError` matching Apple's case names where they exist

Things Apple's `FoundationModels` ships that we do **not** ship today, and explicitly do not promise:

- `Prompt` value type and the `respond(options:prompt:)` / `streamResponse(options:prompt:)` overloads that take it — v0.2.
- `Guardrails` (silent no-op accept-all today) — v0.2.
- `logFeedbackAttachment(...)` — v0.2+.
- Apple Intelligence-specific behavior (rewriting in Mail, image playgrounds). Those are app-level features, not framework surface.

If you find a method or initializer in Apple's docs that PFM doesn't ship, please open an issue.

---

## What this package is *not*

- **Not affiliated with Apple.** "Foundation Models" is Apple's trademark; this project is a community-maintained API-compatible alternative.
- **Not a model.** It's a thin Swift surface that delegates to whatever backend you wire up.
- **Not a grammar-constrained sampler.** When you ask for a `Generable` response, we feed the schema to the model as part of the system prompt and post-process. For deterministic schema enforcement, use a backend that supports a constrained sampler (Outlines, LM Format Enforcer, Apple FM's own grammar mode).

---

## Tutorial

New here? Read the [5-minute walkthrough](docs/TUTORIAL.md). It takes you from `swift package init` to streaming `@Generable` output through Apple's native model.

Already on Apple FM? See [Migrating from `FoundationModels`](docs/MIGRATING_FROM_APPLE_FM.md) — a five-step recipe for bringing your iOS 26 code back to iOS 18 (or shipping both deployment targets from one codebase).

## FAQ

Common questions in [`docs/FAQ.md`](docs/FAQ.md). Highlights:

- *Is this affiliated with Apple?* — No.
- *Why not wait for iOS 26?* — installed base, model choice, adapter support.
- *Does `@Generable` work on Apple's native model?* — yes since v0.4.1.
- *Does `Tool` calling work on Apple's native model?* — yes since v0.5.0, with full transcript audit trail since v0.5.1.

## Changelog

Tagged releases on GitHub plus a high-level rollup in [`CHANGELOG.md`](CHANGELOG.md).

## Examples

- [`Examples/PFMChat/`](Examples/PFMChat/) — single-file SwiftUI chat app (~200 lines). Loads `mlboydaisuke/lfm2.5-350m-coreml`, streams responses.
- [`Examples/PFMSwitcher/`](Examples/PFMSwitcher/) — production-shaped chat app that **switches between Apple `FoundationModels` (iOS 26+) and any CoreML catalog model** with a single picker. Demonstrates the strict release-before-load pattern needed when one of the resident models is 5+ GB on ANE. Includes live RSS readout and a `didReceiveMemoryWarningNotification` handler.

## Verified

Captured on Apple M4 Max / macOS 26.0 / Swift 6.2.1 / Xcode 26.1, against `mlboydaisuke/lfm2.5-350m-coreml` (CoreML / ANE), `mlx-community/Qwen3.5-0.8B-MLX-4bit` (MLX / GPU), and Apple's own on-device model (Apple Intelligence enabled):

| Harness | What it proves | Result |
|---|---|---|
| `swift test` | Session logic, schema decoder, tool dispatch, error wrapping — all stub-backed for determinism | **90 / 90 pass** ([deep tests](docs/DEEP_VERIFICATION.md)) |
| `swift run -c release pfm-verify` | Every public API path against a real CoreML model | **10 / 10 pass** ([log](docs/pfm-verify.log)) |
| `swift run -c release pfm-portability` | Real Apple-FM-shaped code compiled and ran unchanged | **8 / 8 pass** ([log](docs/pfm-portability.log)) |
| `swift run -c release pfm-deep` | Every Generable shape × Tool pattern against the real CoreML model | **PASS 7 / MODEL 4 / FAIL 0** ([log](docs/pfm-deep.log)) |
| `pfm-mlx-deep` (xcodebuild) | Same scenario matrix routed through MLX-Swift on a real `mlx-community/*` model | **PASS 9 / MODEL 5 / FAIL 0** ([log](docs/pfm-mlx-deep.log)) |
| `swift run -c release pfm-apple-smoke` | `respond(to:)` + `streamResponse(to:)` + **Generable** through PFM hitting **Apple's actual native FoundationModels** | ✓ load 0 s, ✓ respond 0.7 s, ✓ stream, ✓ Generable 1.3 s ([log](docs/pfm-apple-smoke.log)) |
| `swift run -c release pfm-apple-deep` | Full Generable × Tool × Multimodal × PromptBuilder matrix through PFM hitting Apple's native FoundationModels, with transcript reconstruction so tool turns appear in `session.transcript` | **PASS 14 / MODEL 0 / FAIL 0** ([log](docs/pfm-apple-deep.log)) |

Standardized `streamResponse` bench on M4 Max / macOS 26.0 (median of 3 timed iterations, same prompt + 80-token cap, one warmup, see [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)):

| Backend | Load | TTFT | Total | Output chars | Throughput |
|---|---|---|---|---|---|
| Apple FM (Apple's 3 B) | 0 ms | 297 ms | 582 ms | 147 | 252.7 chars/s |
| CoreML / ANE (LFM2.5-350M) | 8235 ms | 533 ms | 648 ms | 25 | 38.6 chars/s |
| CoreML / ANE (Qwen3.5-0.8B) | 13018 ms | 530 ms | 1954 ms | 303 | 155.1 chars/s |
| MLX / GPU (Qwen3.5-0.8B 4-bit) | 997 ms | **42 ms** | **108 ms** | 89 | **821.2 chars/s** |

`MODEL` = API works, content quality limited by the small model used for verification (a larger model lands the test in PASS). `FAIL` = framework / backend regression — zero is the only acceptable number across every backend.

## Roadmap

- v0.1 — Core API + CoreML backend + foreground HF fetcher
- v0.1.1 — `@Generable` macro + `@Guide(description:)`
- v0.2 — Qwen3.5 routing + `Prompt` / `@PromptBuilder` /
  `Guardrails` parity + vision input on the session API
- v0.3 — Streaming `Generable` partial-snapshot decode +
  MLX-Swift backend (`mlx-community/*` models, including `*-VL-*` VLMs)
- v0.4 — Apple FoundationModels passthrough backend
  (`PrivateFoundationModelsApple`): on iOS 26+ / macOS 26+ /
  visionOS 26+ the same call site routes to Apple's actual native
  on-device model.
- v0.4.1 — `@Generable` structured output cross-translation
  for Apple FM (PFM `GenerationSchema` → Apple `DynamicGenerationSchema`,
  Apple `GeneratedContent` → JSON for PFM's decoder).
- v0.5.0 — `Tool` cross-translation for Apple FM via
  runtime `PFMToolAdapter`; PFM tools are exposed to Apple's
  session, called automatically by Apple's tool loop, and thrown
  errors are unwrapped from `ToolCallError` before reaching the
  caller.
- v0.5.1 — Transcript reconstruction through Apple's
  opaque tool loop: the backend translates Apple's post-call
  `.toolCalls` / `.toolOutput` entries back to PFM
  `Transcript.Entry` values and returns them via
  `BackendGeneration.transcriptDelta`. `pfm-apple-deep` PASS 14 / FAIL 0.
- v0.5.2 — Standardized `pfm-bench-{apple,coreml,mlx}` harness.
  Apples-to-apples M4 Max baseline in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).
- **v0.6.0 (current)** — `respond(to:generating:T.self)` auto-retries
  on `decodingFailure` (default 2 retries, configurable via
  `maximumRetries:`). Retry prompts append a schema reminder.
  Reliability win for small CoreML / MLX models without needing a
  grammar-constrained sampler. Apple FM backend never trips it
  because Apple's constrained sampler enforces the schema natively.
- v0.7 — Qwen3-VL routing on CoreML, grammar-constrained sampler
  behind a feature flag, llama.cpp / GGUF backend.
- v0.6 — llama.cpp / GGUF backend
- v0.7 — Grammar-constrained decoding
- v0.8 — Audio input on the session API + speculative decoding
- v0.9 — LoRA / adapter hot-swap, benchmark harness, observability

---

## Author

[Daisuke Majima](https://github.com/john-rocky) ([@JackdeS11](https://x.com/JackdeS11)) — ex-Ultralytics, founder of [Pebble Inc.](https://pebble.co.jp). Maintainer of [`CoreML-Models`](https://github.com/john-rocky/CoreML-Models) (1.7k★), [`CoreML-LLM`](https://github.com/john-rocky/CoreML-LLM), and the [`mlboydaisuke`](https://huggingface.co/mlboydaisuke) Apple Silicon model collection on Hugging Face.

Open to consulting on Apple Silicon LLM inference, on-device deployment, and CoreML / MLX optimization — [pebble.co.jp](https://pebble.co.jp).

## License

MIT. See [LICENSE](LICENSE). Model weights inherit their own licenses (Gemma: Gemma Terms; Qwen: Apache 2.0; LFM2.5: LFM Open License v1.0).
