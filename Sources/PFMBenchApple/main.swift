// pfm-bench-apple — runs the standardized PFMBenchKit harness against
// Apple's native FoundationModels via PrivateFoundationModelsApple.
//
//   swift run -c release pfm-bench-apple

import Foundation
import PFMBenchKit
import PrivateFoundationModels
import PrivateFoundationModelsApple

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
func run() async {
    if case .unavailable(let reason) = AppleFoundationModel.availability {
        FileHandle.standardError.write(Data(
            "Apple Intelligence not available: \(reason)\n".utf8
        ))
        exit(2)
    }

    let isMultilang = CommandLine.arguments.contains("--multilang")
    if isMultilang {
        // Bench Apple FM across all curated languages.
        let start = ContinuousClock.now
        let backend = AppleFoundationModel.load()
        SystemLanguageModel.default = SystemLanguageModel(backend: backend)
        let load = ContinuousClock.now - start
        let (s, atto) = load.components
        let loadMs = (Double(s) + Double(atto) / 1e18) * 1000
        let rows = await Bench.runAllLanguages(
            backendLabel: "Apple FM (.general)", loadMs: loadMs
        )
        emitBenchOutput(rows)
        return
    }

    // Default: useCase variants.
    let (_, generalRow) = await bench(label: "Apple FM (.general)") {
        AppleFoundationModel.load()
    }
    let (_, taggingRow) = await bench(label: "Apple FM (.contentTagging)") {
        AppleFoundationModel.load(useCase: .contentTagging)
    }
    emitBenchOutput([generalRow, taggingRow])
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
func bench(
    label: String,
    factory: () -> AppleFoundationModelBackend
) async -> (loadMs: Double, row: BenchRow) {
    let start = ContinuousClock.now
    let backend = factory()
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)
    let load = ContinuousClock.now - start
    let (s, atto) = load.components
    let loadMs = (Double(s) + Double(atto) / 1e18) * 1000
    let row = await Bench.runAll(label: label, loadMs: loadMs)
    return (loadMs, row)
}

if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    await run()
} else {
    FileHandle.standardError.write(Data(
        "pfm-bench-apple requires macOS 26.0 / iOS 26.0 / visionOS 26.0 or newer.\n".utf8
    ))
    exit(1)
}
