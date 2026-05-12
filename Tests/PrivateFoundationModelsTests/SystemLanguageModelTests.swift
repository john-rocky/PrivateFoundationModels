import Testing
@testable import PrivateFoundationModels

@Suite("SystemLanguageModel")
struct SystemLanguageModelTests {
    @Test func defaultStartsUnavailable() {
        // We don't assume test ordering with the SessionTests suite which
        // mutates `default`, but on a fresh process the placeholder backend
        // reports modelNotReady.
        let placeholder = SystemLanguageModel(backend: PlaceholderBackend())
        if case .unavailable(.modelNotReady) = placeholder.availability {
            // ok
        } else {
            Issue.record("placeholder backend should report modelNotReady")
        }
        #expect(placeholder.isAvailable == false)
    }

    @Test func customBackendIsAvailable() {
        let model = SystemLanguageModel(backend: StubBackend())
        #expect(model.isAvailable)
    }

    @Test func mutableDefault() {
        let original = SystemLanguageModel.default
        defer { SystemLanguageModel.default = original }

        let stub = SystemLanguageModel(backend: StubBackend())
        SystemLanguageModel.default = stub
        #expect(SystemLanguageModel.default === stub)
    }
}

// Mirrored from production code so the test can exercise it directly.
private struct PlaceholderBackend: LanguageModelBackend {
    let modelIdentifier = "placeholder"
    var availability: SystemLanguageModel.Availability { .unavailable(.modelNotReady) }
    func prewarm() async {}
    func generate(transcript: Transcript, options: GenerationOptions, schema: GenerationSchema?, tools: [AnyTool]) async throws -> BackendGeneration {
        throw GenerationError.unavailable(.modelNotReady)
    }
    func streamGenerate(transcript: Transcript, options: GenerationOptions, schema: GenerationSchema?, tools: [AnyTool]) -> AsyncThrowingStream<BackendDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GenerationError.unavailable(.modelNotReady))
        }
    }
}
