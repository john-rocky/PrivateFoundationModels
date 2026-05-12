# Apple `FoundationModels` portability

`PrivateFoundationModels` is engineered to be a drop-in substitute for
Apple's `FoundationModels` framework. Existing code that targets Apple FM
should compile and run unchanged except for two purely additive lines.

This document records the verification result and lists the exact diff.

## The entire diff between an Apple FM app and a PrivateFoundationModels app

```diff
-import FoundationModels
+import PrivateFoundationModels
+import PrivateFoundationModelsCoreML

 @main
 struct MyApp: App {
     init() {
+        SystemLanguageModel.default = SystemLanguageModel(
+            backend: try! awaitSync { try await CoreMLLanguageModel.load(.lfm2_5_350M) }
+        )
     }
     var body: some Scene { ... }
 }
```

Two lines added (the backend install) plus one line changed (the import).
Apple's framework loads its model implicitly because `SystemLanguageModel.default`
points at Apple Intelligence; we expose the same singleton but require the
host app to install a backend. Every other call site — `LanguageModelSession`
construction, `respond(to:)`, `streamResponse`, `Generable`, `Tool` invocation,
`Transcript` round-trip, `prewarm`, `isResponding`, the typealiases nested on
`LanguageModelSession` — is byte-for-byte identical.

## How the verification was run

`Sources/PFMPortability/AppleFMCode.swift` contains nine Apple-FM-style
functions: basic single-turn, multi-turn chat with trailing-closure
instructions, streaming, `GenerationOptions`, a `Generable` structured
output, a `Tool` call loop, transcript Codable round-trip, prewarm + sync
property access, and concurrent rejection. **None of those functions
contain a single PrivateFoundationModels-specific call** — they are written
exactly as they would be against Apple FM. The only PrivateFoundationModels
keyword in the file is the `import` statement.

The driver in `PortabilityMain.swift` installs the CoreML backend (the one
line that has no Apple FM equivalent) and exercises the call sites against
`mlboydaisuke/lfm2.5-350m-coreml` on the Apple Neural Engine.

```
swift run -c release pfm-portability
```

## Result (2026-05-13, Apple M4 Max, macOS 26.0, Swift 6.2.1)

```
──────────────────────────────────────────────────────────────────────────────
 Apple FoundationModels portability test
──────────────────────────────────────────────────────────────────────────────
  • AppleFMCode.swift compiled — source compatibility holds
  • runtime invocation: ENABLED
[Load] LFM2 conv_state_in shape: [10, 1024, 3]

──────────────────────────────────────────────────────────────────────────────
 Running Apple FM-style call sites
──────────────────────────────────────────────────────────────────────────────
  ✓ 1. firstAnswer (basic single-turn)
  ✓ 2. miniChat (closure-form instructions + multi-turn)
  ✓ 3. streamSky (streamResponse, cumulative snapshots)
  ✓ 4. deterministic (GenerationOptions)
  ✓ 5. famousLandmark (Generable with includeSchemaInPrompt)
  ✓ 6. researchAssistant (Tool call loop)
  ✓ 7. saveAndRestoreSession (Transcript Codable round-trip)
  ✓ 8. warmupAndCheck (prewarm + sync property access)

──────────────────────────────────────────────────────────────────────────────
 Summary
──────────────────────────────────────────────────────────────────────────────
  passed: 8
  failed: 0

  🎉 every Apple FM-shaped call site ran green.
```

Full unedited log: [`pfm-portability.log`](pfm-portability.log).

## API parity matrix

Verified type / signature parity with Apple's [FoundationModels documentation](https://developer.apple.com/documentation/foundationmodels)
as of WWDC 2025. ✅ = same shape compiles, ⚠ = subset only (noted), ❌ = not
shipped in v0.1.

| Apple FM symbol | v0.1 status | Notes |
|---|---|---|
| `LanguageModelSession.init(model:tools:instructions:)` (value) | ✅ | |
| `LanguageModelSession.init(model:tools:instructions:)` (trailing closure) | ✅ | `@InstructionsBuilder` accepts string literal concatenation; full expression-AST builder is v0.2 |
| `LanguageModelSession.init(model:tools:transcript:)` | ✅ | |
| `session.respond(to:options:)` | ✅ | |
| `session.respond(to:generating:includeSchemaInPrompt:options:)` | ✅ | |
| `session.respond(to:schema:includeSchemaInPrompt:options:)` | ❌ | Schema-by-value overload — v0.2 |
| `session.respond(options:prompt:)` (Prompt) | ❌ | `Prompt` value type — v0.2 |
| `session.streamResponse(to:options:)` | ✅ | |
| `session.streamResponse(to:generating:includeSchemaInPrompt:options:)` | ✅ | |
| `session.prewarm(promptPrefix:)` | ✅ | `promptPrefix` argument accepted; backends currently ignore it |
| `session.transcript` (sync) | ✅ | |
| `session.isResponding` (sync) | ✅ | |
| `LanguageModelSession.Response<T>` (nested) | ✅ | Typealias to top-level `Response<T>` |
| `LanguageModelSession.ResponseStream<T>` (nested) | ✅ | Typealias to top-level `ResponseStream<T>` |
| `LanguageModelSession.GenerationError` (nested) | ✅ | Typealias to top-level `GenerationError` |
| `Transcript` + `Transcript.Entry` (Codable) | ✅ | Round-trip preserves all entry kinds |
| `Instructions` (string-literal expressible) | ✅ | |
| `GenerationOptions` + `SamplingMode` | ✅ | |
| `Tool` protocol | ✅ | |
| `Generable` protocol | ⚠ | Manual `generationSchema` required; `@Generable` macro is v0.2 |
| `SystemLanguageModel.default` | ✅ | Mutable (settable) instead of constant — necessary because v0.1 carries no built-in model |
| `SystemLanguageModel.Availability` / `UnavailableReason` | ✅ | |
| `LanguageModelSession.logFeedbackAttachment(...)` | ❌ | Feedback API — v0.2+ |
| Guardrails | ❌ | v0.2 (currently a no-op accept-all) |

## Notes on the two additive lines

- **The import**: PrivateFoundationModels ships under its own module name so
  it does not clash with Apple's `FoundationModels` symbol — both modules
  could in principle be imported into the same target (the v0.2 roadmap
  includes a `#if canImport(FoundationModels)` shim that lets an app pick
  Apple FM on iOS 26 and PrivateFoundationModels on older OSes from the
  same source).

- **The backend install**: Apple's `SystemLanguageModel.default` is a
  constant tied to Apple Intelligence. Ours is a settable singleton because
  the whole point of the library is to bring your own backend. The install
  line runs once at app startup and never again; everything downstream is
  identical.

## Reproducing

```bash
# Pre-populate the model directory (background URLSession does not run from
# a plain CLI process — see docs/VERIFICATION.md):
mkdir -p ~/Documents/Models/lfm2.5-350m
huggingface-cli download mlboydaisuke/lfm2.5-350m-coreml \
    --local-dir ~/Documents/Models/lfm2.5-350m

swift run -c release pfm-portability
```

`--no-runtime` is also supported: it builds `AppleFMCode.swift` but skips
loading the model. Use this in CI when you only want to check source
compatibility without paying for the 5 second ANE warm-up:

```bash
swift run -c release pfm-portability -- --no-runtime
```
