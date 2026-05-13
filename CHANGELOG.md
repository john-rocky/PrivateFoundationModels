# Changelog

All notable changes to PrivateFoundationModels will be documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.2] — 2026-05-13

### Added
- **CORS** support throughout pfm-serve. `OPTIONS /v1/*` preflights
  return 204 with `Access-Control-Allow-Origin: *`,
  `Access-Control-Allow-Methods: GET, POST, OPTIONS`, and
  `Access-Control-Allow-Headers: content-type, authorization`.
  Every other response carries
  `Access-Control-Allow-Origin: *` by default. Browser `fetch()`
  against `http://127.0.0.1:11434` Just Works.
- **OpenAI JSON mode**: when the request includes
  `response_format: { "type": "json_object" }` or
  `"json_schema"`, the server appends a strict JSON-only
  instruction to the system prompt and post-processes the
  reply through `JSONExtraction.extractObject(...)` so
  the assistant `content` is a bare JSON object string —
  no ` ```json ... ``` ` fence wrapping.
- HTTP/1.1 `204 No Content` status text wired into the
  response serializer (was previously emitted as
  `204 Unknown`).

### Verified
- `curl -X OPTIONS … /v1/chat/completions` → 204 + CORS headers.
- `curl … -d '{"response_format":{"type":"json_object"}, …}'` →
  bare `{"city":"Paris","country":"France"}` content.

## [0.7.1] — 2026-05-13

### Added
- `/v1/chat/completions` now honors `"stream": true` and replies
  with Server-Sent Events shaped exactly like OpenAI's
  `chat.completion.chunk`:
    - Initial `delta.role = "assistant"` chunk.
    - One chunk per incremental `delta.content` slice as PFM's
      cumulative streamResponse advances.
    - Final chunk with `finish_reason: "stop"`, followed by
      `data: [DONE]\n\n`.
  Backend errors mid-stream are emitted as an `error` SSE event
  before `[DONE]`.
- `docs/pfm-serve-stream-sample.txt`: real captured streaming
  exchange from Apple FM (11 chunks).

### Notes
- Framing uses `Connection: close` (no chunked encoding), which is
  the simplest pattern that works with curl, the OpenAI SDKs,
  EventSource browsers, `requests` + `sseclient`, etc.

## [0.7.0] — 2026-05-13

### Added
- `pfm-serve-apple` / `pfm-serve-coreml` / `pfm-serve-mlx`
  OpenAI-compatible HTTP servers. Each exposes:
  - `POST /v1/chat/completions`
  - `POST /v1/completions` (delegates to chat-completions)
  - `GET /v1/models` (returns the installed backend's identifier)
  - `GET /healthz`
- New shared library `PFMServeKit` implementing minimal HTTP/1.1
  on top of `Network.framework`'s `NWListener`. Zero new package
  dependencies — chunked-encoding bodies not yet supported; standard
  `Content-Length` bodies from curl / the OpenAI SDKs / requests /
  axios work out of the box.
- `docs/pfm-serve-sample.json`: real captured response from Apple's
  native model through the HTTP endpoint.

### Notes
- Streaming (`"stream": true` → Server-Sent Events) is not implemented
  in this release; requests are answered synchronously. SSE lands in
  v0.7.1.
- The server runs on `127.0.0.1` by default. Pass `--host 0.0.0.0` to
  expose it on the LAN at your own risk.

## [0.6.1] — 2026-05-13

### Added
- `AppleFoundationModel.UseCase` enum (`.general` / `.contentTagging`)
  and `AppleFoundationModel.load(useCase:)` factory. Mirrors Apple's
  `FoundationModels.SystemLanguageModel.UseCase`.
- `AppleFoundationModel.Adapter` enum (`.name(String)` /
  `.fileURL(URL)`) and `AppleFoundationModel.load(adapter:) throws`
  factory. Mirrors Apple's `SystemLanguageModel.Adapter(name:)` /
  `Adapter(fileURL:)` initializers so apps can load fine-tuned
  Apple FM adapters without importing FoundationModels directly.

### Changed
- The original `AppleFoundationModel.load()` (no-arg) is unchanged
  and still wires to `SystemLanguageModel.default`. The two new
  overloads are additive.

## [0.6.0] — 2026-05-13

### Added
- `respond(to:generating:T.self)` auto-retries on
  `GenerationError.decodingFailure`. Default `maximumRetries: 2`
  (so a max of 3 backend calls), configurable per call. Retry
  prompts append a JSON-encoded schema reminder so the model sees
  exactly what shape it failed to produce. Apple's native backend
  rarely trips this because its grammar-constrained sampler
  enforces schema directly; CoreML and MLX benefit when small
  models occasionally emit invalid JSON.
- `maximumRetries: 0` restores single-shot Apple-FM-strict
  behavior for callers that want it.
- 3 new tests
  (`generableAutoRetriesOnDecodingFailure`,
  `generableThrowsAfterRetriesExhausted`,
  `generableMaximumRetriesZeroDisablesRetry`) cover the contract.

### Changed
- Two existing tests
  (`respondGenerableFailsOnGarbledJSON` /
  `decodingFailureReturnsRawText`) pass `maximumRetries: 0`
  explicitly so they keep exercising the single-shot decode-failure
  path now that the default value is 2.

## [0.5.2] — 2026-05-13

### Added
- `pfm-bench-apple` / `pfm-bench-coreml` / `pfm-bench-mlx` standardized
  benchmark executables. Same prompt × same `GenerationOptions` × 3
  timed iterations + 1 warmup per backend. Each emits load_ms,
  time-to-first-token, total_ms, output_chars, chars/sec, and a
  drop-in markdown row.
- New `PFMBenchKit` shared library backing the three executables.
- `docs/BENCHMARKS.md` updated with M4 Max / macOS 26.0 baseline:
  Apple FM (3 B native) — TTFT 297 ms / 252.7 chars/sec,
  CoreML LFM2.5-350M — TTFT 533 ms / 38.6 chars/sec,
  CoreML Qwen3.5-0.8B — TTFT 530 ms / 155.1 chars/sec,
  MLX Qwen3.5-0.8B 4-bit — TTFT 42 ms / 821.2 chars/sec.

## [0.5.1] — 2026-05-13

### Added
- `BackendGeneration.transcriptDelta`: backends can report transcript
  entries they produced internally so the session appends them to its
  own audit trail.
- Apple FM backend snapshots `session.transcript` before/after the call
  and translates Apple-side `.toolCalls` / `.toolOutput` entries back
  to PFM `Transcript.Entry` values via the new field.
- Test `transcriptDeltaIsAppendedBeforeResponse` locks the contract.

### Changed
- `pfm-apple-deep` matrix: jumped from **PASS 10 / MODEL 4 / FAIL 0**
  to **PASS 14 / MODEL 0 / FAIL 0** — tool turns are now visible in
  `session.transcript` on Apple too.

## [0.5.0] — 2026-05-13

### Added
- `PFMToolAdapter` (runtime bridge): conforms to
  `FoundationModels.Tool` with `Arguments = GeneratedContent`, routes
  each `call(arguments:)` back through PFM's `AnyTool.invoke` so the
  user's `func call(arguments:)` runs against PFM-decoded Generable
  arguments exactly as on the CoreML / MLX backends.
- Apple FM backend now constructs `[PFMToolAdapter]` from incoming
  PFM tools and passes them to `LanguageModelSession(model:tools:transcript:)`.
- Apple's `LanguageModelSession.ToolCallError` is unwrapped to the
  underlying error so PFM callers see exactly what their tool threw.

### Changed
- Removed the `guardUnsupported(tools:)` guard. Tools work now.
- `pfm-apple-deep` re-enabled the Tool phase via `runner.runAll()`.

## [0.4.1] — 2026-05-13

### Added
- `@Generable` cross-translation for the Apple FM backend.
  `pfmSchemaToDynamic(_:name:)` walks PFM's JSON-Schema-shaped
  `GenerationSchema` and produces an Apple `DynamicGenerationSchema`,
  which is fed to `FoundationModels.GenerationSchema(root:dependencies:)`
  and `respond(to:schema:)`. Apple's returned `GeneratedContent` is
  re-serialized as JSON via `generatedContentToJSON(_:)` so PFM's
  existing Generable decoder takes over.
- New `pfm-apple-deep` executable mirrors `pfm-deep` / `pfm-mlx-deep`
  but routes through Apple FM. **PASS 9 / MODEL 0 / FAIL 0** on
  all 6 Generable shapes + Multimodal + PromptBuilder phases.
- `PFMDeepKit` scenario phase methods promoted to `public` so
  downstream executables can pick which phases to run.

## [0.4.0] — 2026-05-13

### Added
- `PrivateFoundationModelsApple` product — passthrough to Apple's
  native FoundationModels framework on iOS 26+ / macOS 26+ /
  visionOS 26+. The same `LanguageModelSession.respond(...)` call
  site that runs on a CoreML/MLX model on iOS 18 routes directly to
  Apple's actual on-device LLM here.
- `AppleFoundationModel.load()`, `.availability`, `.isAvailable`
  helpers + `AppleFoundationModelBackend`.
- Transcript / GenerationOptions / SamplingMode translation between
  PFM and Apple types.
- New `pfm-apple-smoke` executable.
- Verified on macOS 26.0: load 0 ms, respond 1.2 s, stream OK.

## [0.3.1] — 2026-05-13

### Added
- MLXVLM dependency. Linking it registers the VLM model factory with
  `ModelFactoryRegistry.shared` via NSClassFromString trampoline, so
  `loadModelContainer(id:)` auto-routes `mlx-community/*-VL-*` repos
  to the VLM factory and falls back to the LLM factory for text models.
- `MLXLanguageModel.Catalog.qwen25_VL_7B_4bit` / `.qwen2_VL_7B_4bit`.
- Try-image-then-fallback in `MLXBackend`: VLM models accept the
  attachment, text-only LLMs silently drop it instead of crashing.

### Changed
- Backend-agnostic scenario library extracted into `PFMDeepKit`.
- `pfm-deep` becomes a CoreML wrapper, `pfm-mlx-deep` (new) is the
  MLX equivalent. Both call the same `DeepRunner`.

## [0.3.0] — 2026-05-13

### Added
- Streaming `Generable` partial-snapshot decode (Apple FM cadence
  parity). `streamResponse(to:generating:)` now emits partial decodes
  of the target type as soon as enough JSON is on the wire to parse a
  prefix. Implemented via `JSONExtraction.extractPartialObject` /
  `PartialJSONParser` state machine. 19 new unit tests +
  `streamingGenerableEmitsIncrementalSnapshots` integration test.
- `PrivateFoundationModelsMLX` product. Wraps `ml-explore/mlx-swift-lm`,
  routes generation to any `mlx-community/*` model under PFM's call
  site. `MLXLanguageModel.Catalog` ships Qwen3-4B, Llama-3.2-3B,
  Gemma-2-2B, Mistral-7B, Phi-3.5-mini.
- New `pfm-mlx-smoke` executable proves the path against
  `mlx-community/Qwen3.5-0.8B-MLX-4bit` (load 2.0 s, respond 1.4 s).

### Changed
- README: lead rewritten ("One call site. Three backends." — the
  iOS 18 polyfill that becomes a runtime passthrough on iOS 26).
- Roadmap bumped.

## [0.2.0] — 2026-05-13

Rolls up beta.1 and beta.2 into the first stable v0.2 release.

### Added (since 0.1.1)

#### API parity
- `Prompt` value type with `ExpressibleByStringLiteral` + `Codable`.
- `@PromptBuilder` result builder so `session.respond { "..." }` trailing
  closures compile against either Apple's framework or this one. Builder
  joins segments with double newlines, matching Apple's expected output.
- `LanguageModelSession.respond(options:prompt:)` /
  `streamResponse(options:prompt:)` overloads (string and `Generable`
  outputs) for the trailing-closure call style.
- `Guardrails` value type with `.default`. Apple-shaped
  `LanguageModelSession(model:guardrails:tools:instructions:)` init now
  compiles. v0.2 ships an accept-all no-op; v0.3+ will support real
  policy configuration.
- Vision input: `respond(to:image:options:)` and
  `streamResponse(to:image:options:)` take an optional `CGImage`.
  Plumbed into a new `BackendAttachment` value type passed to backends
  via overloaded `LanguageModelBackend.generate(transcript:attachments:...)`
  / `streamGenerate`.

#### Backends
- `Qwen3Backend`: drives Qwen3.5 0.8B / 2B via CoreML-LLM's
  `Qwen35MLKVGenerator`. The Qwen catalog entries that returned
  `configNotFound` in v0.1 now load and generate end-to-end. Tokenizer is
  pulled from `Qwen/Qwen3.5-{0.8B,2B}` automatically via the new
  `Catalog.tokenizerSourceRepo` mapping + `HFFetcher.ensureFiles(...)`.
- `CoreMLBackendImpl` overrides the multimodal entry points and forwards
  the first `.image(CGImage)` attachment to
  `CoreMLLLM.generate(messages:image:)` /
  `.stream(messages:image:)`. Vision-capable bundles (Gemma 4 E2B
  multimodal) light up; text-only bundles transparently fall back.

#### Quality / DX
- `HFFetcher` retries transient `URLSession` errors
  (`NSURLErrorNetworkConnectionLost`, `NSURLErrorTimedOut`, etc.) up to
  4 times with exponential backoff. Necessary because HF's Xet LFS
  backend drops multi-GB downloads more often than fresh S3.
- `JSONExtraction.stripThinkBlocks` removes `<think>...</think>`
  reasoning preambles before downstream JSON / tool extraction.
  Required for Qwen3 family; future DeepSeek-R1 etc. land for free.
- Tool-call parser is layout-tolerant: accepts
  `TOOL_CALL: name\n{json}`, `TOOL_CALL: name {json}`,
  `TOOL_CALL: {json}` (single-tool inference).
- 16 new tests (Prompt + Guardrails + builder overloads + vision
  plumbing).

#### Examples + tooling
- `Examples/PFMSwitcher/PFMSwitcher/ChatView.swift` integrates
  `PhotosPicker`; the picked image flows through
  `session.streamResponse(to:image:)` on send and is dropped after
  send.
- `Examples/PFMPortability/AppleFMCode.swift` adds two more
  Apple-FM-shaped scenarios: `describeImage` (vision) and
  `translateUsingPromptBuilder` (PromptBuilder + Guardrails). 10 / 10
  scenarios green on real model.
- `Sources/PFMDeep/DeepMain.swift` exercises three new scenarios:
  `respond(to:image:)`, `streamResponse(to:image:)`,
  `respond { @PromptBuilder }`. All three PASS on LFM2.5-350M ANE.

### Changed
- `CoreMLLanguageModel.load(...)` return type widened from
  `CoreMLBackendImpl` to `any LanguageModelBackend` (necessary to also
  return `Qwen3Backend`). All documented call sites pipe into
  `SystemLanguageModel(backend:)` which takes the protocol, so the
  change is source-compatible at usage.

### Known limitations
- `.qwen3VL2BStateful` still requires the upstream
  `Qwen3VL2BStatefulGenerator` and lands in v0.3.
- Reasoning models (Qwen3 family) need a generous
  `maximumResponseTokens` budget for `Generable` because the `<think>`
  preamble consumes the budget; no toggle to disable yet.

## [0.2.0-beta.2] — 2026-05-13

### Added
- Vision input on `LanguageModelSession`:
  `respond(to:image:options:)` and `streamResponse(to:image:options:)`
  both accept a `CGImage?` alongside the prompt. The image is forwarded
  to the backend via a new `BackendAttachment` value type. Available on
  iOS 18+ / macOS 15+ / visionOS 2+.
- `LanguageModelBackend` gained a multimodal overload:
  `generate(transcript:attachments:options:schema:tools:)` and the
  streaming variant. Default extension implementations silently drop
  attachments before delegating to the text-only methods, so existing
  backends (`AppleFMBridgeBackend` in the PFMSwitcher sample, third-party
  custom backends) keep compiling and working without changes.
- `BackendAttachment` (`Sources/PrivateFoundationModels/`) — value type
  wrapping a `CGImage` for now; the discriminator is `enum Kind` so
  audio (v0.8 roadmap) can join without a breaking change.
- 5 new tests (`AttachmentTests`) covering: image-with-respond plumbing,
  image-with-streamResponse plumbing, no-image-zero-attachments,
  nil-image-zero-attachments, text-only-backend-drops-image fallback.

### Changed
- `CoreMLBackendImpl` (default CoreML backend, the one
  `CoreMLLanguageModel.load(.gemma4E2B)` returns) now overrides the
  multimodal entry points and forwards the first `.image(CGImage)`
  attachment to `CoreMLLLM.generate(messages:image:maxTokens:)` /
  `.stream(messages:image:maxTokens:)`. Vision-capable models (Gemma 4
  E2B multimodal build) light up; text-only models in the same
  family transparently fall back to text-only generation.

### Known limitations
- `Qwen3Backend` (the Qwen3.5 path) does not yet override the
  multimodal entry points — Qwen3-VL needs a different upstream Swift
  class (`Qwen3VL2BStatefulGenerator`) than the text-only
  `Qwen35MLKVGenerator`. v0.3 will route `.qwen3VL2BStateful` through
  the dedicated generator.

## [0.2.0-beta.1] — 2026-05-13

### Added
- `Qwen3Backend`: a `LanguageModelBackend` that drives Qwen3.5 0.8B / 2B
  through CoreML-LLM's `Qwen35MLKVGenerator` ANE path. The Qwen catalog
  entries that returned `configNotFound` / "model does not exist" in v0.1
  now load and generate end-to-end (`pfm-verify --model qwen3.5-0.8B` →
  9/10 PASS; the one remaining miss is model-quality, not framework —
  Qwen3.5 0.8B occasionally emits a JSON array where a string-typed
  Generable field is required, and the framework correctly raises
  `decodingFailure`).
- `CoreMLLanguageModel.Catalog.tokenizerSourceRepo`: maps a CoreML repo
  to the upstream HuggingFace repo it borrows its tokenizer from.
  Used internally so the foreground fetcher pulls `tokenizer.json` +
  `tokenizer_config.json` from `Qwen/Qwen3.5-0.8B` (etc.) when the
  mlboydaisuke CoreML repo doesn't include them.
- `HFFetcher.ensureFiles(_:repo:in:token:onProgress:)`: download a
  hand-picked list of files from any HF repo. Backs the tokenizer
  pull-down above.
- Retry loop on transient `URLSession` errors in `HFFetcher`
  (`NSURLErrorNetworkConnectionLost`, `NSURLErrorTimedOut`, etc.) with
  exponential backoff. HF's Xet LFS backend drops multi-GB downloads
  often enough that this matters in practice.
- `JSONExtraction.stripThinkBlocks`: removes `<think>...</think>` and
  `<thinking>...</thinking>` reasoning preambles so the downstream JSON
  / tool-call extraction sees the model's final answer. Qwen3 family is
  the immediate motivation; future DeepSeek-R1 / o1-style models would
  use the same path.

### Changed
- `CoreMLLanguageModel.load(...)` return type went from
  `CoreMLBackendImpl` to `any LanguageModelBackend` so the function can
  return either a `CoreMLBackendImpl` (LFM2.5 / Gemma 4) or a
  `Qwen3Backend` (Qwen3.5). All real-world call sites pipe the return
  value into `SystemLanguageModel(backend:)`, which takes
  `any LanguageModelBackend`, so the change is source-compatible at
  every documented usage. `pfm-verify` adjusted to cast when it wants
  CoreML-specific introspection (`underlying.contextLength`).
- Tool-call parser is now layout-tolerant: accepts
  `TOOL_CALL: name\n{json}`, `TOOL_CALL: name {json}`, and
  `TOOL_CALL: {json}` (with single-tool name inference). The tool name
  is taken as the first whitespace-delimited token before the `{` —
  previous versions kept all interior whitespace and broke on
  small-model output like `TOOL_CALL: add\nSINGLE-LINE JSON arguments:`.

### Known limitations
- `.qwen3VL2BStateful` still doesn't load — vision input on the session
  API ships in v0.3.
- Reasoning models (Qwen3 family) need a generous `maximumResponseTokens`
  budget for `Generable` because the `<think>` preamble eats into the
  budget. v0.2 doesn't expose a "thinking off" toggle; `pfm-verify`
  bumps the Generable budget to 768 tokens for the qwen3.5 case as a
  workaround.

## [0.1.1] — 2026-05-13

### Added
- `@Generable` macro (member + extension attached) that walks a struct's
  stored properties and synthesizes `static var generationSchema`. Drop-in
  shape with Apple's `FoundationModels.Generable` macro: supports
  primitives, optional fields (which drop out of `required`), `[T]` arrays,
  nested `@Generable` types, and macro-level `description:` argument.
- `@Guide(description:)` peer attribute for per-field schema descriptions.
- `HFFetcher`: a foreground-`URLSession` HuggingFace tree mirror used by
  `CoreMLLanguageModel.load(...)` so the first call downloads on its own
  from any plain-process context (CLI, Xcode Preview, unit tests).
  CoreML-LLM upstream's background-`URLSession` downloader is bypassed.
- `CoreMLLanguageModel.load(_:cacheDirectory:hfToken:onProgress:)` with
  new parameters for custom cache root and gated-repo authentication.
- `defaultCacheDirectory(for:)` static helper exposing the cache root.
- New `PFMMacros` macro target backed by `swift-syntax 600.0`.
- 11 new tests (`GenerableMacroTests`) covering primitive / optional /
  array / nested / `@Guide` / macro-description / end-to-end paths.

### Changed
- `PFMPortability/AppleFMCode.swift` now uses `@Generable` and
  `@Guide(description:)` — the portability proof's structured-output
  fixture is now byte-identical to canonical Apple FM sample code.
- README documents `@Generable` as the recommended path; manual
  `generationSchema` is now an opt-out.

### Fixed
- Streaming `Generable` decode path now strips Markdown code fences
  through the shared `JSONExtraction` helper, matching the non-streaming
  path. (First surfaced in `pfm-deep`.)
- Streaming `Generable` decode now wraps `Swift.DecodingError` as
  `GenerationError.decodingFailure` — consistent error surface with
  `respond(to:generating:)`.

## [0.1.0] — 2026-05-13

Initial release.

### Added
- `LanguageModelSession` with `respond(to:)`, `respond(to:generating:)`,
  `streamResponse(to:)`, `streamResponse(to:generating:)`, `prewarm()`,
  `transcript`, `isResponding`.
- `Instructions`, `GenerationOptions`, `SamplingMode`.
- `Response<Content>` and `ResponseStream<Content>` (cumulative snapshots).
- `Transcript` with `Entry` kinds `instructions` / `prompt` / `response` /
  `toolCall` / `toolOutput`, Codable round-trip via `serialized()` /
  `init(serialized:)`.
- `Tool` protocol + `AnyTool` type-erased wrapper, plus
  `LanguageModelSession(tools: [any Tool], ...)` convenience initializer.
- `Generable` protocol with `GenerationSchema` (recursive JSON-Schema-shaped),
  primitives conforming out of the box.
- `SystemLanguageModel` with `.default` (thread-safe, settable), pluggable
  `LanguageModelBackend` protocol.
- `GenerationError` matching Apple's case names: `concurrentRequests`,
  `refusal`, `decodingFailure`, `exceededContextWindowSize`, `unavailable`,
  `cancelled`, `backend`.
- `PrivateFoundationModelsCoreML` product: `CoreMLLanguageModel` factory
  wrapping `john-rocky/CoreML-LLM` with a 7-model catalog covering
  `mlboydaisuke/*` HuggingFace repos.
- `PFMChat` example iOS app (~200 lines, SwiftUI).
- 30 unit tests covering API surface and session behavior.

### Fixed during verification
- CoreML backend streaming: terminal snapshot was trimmed which broke
  Apple's documented cumulative-prefix invariant. Terminal snapshot now
  carries the same raw cumulative buffer as interior snapshots.
- CoreML backend tool-call JSON extraction: parser was too literal and
  rejected output where the model prepended prose to the JSON object.
  Replaced with a depth-counted, string-aware extractor that finds the
  outermost balanced `{ ... }`.

### Known limitations
- No `@Generable` macro yet — conformers supply `generationSchema` by hand.
- Schema-constrained generation is enforced via system-prompt instructions and
  post-processing, not via a grammar-constrained sampler. Use a backend that
  supports a constrained sampler (Apple FM's grammar mode, Outlines, LM Format
  Enforcer) for deterministic schema enforcement.
- Tool calling uses a `TOOL_CALL: name\n{json}` text protocol the model is
  asked to follow; robustness depends on the underlying model.
- The Qwen3.5 / Qwen3-VL catalog entries do not load through this backend in
  v0.1 — CoreML-LLM ships those families behind a separate Swift type
  (`Qwen35MLKVGenerator`). Verified safe catalog entries: `.lfm2_5_350M`,
  `.gemma4E2B`, `.gemma4E4B`. See `docs/VERIFICATION.md`.
- `CoreMLLLM.ModelDownloader` uses `URLSessionConfiguration.background` and
  does not run from a plain CLI process. From an iOS app context it works as
  documented in CoreML-LLM's README; for CLI / Mac verification pre-populate
  `~/Documents/Models/<id>/` with `huggingface-cli download`.
- No vision input on the `LanguageModelSession` API yet. The CoreML backend
  can run Qwen3-VL / Gemma 4 multimodal via `CoreMLLLM` directly but the
  typed surface for image prompts is on the v0.6 roadmap.
- No streaming partial-JSON decode for `Generable` types other than fully
  parseable prefixes. Mid-stream snapshots are emitted only when the
  accumulated JSON parses as the target type.
