import Foundation

/// What every backend (CoreML, MLX, GGUF, custom) must implement. This is
/// the seam between the public Apple-FM-compatible surface and the actual
/// inference engine.
///
/// Backends are **owned by `SystemLanguageModel`**, not by sessions. One
/// `SystemLanguageModel` may serve many sessions concurrently — the backend
/// is responsible for queueing or refusing overlapping calls. The CoreML
/// backend, for example, holds a single ANE-loaded `MLModel` and serializes
/// requests with an internal actor.
public protocol LanguageModelBackend: Sendable {
    /// Whether this backend is ready to take calls right now.
    var availability: SystemLanguageModel.Availability { get }

    /// Backend-specific identifier ("coreml/qwen3.5-0.8b", "mlx/gemma-4-e2b",
    /// …). Used for logging, A/B benches, and to disambiguate the active
    /// backend when multiple are installed.
    var modelIdentifier: String { get }

    /// Lock the model into memory and ANE / GPU residency. Optional — the
    /// session calls this from `prewarm()`.
    func prewarm() async

    /// One-shot generation. The backend must:
    ///
    /// 1. Render `transcript` into its native prompt format (chat template,
    ///    typically).
    /// 2. If `schema` is non-nil, constrain decoding to match it.
    /// 3. If a tool call appears in the output, return it via
    ///    `BackendGeneration.toolCalls` *without* invoking the tool — the
    ///    session handles tool dispatch.
    /// 4. Otherwise return the final assistant text.
    ///
    /// The session may call this multiple times in a single `respond()` to
    /// handle the tool-call → tool-output → final-answer loop.
    func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration

    /// Streaming variant. The stream emits `BackendDelta` values until it
    /// either yields a `.tool(...)` (caller must dispatch the tool and call
    /// `streamGenerate` again with an updated transcript) or completes with
    /// `.text(final, complete: true)`.
    func streamGenerate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> AsyncThrowingStream<BackendDelta, Error>
}

/// Result of a non-streaming `generate` call.
public struct BackendGeneration: Sendable {
    /// The final assistant text. `nil` if `toolCalls` is non-empty (the
    /// model wants the session to invoke tools first).
    public let text: String?

    /// Tool calls the model emitted. The session iterates these, invokes
    /// each matching tool, appends the results to the transcript, then calls
    /// `generate` again to get the post-tool response.
    public let toolCalls: [ToolCall]

    public init(text: String?, toolCalls: [ToolCall] = []) {
        self.text = text
        self.toolCalls = toolCalls
    }

    public struct ToolCall: Sendable {
        public let name: String
        public let argumentsJSON: String

        public init(name: String, argumentsJSON: String) {
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }
}

/// One emission from a streaming backend.
public enum BackendDelta: Sendable {
    /// A chunk of assistant text. `cumulative` is the full string so far
    /// (snapshot semantics, matching Apple's framework). `complete` flips to
    /// `true` on the final emission.
    case text(cumulative: String, complete: Bool)

    /// The model emitted a tool call. The session must stop iterating,
    /// invoke the tool, append the result to the transcript, and start a
    /// new stream.
    case tool(BackendGeneration.ToolCall)
}
