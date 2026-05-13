// pfm-serve-apple — expose Apple FoundationModels behind an
// OpenAI-compatible local HTTP endpoint.
//
//   swift run -c release pfm-serve-apple [--port 11434] [--host 127.0.0.1]
//
//   curl http://127.0.0.1:11434/v1/chat/completions \
//     -H 'Content-Type: application/json' \
//     -d '{"model":"apple-fm","messages":[{"role":"user","content":"Capital of France?"}]}'

import Foundation
import PFMServeKit
import PrivateFoundationModels
import PrivateFoundationModelsApple

func argSingle(_ flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
func run() async {
    if case .unavailable(let reason) = AppleFoundationModel.availability {
        FileHandle.standardError.write(Data(
            "Apple Intelligence not available: \(reason)\n".utf8
        ))
        exit(2)
    }
    let port = UInt16(argSingle("--port") ?? "") ?? 11434
    let host = argSingle("--host") ?? "127.0.0.1"
    let useCase = argSingle("--use-case") ?? "general"  // general | contentTagging
    let modelID: String
    let backend: AppleFoundationModelBackend
    switch useCase.lowercased() {
    case "contenttagging", "content-tagging", "tagging":
        modelID = "apple-fm-content-tagging"
        backend = AppleFoundationModel.load(useCase: .contentTagging)
    default:
        modelID = "apple-fm"
        backend = AppleFoundationModel.load()
    }

    let registry = ModelRegistry()
    registry.registerChat(id: modelID, backend: backend)

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

if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    await run()
} else {
    FileHandle.standardError.write(Data(
        "pfm-serve-apple requires macOS 26.0 / iOS 26.0 / visionOS 26.0 or newer.\n".utf8
    ))
    exit(1)
}
