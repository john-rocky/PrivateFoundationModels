// pfm-apple-deep — same scenario matrix as pfm-deep / pfm-mlx-deep,
// routed through Apple's native FoundationModels via the PFM
// passthrough backend. All three phases run (Generable, Tools,
// Multimodal+PromptBuilder).
//
//   swift run -c release pfm-apple-deep

import Foundation
import PFMDeepKit
import PrivateFoundationModels
import PrivateFoundationModelsApple

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
func run() async {
    banner("PrivateFoundationModels deep verification — Apple FoundationModels")
    print("  model:          Apple native (\(AppleFoundationModel.availability))")
    print("  date:           \(Date())")

    switch AppleFoundationModel.availability {
    case .available:
        break
    case .unavailable(let reason):
        fail("Apple Intelligence is not available: \(reason)")
        exit(2)
    }

    let backend = AppleFoundationModel.load()
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)

    var runner = DeepRunner()
    await runner.runAll()
    runner.summarize()
}

if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    await run()
} else {
    fail("This binary requires macOS 26.0 / iOS 26.0 / visionOS 26.0 or newer.")
    exit(1)
}
