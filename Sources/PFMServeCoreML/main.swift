// pfm-serve-coreml — expose one or more CoreML catalog models behind
// an OpenAI-compatible local HTTP endpoint.
//
//   pfm-serve-coreml --model lfm2.5-350m
//   pfm-serve-coreml --model lfm2.5-350m --model qwen3.5-0.8B

import Foundation
import PFMServeKit
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

func argsCollect(flag: String) -> [String] {
    var out: [String] = []
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag, let v = it.next() { out.append(v) }
    }
    return out
}

func argSingle(_ flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

func catalog(for modelID: String) -> CoreMLLanguageModel.Catalog {
    switch modelID.lowercased() {
    case "lfm2.5-350m":  return .lfm2_5_350M
    case "gemma4-e2b":   return .gemma4E2B
    case "gemma4-e4b":   return .gemma4E4B
    case "qwen3.5-0.8b": return .qwen3_5_0_8B
    case "qwen3.5-2b":   return .qwen3_5_2B
    default:             return .custom(modelID)
    }
}

func run() async {
    var modelIDs = argsCollect(flag: "--model")
    if modelIDs.isEmpty {
        modelIDs = ["lfm2.5-350m"]
    }
    let port = UInt16(argSingle("--port") ?? "") ?? 11434
    let host = argSingle("--host") ?? "127.0.0.1"

    let registry = ModelRegistry()

    for id in modelIDs {
        print("[pfm-serve-coreml] loading \(id) …")
        do {
            let backend = try await CoreMLLanguageModel.load(catalog(for: id)) { @Sendable _ in }
            registry.registerChat(id: id, backend: backend)
        } catch {
            FileHandle.standardError.write(Data("Chat model \(id) failed: \(error)\n".utf8))
        }
    }

    do {
        let server = try PFMServer(
            options: ServeOptions(host: host, port: port),
            registry: registry
        )
        try await server.runForever()
    } catch {
        FileHandle.standardError.write(Data("server failed: \(error)\n".utf8))
        exit(3)
    }
}

await run()
