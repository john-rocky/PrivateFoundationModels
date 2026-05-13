// pfm-serve-mlx — expose any mlx-community/* model behind an
// OpenAI-compatible local HTTP endpoint.
//
// Build with xcodebuild (SPM CLI can't compile MLX Metal shaders).
//   xcodebuild -scheme pfm-serve-mlx -configuration Release \
//     -destination "platform=macOS" -skipMacroValidation build
//   pfm-serve-mlx [--model mlx-community/<repo>] [--port 11434]

import Foundation
import PFMServeKit
import PrivateFoundationModels
import PrivateFoundationModelsMLX

func arg(after flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

func run() async {
    let modelID = arg(after: "--model") ?? "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    let port = UInt16(arg(after: "--port") ?? "") ?? 11434
    let host = arg(after: "--host") ?? "127.0.0.1"
    let embedderID = arg(after: "--embedding-model")

    print("[pfm-serve-mlx] loading \(modelID) …")
    let backend: MLXBackend
    do {
        backend = try await MLXLanguageModel.load(.custom(modelID)) { _ in }
    } catch {
        FileHandle.standardError.write(Data("Load failed: \(error)\n".utf8))
        exit(2)
    }
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)

    if let embedderID {
        print("[pfm-serve-mlx] loading embedder \(embedderID) …")
        do {
            let embedder = try await MLXEmbedder.load(embedderID) { stage in
                print("  • \(stage)")
            }
            SystemLanguageModel.defaultEmbedder = embedder
            print("[pfm-serve-mlx] /v1/embeddings ready — dim=\(embedder.dimensions)")
        } catch {
            FileHandle.standardError.write(Data(
                "Embedder load failed (\(embedderID)): \(error)\nServer will still start; /v1/embeddings returns 503.\n".utf8
            ))
        }
    }

    do {
        let server = try PFMServer(
            options: ServeOptions(host: host, port: port),
            modelLabel: "mlx-\(modelID.split(separator: "/").last ?? Substring(modelID))"
        )
        try await server.runForever()
    } catch {
        FileHandle.standardError.write(Data("server failed: \(error)\n".utf8))
        exit(3)
    }
}

await run()
