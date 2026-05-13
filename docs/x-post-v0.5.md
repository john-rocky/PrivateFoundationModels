# X (Twitter) post — v0.5.0 launch (Apple FM at full parity)

Account: @JackdeS11
Repo: https://github.com/john-rocky/PrivateFoundationModels
Release: https://github.com/john-rocky/PrivateFoundationModels/releases/tag/v0.5.0

## Recommended single tweet

> PrivateFoundationModels v0.5 — three Swift backends, same `LanguageModelSession.respond(to:)` call site:
>
> · iOS 26+: Apple's native FoundationModels (Apple Intelligence)
> · iOS 18+: CoreML / Apple Neural Engine (LFM2.5, Gemma 4, Qwen3.5…)
> · iOS 17+: MLX / GPU (any mlx-community/* model, LLM + VLM)
>
> @Generable + Tools work on all three. Verified.
>
> https://github.com/john-rocky/PrivateFoundationModels

(Attach video: screen-record `pfm-apple-deep` finishing with `PASS 10 / MODEL 4 / FAIL 0`. ~6 seconds.)

## Thread version

### 1. The hook

> v0.5 of PrivateFoundationModels ships. The same Apple-FM-shaped `LanguageModelSession.respond(...)` code runs on:
>
> · iOS 26+ — Apple's actual native on-device model (Apple Intelligence)
> · iOS 18+ — CoreML on the Apple Neural Engine
> · iOS 17+ — MLX-Swift on the GPU
>
> Drop-in source-compatible.

### 2. The proof

> Verified on macOS 26.0 / Xcode 26.1 against Apple's native model — full Generable × Tool × Multimodal matrix:
>
> ```
> PASS  10
> MODEL  4
> FAIL   0
> ```
>
> All 6 @Generable shapes pass. Throwing-tool scenario: Apple's session called my Swift tool, it threw, the wrapped error unwound exactly as on CoreML/MLX.

### 3. The install

> ```swift
> import PrivateFoundationModels
> import PrivateFoundationModelsApple
>
> if #available(iOS 26.0, *), AppleFoundationModel.isAvailable {
>     SystemLanguageModel.default = SystemLanguageModel(
>         backend: AppleFoundationModel.load()
>     )
> }
>
> @Generable struct Address { let city: String; let country: String }
>
> let r = try await session.respond(
>     to: "Famous landmark — city, country?",
>     generating: Address.self
> )
> print(r.content)   // Address(city: "Paris", country: "France")
> ```

### 4. The why

> Why bother?
>
> 1. Apple FM is gated to iOS 26. PFM gives you the same surface on iOS 18 (today's installed base).
> 2. Apple FM is locked to Apple's 3 B model. PFM lets you swap to Gemma 4 / Qwen3.5 / LFM2.5 / Llama 3.2 / any mlx-community model.
> 3. When you bump to iOS 26 you can either keep PFM (older-OS support + your own models) or `s/PrivateFoundationModels/FoundationModels/`. Either way your code didn't change.

### 5. The link

> MIT licensed. SPM only. 90 / 90 stub tests + real-model deep-matrix harnesses on every backend.
>
> https://github.com/john-rocky/PrivateFoundationModels
>
> Built by @JackdeS11. Grateful to @apple's FoundationModels team and @AwniHannun + the MLX crew.

---

## Hacker News title

`PrivateFoundationModels: one Apple-FM API, three on-device backends — iOS 18+ polyfill that becomes a native passthrough on iOS 26`

(Submit URL: https://github.com/john-rocky/PrivateFoundationModels — let the README do the work.)

---

## Reddit r/swift submission

Title: `PrivateFoundationModels v0.5 — Apple FoundationModels API on iOS 18, native passthrough on iOS 26, CoreML / MLX backends in between`

Body:

> Hey r/swift — I just shipped v0.5 of PrivateFoundationModels, a Swift package that mirrors Apple's `FoundationModels` API surface on iOS 18+.
>
> The interesting bit: the same `LanguageModelSession.respond(to:)` call site routes to three different runtimes depending on what's available on the device.
>
> - iOS 26+ → Apple's actual native FoundationModels (Apple Intelligence)
> - iOS 18+ → CoreML on the Apple Neural Engine (LFM2.5, Gemma 4, Qwen3.5, …)
> - iOS 17+ → ml-explore/mlx-swift-lm on the GPU (any mlx-community/* model)
>
> `@Generable` structured output and `Tool` calling work on all three backends. Verified end-to-end on Apple M4 Max with PASS 10 / FAIL 0 on the Apple-native path.
>
> Source compatibility: the only diff from Apple's framework is the `import` line and the backend install at startup. When you bump your deployment target to iOS 26 you can either delete PFM (`s/PrivateFoundationModels/FoundationModels/`) or keep it for the older-OS support and bring-your-own-model story.
>
> MIT, SPM only. Repo: https://github.com/john-rocky/PrivateFoundationModels
>
> Feedback / issues / PRs welcome.
