import Foundation
import Synchronization
@testable import PrivateFoundationModels

/// Backend used by the test suite. Returns canned responses recorded in
/// `script`, optionally with delays so streaming behavior can be exercised.
final class StubBackend: LanguageModelBackend, @unchecked Sendable {
    struct Reply: Sendable {
        let text: String?
        let toolCalls: [BackendGeneration.ToolCall]
        let chunks: [String]?  // for streaming; if nil we emit `text` as one chunk

        init(text: String? = nil,
             toolCalls: [BackendGeneration.ToolCall] = [],
             chunks: [String]? = nil) {
            self.text = text
            self.toolCalls = toolCalls
            self.chunks = chunks
        }
    }

    nonisolated let modelIdentifier = "stub"
    let availability: SystemLanguageModel.Availability = .available

    /// If set, every `generate` call awaits a continuation that the test must
    /// resume manually. Lets us pin the backend in mid-call to exercise the
    /// session's concurrent-request rejection deterministically.
    var artificialDelay: Duration?

    // All mutable state lives behind a single Mutex so it can be read /
    // written from any isolation context (sync or async) without tripping
    // Swift 6's actor-safety checks.
    private struct State {
        var script: [Reply] = []
        var index: Int = 0
        var lastTranscript: Transcript?
        var lastOptions: GenerationOptions?
        var lastSchema: GenerationSchema?
        var lastTools: [AnyTool] = []
    }
    private let state = Mutex(State())

    func enqueue(_ reply: Reply) {
        state.withLock { $0.script.append(reply) }
    }

    var lastTranscript: Transcript? { state.withLock { $0.lastTranscript } }
    var lastOptions: GenerationOptions? { state.withLock { $0.lastOptions } }
    var lastSchema: GenerationSchema? { state.withLock { $0.lastSchema } }
    var lastTools: [AnyTool] { state.withLock { $0.lastTools } }

    func prewarm() async {}

    func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        let reply = state.withLock { state -> Reply in
            state.lastTranscript = transcript
            state.lastOptions = options
            state.lastSchema = schema
            state.lastTools = tools
            let r = state.script[state.index]
            state.index += 1
            return r
        }
        if let delay = artificialDelay {
            try await Task.sleep(for: delay)
        }
        return BackendGeneration(text: reply.text, toolCalls: reply.toolCalls)
    }

    func streamGenerate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> AsyncThrowingStream<BackendDelta, Error> {
        let reply = state.withLock { state -> Reply in
            state.lastTranscript = transcript
            state.lastOptions = options
            state.lastSchema = schema
            state.lastTools = tools
            let r = state.script[state.index]
            state.index += 1
            return r
        }

        return AsyncThrowingStream { continuation in
            Task {
                if !reply.toolCalls.isEmpty {
                    for call in reply.toolCalls {
                        continuation.yield(.tool(call))
                    }
                    continuation.finish()
                    return
                }
                if let chunks = reply.chunks {
                    var cumulative = ""
                    for (i, chunk) in chunks.enumerated() {
                        cumulative += chunk
                        continuation.yield(.text(cumulative: cumulative, complete: i == chunks.count - 1))
                    }
                } else if let text = reply.text {
                    continuation.yield(.text(cumulative: text, complete: true))
                }
                continuation.finish()
            }
        }
    }
}
