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
    ],
    dependencies: [
        .package(url: "https://github.com/john-rocky/CoreML-LLM", from: "1.8.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
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
        .executableTarget(
            name: "PFMDeep",
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
