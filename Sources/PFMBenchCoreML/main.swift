// pfm-bench-coreml — runs PFMBenchKit against the CoreML backend.
//
//   swift run -c release pfm-bench-coreml [--model qwen3.5-0.8B]

import Foundation
import PFMBenchKit
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

func readArg(after flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

func run() async {
    let modelID = readArg(after: "--model") ?? "lfm2.5-350m"
    let catalog: CoreMLLanguageModel.Catalog
    switch modelID.lowercased() {
    case "lfm2.5-350m": catalog = .lfm2_5_350M
    case "gemma4-e2b":  catalog = .gemma4E2B
    case "gemma4-e4b":  catalog = .gemma4E4B
    case "qwen3.5-0.8b": catalog = .qwen3_5_0_8B
    case "qwen3.5-2b":   catalog = .qwen3_5_2B
    default:            catalog = .custom(modelID)
    }

    let start = ContinuousClock.now
    let backend: any LanguageModelBackend
    do {
        backend = try await CoreMLLanguageModel.load(catalog) { @Sendable _ in }
    } catch {
        FileHandle.standardError.write(Data("Load failed: \(error)\n".utf8))
        exit(2)
    }
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)
    let load = ContinuousClock.now - start
    let (s, atto) = load.components
    let loadMs = (Double(s) + Double(atto) / 1e18) * 1000

    let row = await Bench.runAll(label: "CoreML / ANE (\(modelID))", loadMs: loadMs)
    emitBenchOutput([row])
}

await run()
