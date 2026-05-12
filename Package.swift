// swift-tools-version: 6.0
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
    ],
    dependencies: [
        .package(url: "https://github.com/john-rocky/CoreML-LLM", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "PrivateFoundationModels",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "PrivateFoundationModelsCoreML",
            dependencies: [
                "PrivateFoundationModels",
                .product(name: "CoreMLLLM", package: "CoreML-LLM"),
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
    ]
)
