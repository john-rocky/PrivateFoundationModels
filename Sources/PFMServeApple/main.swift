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

func arg(after flag: String) -> String? {
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
    let port = UInt16(arg(after: "--port") ?? "") ?? 11434
    let host = arg(after: "--host") ?? "127.0.0.1"

    let backend = AppleFoundationModel.load()
    SystemLanguageModel.default = SystemLanguageModel(backend: backend)

    do {
        let server = try PFMServer(
            options: ServeOptions(host: host, port: port),
            modelLabel: "apple-fm"
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
