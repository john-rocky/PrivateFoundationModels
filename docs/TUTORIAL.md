# 5-minute tutorial — your first PrivateFoundationModels app

A walkthrough that takes you from `swift package init` to a working Apple-FM-shaped chat session in five minutes.

## 0. Prerequisites

- Xcode 16.4 or newer (Swift 6.1+).
- macOS 14+ for the CoreML / MLX backends; macOS 26+ to also try the Apple FM passthrough.

## 1. Add PFM as a dependency

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/john-rocky/PrivateFoundationModels", from: "0.5.2"),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "PrivateFoundationModels",       package: "PrivateFoundationModels"),
                .product(name: "PrivateFoundationModelsCoreML", package: "PrivateFoundationModels"),
            ]
        ),
    ]
)
```

Pick exactly **one** backend product to start. Most apps will pick CoreML (works on iOS 18+) or Apple (iOS 26+). MLX is best when you need a specific model not yet packaged for CoreML.

## 2. Hello, on-device model

```swift
// Sources/MyApp/main.swift
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

let backend = try await CoreMLLanguageModel.load(.lfm2_5_350M) { stage in
    print(stage)
}
SystemLanguageModel.default = SystemLanguageModel(backend: backend)

let session = LanguageModelSession(instructions: Instructions("Be brief."))
let response = try await session.respond(to: "What is `async let`?")
print(response.content)
```

That's it. First run downloads the model (~810 MB) into `~/Library/Application Support/PrivateFoundationModels/`. Second run is cached.

## 3. Streaming responses

```swift
let stream = session.streamResponse(to: "Write a haiku about autumn.")
for try await snapshot in stream {
    print(snapshot.content)
}
```

Each `snapshot.content` is the **cumulative** text emitted so far — same semantics as Apple's `FoundationModels.ResponseStream<String>`. Use `String.suffix(...)` to compute deltas if you need per-chunk text.

## 4. Structured output with `@Generable`

```swift
@Generable
struct CityReport {
    @Guide(description: "City name in English")
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

The `@Generable` macro walks your struct, picks a JSON-Schema type per field, drops `Optional` fields out of `required`, and recurses into nested `@Generable` types. `@Guide(description:)` annotations become per-field instructions for the model. The same code works on all three backends.

## 5. Tool calling

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
    instructions: Instructions("Use lookup_weather when asked about temperature.")
)
let reply = try await session.respond(to: "How warm is it in Tokyo?")
```

Tool calls and outputs appear in `session.transcript` as `.toolCall` / `.toolOutput` entries on every backend — including Apple FM (we reconstruct Apple's opaque tool loop into PFM `Transcript.Entry` values).

## 6. Route to Apple's native model on iOS 26+

Once your deployment target reaches iOS 26, add the Apple backend and pick at runtime:

```swift
// Package.swift dependencies — add a second product:
.product(name: "PrivateFoundationModelsApple", package: "PrivateFoundationModels"),
```

```swift
import PrivateFoundationModels
import PrivateFoundationModelsApple
import PrivateFoundationModelsCoreML

func installDefaultBackend() async throws {
    if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *),
       AppleFoundationModel.isAvailable {
        SystemLanguageModel.default = SystemLanguageModel(
            backend: AppleFoundationModel.load()
        )
    } else {
        SystemLanguageModel.default = SystemLanguageModel(
            backend: try await CoreMLLanguageModel.load(.lfm2_5_350M)
        )
    }
}
```

Nothing else in your app changes. The same `session.respond(...)`, `@Generable`, and `Tool` code that ran on CoreML on iOS 18 now runs on Apple's actual native model on iOS 26+.

## 7. Where to next

- Sample app: [`Examples/PFMSwitcher`](../Examples/PFMSwitcher/) — production-shaped chat app with backend switching and strict memory management.
- API reference: every public type mirrors `FoundationModels`; see [Apple's docs](https://developer.apple.com/documentation/foundationmodels).
- Backend authoring: implement `LanguageModelBackend` to route to llama.cpp, a remote API, your own runtime.
- Benchmarks: [`docs/BENCHMARKS.md`](BENCHMARKS.md) for M4 Max numbers across all three backends.
- FAQ: [`docs/FAQ.md`](FAQ.md).

## 8. When something goes wrong

- `decodingFailure` from `respond(to:generating:T.self)` — the model produced invalid JSON. Use a larger model, a clearer schema description, or a tighter prompt. CoreML and MLX backends do prompt-based schema enforcement; Apple FM uses its grammar-constrained sampler internally.
- `refusal` — the backend's safety layer (Apple FM) declined. Rephrase, or check `GenerationError.refusal` for the explanation.
- `concurrentRequests` — one session is already mid-call. PFM matches Apple's "one in-flight call per session" rule.
- `backend(error)` — the underlying backend threw. Inspect the wrapped error.

Open an [issue](https://github.com/john-rocky/PrivateFoundationModels/issues) with the relevant deep-harness log appended if you hit a regression.
