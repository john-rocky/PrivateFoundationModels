// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "PrivateFoundationModels",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        // Core API surface. Zero runtime dependencies. Importing this gives
        // you `LanguageModelSession`, `Instructions`, `GenerationOptions`,
        // `Transcript`, `Tool`, `Generable`, `SystemLanguageModel`. To
        // actually run a model you also need a backend product.
        .library(name: "PrivateFoundationModels", targets: ["PrivateFoundationModels"]),

        // Default backend. Routes generation to john-rocky/CoreML-LLM,
        // which runs converted CoreML LLM bundles (Gemma 4, Qwen3.5,
        // Qwen3-VL, LFM2.5, FunctionGemma, EmbeddingGemma) on the Apple
        // Neural Engine. Set `SystemLanguageModel.default` to the value
        // returned by `CoreMLLanguageModel.default()` to use it.
        .library(name: "PrivateFoundationModelsCoreML", targets: ["PrivateFoundationModelsCoreML"]),

        // MLX-Swift backend. Routes generation to ml-explore/mlx-swift-lm
        // (the official Apple MLX Swift LM runtime split out of
        // mlx-swift-examples in 2026-04). Lights up `mlx-community/*`
        // models — Llama, Qwen, Gemma, Mistral, Phi, and the rest — under
        // the same `LanguageModelSession.respond(...)` API as the CoreML
        // backend.
        .library(name: "PrivateFoundationModelsMLX", targets: ["PrivateFoundationModelsMLX"]),

        // Apple FoundationModels passthrough backend. On iOS 26+ /
        // macOS 26+ / visionOS 26+, routes the exact same call sites
        // straight to Apple's native FoundationModels framework, the
        // one that ships with Apple Intelligence. Text + streaming
        // only in v0.4 — Generable / Tool cross-translation lands in
        // v0.5.
        .library(name: "PrivateFoundationModelsApple", targets: ["PrivateFoundationModelsApple"]),

        // End-to-end verification harness. Exercises every public API path
        // (respond / streamResponse / Generable / Tools / transcript) against
        // a real on-device model. Run with:
        //   swift run -c release pfm-verify --model qwen3.5-0.8B
        .executable(name: "pfm-verify", targets: ["PFMVerify"]),

        // Drop-in portability proof. The source files in this target are
        // written exactly as if they imported Apple's `FoundationModels`
        // framework; only the import line and a single-line backend install
        // are different from the Apple equivalent. Compiles green = source
        // compatibility holds.
        //   swift run -c release pfm-portability
        .executable(name: "pfm-portability", targets: ["PFMPortability"]),

        // Deep end-to-end exercise of every Generable shape and Tool pattern
        // (nested objects, arrays, primitives mix, optionals, streaming
        // Generable, multi-tool dispatch, complex tool arguments, throwing
        // tool, multi-step tool chain) against a real on-device model. Per-
        // scenario pass/fail is honest: small models may fail content-level
        // checks even when the API surface works.
        //   swift run -c release pfm-deep
        .executable(name: "pfm-deep", targets: ["PFMDeep"]),

        // Minimal end-to-end check for the MLX backend. Downloads (or
        // resolves from cache) an `mlx-community/*` repo and runs both
        // `respond(to:)` and `streamResponse(to:)` against it.
        //   swift run -c release pfm-mlx-smoke
        .executable(name: "pfm-mlx-smoke", targets: ["PFMMLXSmoke"]),

        // Same scenario matrix as `pfm-deep`, but routed through the
        // MLX-Swift backend. Diff the two outputs to verify backend
        // feature parity.
        //   xcodebuild -scheme pfm-mlx-deep ...
        .executable(name: "pfm-mlx-deep", targets: ["PFMMLXDeep"]),

        // Smoke test for the Apple FoundationModels passthrough
        // backend. Loads `FoundationModels.SystemLanguageModel.default`
        // (Apple's native on-device model) and runs respond /
        // streamResponse / Generable through PFM's call sites. Only
        // meaningful on iOS 26+ / macOS 26+ devices with Apple
        // Intelligence enabled.
        //   swift run -c release pfm-apple-smoke
        .executable(name: "pfm-apple-smoke", targets: ["PFMAppleSmoke"]),

        // Same Generable / Multimodal / PromptBuilder matrix as
        // `pfm-deep` and `pfm-mlx-deep`, but routed through Apple's
        // native FoundationModels. Tool scenarios are skipped
        // (cross-protocol Tool bridging is v0.5 work).
        //   swift run -c release pfm-apple-deep
        .executable(name: "pfm-apple-deep", targets: ["PFMAppleDeep"]),

        // Standardized single-prompt latency / throughput harness.
        // Three thin executables (one per backend) share the same
        // PFMBenchKit library so the rows compose into a coherent
        // table.
        //   swift run -c release pfm-bench-apple
        //   swift run -c release pfm-bench-coreml [--model …]
        //   xcodebuild -scheme pfm-bench-mlx …   (Metal shaders)
        .executable(name: "pfm-bench-apple", targets: ["PFMBenchApple"]),
        .executable(name: "pfm-bench-coreml", targets: ["PFMBenchCoreML"]),
        .executable(name: "pfm-bench-mlx", targets: ["PFMBenchMLX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/john-rocky/CoreML-LLM", from: "1.8.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // Provides `HuggingFace.HubClient`, referenced by the macro
        // expansion of `#hubDownloader()` in MLXHuggingFace.
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.8.1"),
    ],
    targets: [
        .macro(
            name: "PFMMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "PrivateFoundationModels",
            dependencies: ["PFMMacros"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "PrivateFoundationModelsCoreML",
            dependencies: [
                "PrivateFoundationModels",
                .product(name: "CoreMLLLM", package: "CoreML-LLM"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "PrivateFoundationModelsApple",
            dependencies: ["PrivateFoundationModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "PrivateFoundationModelsMLX",
            dependencies: [
                "PrivateFoundationModels",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                // VLM factory registers itself with ModelFactoryRegistry
                // via an NSClassFromString trampoline, so simply linking
                // this product opens the `mlx-community/*-VL-*` family
                // without changing any call sites.
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                // Required so the `#huggingFaceTokenizerLoader()` macro
                // expansion can reference `Tokenizers.AutoTokenizer`.
                .product(name: "Tokenizers", package: "swift-transformers"),
                // Required so the `#hubDownloader()` macro expansion can
                // reference `HuggingFace.HubClient`.
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PrivateFoundationModelsTests",
            dependencies: [
                "PrivateFoundationModels",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMVerify",
            dependencies: [
                "PrivateFoundationModels",
                "PrivateFoundationModelsCoreML",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMPortability",
            dependencies: [
                "PrivateFoundationModels",
                "PrivateFoundationModelsCoreML",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Backend-agnostic scenario library: every Generable / Tool /
        // Multimodal / PromptBuilder scenario lives here so the matrix
        // stays in sync across the CoreML and MLX deep-verification
        // executables below.
        .target(
            name: "PFMDeepKit",
            dependencies: ["PrivateFoundationModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMDeep",
            dependencies: [
                "PFMDeepKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsCoreML",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMMLXSmoke",
            dependencies: [
                "PrivateFoundationModels",
                "PrivateFoundationModelsMLX",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMMLXDeep",
            dependencies: [
                "PFMDeepKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsMLX",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMAppleSmoke",
            dependencies: [
                "PrivateFoundationModels",
                "PrivateFoundationModelsApple",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMAppleDeep",
            dependencies: [
                "PFMDeepKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsApple",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Bench scaffolding: shared library + one thin exe per backend.
        .target(
            name: "PFMBenchKit",
            dependencies: ["PrivateFoundationModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMBenchApple",
            dependencies: [
                "PFMBenchKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsApple",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMBenchCoreML",
            dependencies: [
                "PFMBenchKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsCoreML",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "PFMBenchMLX",
            dependencies: [
                "PFMBenchKit",
                "PrivateFoundationModels",
                "PrivateFoundationModelsMLX",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
