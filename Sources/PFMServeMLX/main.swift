// pfm-serve-mlx — expose one or more `mlx-community/*` models behind
// an OpenAI-compatible local HTTP endpoint.
//
// Single-model:
//   pfm-serve-mlx --model mlx-community/Qwen3.5-0.8B-MLX-4bit
//
// Multi-model (v0.10.0+):
//   pfm-serve-mlx \
//     --model mlx-community/Qwen3.5-0.8B-MLX-4bit \
//     --model mlx-community/Llama-3.2-3B-Instruct-4bit \
//     --embedding-model sentence-transformers/all-MiniLM-L6-v2
//
// The request body's `model:` field picks which backend handles the
// call. When `model:` is omitted or unknown, the first registered
// chat backend is used.

import Foundation
import PFMServeKit
import PrivateFoundationModels
import PrivateFoundationModelsMLX

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

func run() async {
    var modelIDs = argsCollect(flag: "--model")
    if modelIDs.isEmpty {
        modelIDs = ["mlx-community/Qwen3.5-0.8B-MLX-4bit"]
    }
    let embedderIDs = argsCollect(flag: "--embedding-model")
    let port = UInt16(argSingle("--port") ?? "") ?? 11434
    let host = argSingle("--host") ?? "127.0.0.1"

    let registry = ModelRegistry()

    for id in modelIDs {
        print("[pfm-serve-mlx] loading chat model \(id) …")
        do {
            let backend = try await MLXLanguageModel.load(.custom(id)) { _ in }
            // Use the bare HuggingFace repo id as the public name —
            // clients are likely to pass this exact string.
            registry.registerChat(id: id, backend: backend)
        } catch {
            FileHandle.standardError.write(Data("Chat model \(id) failed: \(error)\n".utf8))
        }
    }

    for id in embedderIDs {
        print("[pfm-serve-mlx] loading embedder \(id) …")
        do {
            let embedder = try await MLXEmbedder.load(id) { _ in }
            registry.registerEmbedding(id: id, backend: embedder)
        } catch {
            FileHandle.standardError.write(Data(
                "Embedder \(id) failed: \(error)\n".utf8
            ))
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
