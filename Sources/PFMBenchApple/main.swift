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

    // Default useCase — most apps will want this.
    let (generalLoad, generalRow) = await bench(label: "Apple FM (.general)") {
        AppleFoundationModel.load()
    }
    print(generalRow.summary())

    // Content-tagging variant exposed in v0.6.1.
    let (taggingLoad, taggingRow) = await bench(label: "Apple FM (.contentTagging)") {
        AppleFoundationModel.load(useCase: .contentTagging)
    }
    print(taggingRow.summary())

    _ = (generalLoad, taggingLoad)  // already captured in rows
    print()
    print("Markdown:")
    print(generalRow.markdownRow())
    print(taggingRow.markdownRow())
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
