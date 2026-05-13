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
    let start = ContinuousClock.now
    let backend = AppleFoundationModel.load()
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)
    let load = ContinuousClock.now - start
    let (s, atto) = load.components
    let loadMs = (Double(s) + Double(atto) / 1e18) * 1000

    let row = await Bench.runAll(label: "Apple FM (native)", loadMs: loadMs)
    print(row.summary())
    print()
    print("Markdown:")
    print(row.markdownRow())
}

if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    await run()
} else {
    FileHandle.standardError.write(Data(
        "pfm-bench-apple requires macOS 26.0 / iOS 26.0 / visionOS 26.0 or newer.\n".utf8
    ))
    exit(1)
}
