// pfm-serve-coreml — expose a CoreML catalog model behind an
// OpenAI-compatible local HTTP endpoint.
//
//   swift run -c release pfm-serve-coreml [--model lfm2.5-350m] [--port 11434]

import Foundation
import PFMServeKit
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

func arg(after flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

func run() async {
    let modelID = arg(after: "--model") ?? "lfm2.5-350m"
    let port = UInt16(arg(after: "--port") ?? "") ?? 11434
    let host = arg(after: "--host") ?? "127.0.0.1"

    let catalog: CoreMLLanguageModel.Catalog
    switch modelID.lowercased() {
    case "lfm2.5-350m":  catalog = .lfm2_5_350M
    case "gemma4-e2b":   catalog = .gemma4E2B
    case "gemma4-e4b":   catalog = .gemma4E4B
    case "qwen3.5-0.8b": catalog = .qwen3_5_0_8B
    case "qwen3.5-2b":   catalog = .qwen3_5_2B
    default:             catalog = .custom(modelID)
    }

    print("[pfm-serve-coreml] loading \(modelID) …")
    let backend: any LanguageModelBackend
    do {
        backend = try await CoreMLLanguageModel.load(catalog) { @Sendable _ in }
    } catch {
        FileHandle.standardError.write(Data("Load failed: \(error)\n".utf8))
        exit(2)
    }
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)

    do {
        let server = try PFMServer(
            options: ServeOptions(host: host, port: port),
            modelLabel: "coreml-\(modelID)"
        )
        try await server.runForever()
    } catch {
        FileHandle.standardError.write(Data("server failed: \(error)\n".utf8))
        exit(3)
    }
}

await run()
