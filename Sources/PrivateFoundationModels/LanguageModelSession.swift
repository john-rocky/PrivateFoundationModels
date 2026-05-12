import Foundation
import Synchronization

/// A stateful conversation with a language model. Mirrors
/// `FoundationModels.LanguageModelSession`.
///
/// One session owns a single `Transcript`. Each call to `respond` /
/// `streamResponse` appends new entries to the transcript and feeds the
/// updated transcript back into the backend on the next call. Sessions are
/// `Sendable`; the underlying transcript is protected by an actor.
///
/// ```swift
/// let session = LanguageModelSession(
///     instructions: "You are a Swift documentation assistant."
/// )
/// let answer = try await session.respond(to: "What is async let?")
/// print(answer.content)
/// ```
public final class LanguageModelSession: @unchecked Sendable {
    /// The model that services this session. By default `SystemLanguageModel.default`.
    public let model: SystemLanguageModel

    /// The tools the model can invoke. Empty if the session was constructed
    /// without tools.
    public let tools: [AnyTool]

    /// Lock-guarded mutable state. Apple's framework exposes `transcript` and
    /// `isResponding` as plain (synchronous) properties, so we cannot park
    /// them behind an actor.
    private let state: SessionState

    /// Snapshot of the conversation so far. Updated after every successful
    /// `respond` / `streamResponse` call. Reads are cheap (one lock acquire),
    /// so it's fine to bind directly to this from SwiftUI.
    public var transcript: Transcript {
        state.snapshot()
    }

    /// `true` while a `respond` or `streamResponse` call is in flight.
    /// Calling either while this is `true` throws `.concurrentRequests`.
    public var isResponding: Bool {
        state.isResponding
    }

    // MARK: - Initializers

    public convenience init(
        model: SystemLanguageModel = .default,
        instructions: Instructions? = nil
    ) {
        self.init(model: model, instructions: instructions, tools: [])
    }

    public convenience init(
        model: SystemLanguageModel = .default,
        transcript: Transcript
    ) {
        self.init(model: model, transcript: transcript, tools: [])
    }

    /// Heterogeneous-tools convenience that matches Apple's
    /// `LanguageModelSession(model:tools:instructions:)` signature exactly.
    /// Each element is erased to `AnyTool` internally.
    public convenience init(
        model: SystemLanguageModel = .default,
        tools: [any Tool] = [],
        instructions: Instructions? = nil
    ) {
        let erased = tools.map { AnyTool.erased($0) }
        self.init(model: model, instructions: erased.isEmpty ? instructions : instructions, tools: erased)
    }

    /// Closure-form instructions, matching Apple's trailing-closure
    /// `LanguageModelSession { "Be brief." }` style. Apple uses an
    /// `@InstructionsBuilder` result builder; for source-compatibility we
    /// accept a plain `() -> Instructions` closure, which is what most
    /// real-world call sites end up looking like.
    public convenience init(
        model: SystemLanguageModel = .default,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        let erased = tools.map { AnyTool.erased($0) }
        self.init(model: model, instructions: instructions(), tools: erased)
    }

    /// Designated initializer (instructions form).
    public init(
        model: SystemLanguageModel = .default,
        instructions: Instructions? = nil,
        tools: [AnyTool] = []
    ) {
        self.model = model
        self.tools = tools

        var entries: [Transcript.Entry] = []
        if let instructions {
            entries.append(.init(kind: .instructions, content: instructions.text))
        }
        self.state = SessionState(transcript: Transcript(entries: entries))
    }

    /// Designated initializer (transcript form). Rehydrate a session from a
    /// previously serialized transcript.
    public init(
        model: SystemLanguageModel = .default,
        transcript: Transcript,
        tools: [AnyTool] = []
    ) {
        self.model = model
        self.tools = tools
        self.state = SessionState(transcript: transcript)
    }

    // MARK: - Prewarm

    /// Hint to the backend that this session will issue a request soon. Lets
    /// the ANE / GPU spin up early and (on chunked models) page weights in.
    /// Safe to call multiple times. `promptPrefix` matches Apple's
    /// signature; backends that don't differentiate prefixes simply ignore
    /// it.
    public func prewarm(promptPrefix: String? = nil) {
        _ = promptPrefix
        Task.detached { [model] in
            await model.backend.prewarm()
        }
    }

    // MARK: - respond (String)

    /// Single-shot response. Appends a `.prompt` entry, runs the backend
    /// (looping through tool calls if the model emits any), appends the
    /// resulting `.response` entry, and returns it.
    @discardableResult
    public func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<String> {
        try await runRespondString(prompt: prompt, options: options, schema: nil)
    }

    // MARK: - respond (Generable)

    /// Single-shot response constrained to a `Generable` type. The backend
    /// gets the type's `generationSchema` and is responsible for emitting
    /// output that parses into `T`. If parsing fails, throws
    /// `.decodingFailure(rawText)`.
    ///
    /// `includeSchemaInPrompt` controls whether the backend renders the
    /// schema into the system prompt. Set `false` when you've already
    /// described the structure to the model via `instructions` and want to
    /// save context budget. Mirrors Apple's parameter shape.
    @discardableResult
    public func respond<T: Generable>(
        to prompt: String,
        generating type: T.Type = T.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<T> {
        let schema: GenerationSchema? = includeSchemaInPrompt ? T.generationSchema : nil
        let raw = try await runRespondString(prompt: prompt, options: options, schema: schema)
        do {
            let decoded = try JSONDecoder().decode(T.self, from: Data(raw.content.utf8))
            return Response(content: decoded, transcriptEntries: raw.transcriptEntries)
        } catch {
            throw GenerationError.decodingFailure(raw.content)
        }
    }

    // MARK: - streamResponse (String)

    /// Streaming response. The stream emits cumulative snapshots until the
    /// model finishes. The transcript is updated after the final snapshot.
    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) -> ResponseStream<String> {
        runStreamString(prompt: prompt, options: options, schema: nil)
    }

    // MARK: - streamResponse (Generable)

    /// Streaming response constrained to a `Generable` type. Each snapshot
    /// is the *parsed* value reconstructed from the partial JSON so far —
    /// where the partial JSON is invalid, the snapshot decodes whatever
    /// prefix is parseable. Final snapshot is guaranteed to be a valid
    /// instance of `T` or the stream throws `.decodingFailure`.
    public func streamResponse<T: Generable>(
        to prompt: String,
        generating type: T.Type = T.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> ResponseStream<T> {
        let schema: GenerationSchema? = includeSchemaInPrompt ? T.generationSchema : nil
        return runStreamGenerable(prompt: prompt, options: options, schema: schema, type: type)
    }

    // MARK: - Internals

    private func runRespondString(
        prompt: String,
        options: GenerationOptions,
        schema: GenerationSchema?
    ) async throws -> Response<String> {
        try state.beginRequest()
        do {
            let promptEntry = Transcript.Entry(kind: .prompt, content: prompt)
            state.append([promptEntry])

            var newEntries: [Transcript.Entry] = [promptEntry]
            var iterationsLeft = 8 // hard cap on tool-call loops per call

            while iterationsLeft > 0 {
                iterationsLeft -= 1

                let current = state.snapshot()
                let result: BackendGeneration
                do {
                    result = try await model.backend.generate(
                        transcript: current,
                        options: options,
                        schema: schema,
                        tools: tools
                    )
                } catch let error as GenerationError {
                    state.endRequest()
                    throw error
                } catch is CancellationError {
                    state.endRequest()
                    throw GenerationError.cancelled
                } catch {
                    state.endRequest()
                    throw GenerationError.backend(error)
                }

                // Tool calls take priority over text — if both are present we
                // dispatch tools first and discard the text (matching Apple's
                // behavior).
                if !result.toolCalls.isEmpty {
                    let toolEntries = try await invokeTools(result.toolCalls)
                    state.append(toolEntries)
                    newEntries.append(contentsOf: toolEntries)
                    continue
                }

                if let text = result.text {
                    let responseEntry = Transcript.Entry(kind: .response, content: text)
                    state.append([responseEntry])
                    newEntries.append(responseEntry)
                    state.endRequest()
                    return Response(content: text, transcriptEntries: newEntries)
                }

                // Backend returned neither text nor tool calls. Treat as refusal.
                state.endRequest()
                throw GenerationError.refusal("backend returned an empty response")
            }

            state.endRequest()
            throw GenerationError.refusal("exceeded maximum tool-call iterations (8)")
        } catch {
            state.endRequest()
            throw error
        }
    }

    private func runStreamString(
        prompt: String,
        options: GenerationOptions,
        schema: GenerationSchema?
    ) -> ResponseStream<String> {
        let (stream, continuation) = AsyncThrowingStream<ResponseStream<String>.Snapshot, Error>.makeStream()
        let finalEntries = LockedArray<Transcript.Entry>()
        let finalText = LockedString()

        let task = Task { [model, state, tools] in
            do {
                try state.beginRequest()

                let promptEntry = Transcript.Entry(kind: .prompt, content: prompt)
                state.append([promptEntry])
                finalEntries.append(promptEntry)

                var iterationsLeft = 8

                while iterationsLeft > 0 {
                    iterationsLeft -= 1
                    let current = state.snapshot()
                    let inner = model.backend.streamGenerate(
                        transcript: current,
                        options: options,
                        schema: schema,
                        tools: tools
                    )
                    var pendingToolCall: BackendGeneration.ToolCall?
                    var lastCumulative = ""

                    do {
                        for try await delta in inner {
                            switch delta {
                            case .text(let cumulative, let complete):
                                lastCumulative = cumulative
                                continuation.yield(.init(content: cumulative))
                                if complete {
                                    let responseEntry = Transcript.Entry(kind: .response, content: cumulative)
                                    state.append([responseEntry])
                                    finalEntries.append(responseEntry)
                                    finalText.set(cumulative)
                                }
                            case .tool(let call):
                                pendingToolCall = call
                            }
                        }
                    } catch is CancellationError {
                        throw GenerationError.cancelled
                    } catch let error as GenerationError {
                        throw error
                    } catch {
                        throw GenerationError.backend(error)
                    }

                    if let call = pendingToolCall {
                        let entries = try await invokeTools([call])
                        state.append(entries)
                        for e in entries { finalEntries.append(e) }
                        continue
                    }

                    if finalText.get() == nil && !lastCumulative.isEmpty {
                        // Backend didn't flag `complete:true` but emitted text — be liberal.
                        let responseEntry = Transcript.Entry(kind: .response, content: lastCumulative)
                        state.append([responseEntry])
                        finalEntries.append(responseEntry)
                        finalText.set(lastCumulative)
                    }

                    break // got a final text response, exit the tool loop
                }

                continuation.finish()
                state.endRequest()
            } catch {
                continuation.finish(throwing: error)
                state.endRequest()
            }
        }

        return ResponseStream(
            stream: stream,
            finalize: {
                _ = task // retain so cancellation works
                guard let text = finalText.get() else {
                    throw GenerationError.refusal("stream ended without a final response")
                }
                return Response(content: text, transcriptEntries: finalEntries.snapshot())
            }
        )
    }

    private func runStreamGenerable<T: Generable>(
        prompt: String,
        options: GenerationOptions,
        schema: GenerationSchema?,
        type: T.Type
    ) -> ResponseStream<T> {
        let upstream = runStreamString(prompt: prompt, options: options, schema: schema)

        let (stream, continuation) = AsyncThrowingStream<ResponseStream<T>.Snapshot, Error>.makeStream()
        let finalContent = LockedValue<T>()

        Task {
            do {
                for try await snapshot in upstream {
                    // Partial JSON may be invalid mid-stream; only emit a
                    // snapshot when the prefix parses. The final emission
                    // is always validated below.
                    if let decoded = try? JSONDecoder().decode(T.self, from: Data(snapshot.content.utf8)) {
                        continuation.yield(.init(content: decoded))
                        finalContent.set(decoded)
                    }
                }
                if finalContent.get() == nil {
                    // Stream ended without a parseable snapshot. Try the
                    // upstream's accumulated text via `collect()`.
                    let response = try await upstream.collect()
                    let decoded = try JSONDecoder().decode(T.self, from: Data(response.content.utf8))
                    continuation.yield(.init(content: decoded))
                    finalContent.set(decoded)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return ResponseStream(
            stream: stream,
            finalize: {
                guard let final = finalContent.get() else {
                    throw GenerationError.decodingFailure("stream ended without a parseable response")
                }
                let response = try await upstream.collect()
                return Response(content: final, transcriptEntries: response.transcriptEntries)
            }
        )
    }

    private func invokeTools(_ calls: [BackendGeneration.ToolCall]) async throws -> [Transcript.Entry] {
        var out: [Transcript.Entry] = []
        for call in calls {
            guard let tool = tools.first(where: { $0.name == call.name }) else {
                throw GenerationError.refusal("model called unknown tool: \(call.name)")
            }
            out.append(.init(
                kind: .toolCall,
                content: "\(call.name)(\(call.argumentsJSON))",
                toolName: call.name,
                toolArguments: call.argumentsJSON
            ))
            let output: String
            do {
                output = try await tool.invoke(call.argumentsJSON)
            } catch {
                throw GenerationError.backend(error)
            }
            out.append(.init(
                kind: .toolOutput,
                content: output,
                toolName: call.name
            ))
        }
        return out
    }
}

// MARK: - Internal state guard

/// Mutex-protected mutable state for a session. Apple's framework exposes
/// `transcript` and `isResponding` as synchronous properties so we cannot
/// guard them with an actor.
private final class SessionState: @unchecked Sendable {
    private struct Storage {
        var transcript: Transcript
        var isResponding: Bool = false
    }
    private let storage: Mutex<Storage>

    init(transcript: Transcript) {
        self.storage = Mutex(Storage(transcript: transcript))
    }

    func snapshot() -> Transcript { storage.withLock { $0.transcript } }
    var isResponding: Bool { storage.withLock { $0.isResponding } }

    func append(_ entries: [Transcript.Entry]) {
        storage.withLock { $0.transcript.entries.append(contentsOf: entries) }
    }

    func beginRequest() throws {
        try storage.withLock { state in
            if state.isResponding { throw GenerationError.concurrentRequests }
            state.isResponding = true
        }
    }

    func endRequest() {
        storage.withLock { $0.isResponding = false }
    }
}

// Tiny lock-protected helpers used by the streaming paths. We can't use
// actor isolation here because the closures returned from `ResponseStream`
// run on whatever executor the caller chooses.
private final class LockedString: @unchecked Sendable {
    private var value: String?
    private let lock = NSLock()
    func set(_ v: String?) { lock.lock(); defer { lock.unlock() }; value = v }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
}

private final class LockedValue<T: Sendable>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()
    func set(_ v: T?) { lock.lock(); defer { lock.unlock() }; value = v }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}

private final class LockedArray<T: Sendable>: @unchecked Sendable {
    private var values: [T] = []
    private let lock = NSLock()
    func append(_ v: T) { lock.lock(); defer { lock.unlock() }; values.append(v) }
    func snapshot() -> [T] { lock.lock(); defer { lock.unlock() }; return values }
}
