// pfm-bench-mlx — runs PFMBenchKit against the MLX backend.
//
// Build with xcodebuild (SPM CLI can't compile MLX Metal shaders).
//   xcodebuild -scheme pfm-bench-mlx -configuration Release \
//     -destination "platform=macOS" -skipMacroValidation build
//   pfm-bench-mlx [--model mlx-community/<repo>]

import Foundation
import PFMBenchKit
import PrivateFoundationModels
import PrivateFoundationModelsMLX

func readArg(after flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

func run() async {
    let modelID = readArg(after: "--model") ?? "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    let start = ContinuousClock.now
    let backend: MLXBackend
    do {
        backend = try await MLXLanguageModel.load(.custom(modelID)) { _ in }
    } catch {
        FileHandle.standardError.write(Data("Load failed: \(error)\n".utf8))
        exit(2)
    }
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)
    let load = ContinuousClock.now - start
    let (s, atto) = load.components
    let loadMs = (Double(s) + Double(atto) / 1e18) * 1000

    let backendLabel = "MLX / GPU (\(modelID.split(separator: "/").last ?? Substring(modelID)))"
    if CommandLine.arguments.contains("--multilang") {
        let rows = await Bench.runAllLanguages(
            backendLabel: backendLabel, loadMs: loadMs
        )
        emitBenchOutput(rows)
        return
    }
    let row = await Bench.runAll(label: backendLabel, loadMs: loadMs)
    emitBenchOutput([row])
}

await run()
