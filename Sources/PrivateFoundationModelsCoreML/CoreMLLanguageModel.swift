import CoreML
import CoreMLLLM
import Foundation
import PrivateFoundationModels

/// Factory + `LanguageModelBackend` adapter that runs PrivateFoundationModels
/// on top of [CoreML-LLM](https://github.com/john-rocky/CoreML-LLM), which
/// targets the Apple Neural Engine for Gemma 4, Qwen3.5, Qwen3-VL, LFM2.5,
/// FunctionGemma, and EmbeddingGemma.
///
/// ```swift
/// import PrivateFoundationModels
/// import PrivateFoundationModelsCoreML
///
/// SystemLanguageModel.default = SystemLanguageModel(
///     backend: try await CoreMLLanguageModel.load(.qwen3_5_0_8B)
/// )
///
/// let session = LanguageModelSession(instructions: "Be brief.")
/// let reply = try await session.respond(to: "What is async let?")
/// print(reply.content)
/// ```
public enum CoreMLLanguageModel {
    /// Models we ship out-of-the-box. Names align with HuggingFace repos
    /// under `mlboydaisuke/*`; pass `.custom("user/repo-coreml")` for any
    /// other CoreML bundle that CoreML-LLM can load.
    ///
    /// Compatibility note: `CoreMLLLM.load(repo:)` (the unified entry this
    /// adapter calls) supports the flat monolithic layout (LFM2.5) and the
    /// Gemma 4 chunked layout. The Qwen3.5 / Qwen3-VL families ship under a
    /// different chunk-naming convention and are driven by separate Swift
    /// types in the upstream package (`Qwen35MLKVGenerator`,
    /// `Qwen3VL2BStatefulGenerator`); those catalog cases will fail at
    /// load on v0.1 and are kept for source-compatibility only. See
    /// `docs/VERIFICATION.md` for the matrix.
    public enum Catalog: Sendable, Hashable {
        /// Recommended default. Verified end-to-end on Mac in
        /// `docs/VERIFICATION.md`.
        case lfm2_5_350M
        /// Gemma 4 E2B (text + image + video + audio multimodal). Routes
        /// through the unified entry.
        case gemma4E2B
        /// Gemma 4 E4B (text-only). Routes through the unified entry.
        case gemma4E4B
        /// Qwen3.5 0.8B. Currently NOT loadable via this adapter — pending
        /// a `Qwen35MLKVGenerator` routing path in v0.2.
        case qwen3_5_0_8B
        /// Qwen3.5 2B. Same caveat as `qwen3_5_0_8B`.
        case qwen3_5_2B
        /// Qwen3-VL 2B (stateful). Same caveat as `qwen3_5_0_8B`.
        case qwen3VL2BStateful
        case custom(String)

        var repo: String {
            switch self {
            case .qwen3_5_0_8B:      return "mlboydaisuke/qwen3.5-0.8B-CoreML"
            case .qwen3_5_2B:        return "mlboydaisuke/qwen3.5-2B-CoreML"
            case .gemma4E2B:         return "mlboydaisuke/gemma-4-E2B-coreml"
            case .gemma4E4B:         return "mlboydaisuke/gemma-4-E4B-coreml"
            case .qwen3VL2BStateful: return "mlboydaisuke/qwen3-vl-2b-stateful-coreml"
            case .lfm2_5_350M:       return "mlboydaisuke/lfm2.5-350m-coreml"
            case .custom(let r):     return r
            }
        }
    }

    /// Load (downloading on first call) a CoreML LLM bundle and wrap it as a
    /// `LanguageModelBackend`. The returned value is safe to install as
    /// `SystemLanguageModel.default`'s backend.
    public static func load(
        _ model: Catalog,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> CoreMLBackendImpl {
        let llm = try await CoreMLLLM.load(repo: model.repo,
                                            computeUnits: computeUnits,
                                            onProgress: onProgress)
        return CoreMLBackendImpl(llm: llm, modelIdentifier: "coreml://\(model.repo)")
    }

    /// Wrap an already-loaded `CoreMLLLM` instance. Useful if you constructed
    /// the underlying model with custom paths or compute units.
    public static func wrap(_ llm: CoreMLLLM, identifier: String) -> CoreMLBackendImpl {
        CoreMLBackendImpl(llm: llm, modelIdentifier: identifier)
    }
}

/// The actual `LanguageModelBackend` implementation. Public so callers can
/// reach `underlying` for advanced bench / debug use.
public final class CoreMLBackendImpl: LanguageModelBackend, @unchecked Sendable {
    /// The wrapped CoreML-LLM instance. Use this when you need the
    /// CoreML-LLM-specific knobs (`mtpEnabled`, `mtpAcceptanceRate`, etc.)
    /// the Apple-FM-shaped surface doesn't expose.
    public let underlying: CoreMLLLM

    public let modelIdentifier: String

    private let queue = SerialQueue()

    public init(llm: CoreMLLLM, modelIdentifier: String) {
        self.underlying = llm
        self.modelIdentifier = modelIdentifier
    }

    public var availability: SystemLanguageModel.Availability { .available }

    public func prewarm() async {
        // CoreMLLLM lazy-loads its first prediction; firing a one-token
        // generation here amortizes the ANE warm-up.
        _ = try? await queue.run { [underlying] in
            _ = try? await underlying.generate("Hi", maxTokens: 1)
        }
    }

    public func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        try await queue.run { [underlying] in
            let messages = Self.render(transcript: transcript, schema: schema, tools: tools)
            let maxTokens = options.maximumResponseTokens ?? 2048
            let raw: String
            do {
                raw = try await underlying.generate(messages, maxTokens: maxTokens)
            } catch is CancellationError {
                throw GenerationError.cancelled
            } catch {
                throw GenerationError.backend(error)
            }
            return Self.parse(raw: raw, tools: tools, schema: schema)
        }
    }

    public func streamGenerate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> AsyncThrowingStream<BackendDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [underlying, weak self] in
                guard let self else {
                    continuation.finish(throwing: GenerationError.unavailable(.modelNotReady))
                    return
                }
                do {
                    try await self.queue.run {
                        let messages = Self.render(transcript: transcript, schema: schema, tools: tools)
                        let maxTokens = options.maximumResponseTokens ?? 2048
                        let stream: AsyncStream<String>
                        do {
                            stream = try await underlying.stream(messages, maxTokens: maxTokens)
                        } catch {
                            throw GenerationError.backend(error)
                        }

                        var cumulative = ""
                        var sawToolHeader = false
                        for await chunk in stream {
                            cumulative += chunk
                            // Sniff for the structured tool-call marker. If
                            // detected, we don't emit text snapshots — we wait
                            // until generation finishes and emit a single
                            // `.tool` delta.
                            if !sawToolHeader && cumulative.contains(Self.toolCallMarker) {
                                sawToolHeader = true
                                continue
                            }
                            if !sawToolHeader {
                                continuation.yield(.text(cumulative: cumulative, complete: false))
                            }
                            if Task.isCancelled {
                                throw GenerationError.cancelled
                            }
                        }

                        let parsed = Self.parse(raw: cumulative, tools: tools, schema: schema)
                        if let call = parsed.toolCalls.first {
                            continuation.yield(.tool(call))
                            continuation.finish()
                            return
                        }
                        // CRITICAL: the final snapshot must preserve the
                        // cumulative-prefix invariant Apple's ResponseStream
                        // guarantees. `parse()` may trim trailing whitespace
                        // or strip a code fence — fine for the *Transcript*
                        // entry, but breaks `snapshots[i].hasPrefix(snapshots[i-1])`.
                        // So we emit the raw cumulative as the final stream
                        // snapshot; the session-level `Response.content`
                        // surfaces the parsed text separately via the
                        // non-streaming path.
                        let final = sawToolHeader ? (parsed.text ?? cumulative) : cumulative
                        continuation.yield(.text(cumulative: final, complete: true))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Transcript → CoreMLLLM.Message rendering

    static func render(
        transcript: Transcript,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> [CoreMLLLM.Message] {
        var systemParts: [String] = []
        var messages: [CoreMLLLM.Message] = []

        for entry in transcript.entries {
            switch entry.kind {
            case .instructions:
                systemParts.append(entry.content)
            case .prompt:
                messages.append(.init(role: .user, content: entry.content))
            case .response:
                messages.append(.init(role: .assistant, content: entry.content))
            case .toolCall:
                // Render as an assistant message so the model sees its own
                // prior tool call in the running context. Format mirrors the
                // protocol described to the model in the system prompt.
                let body = "\(toolCallMarker) \(entry.toolName ?? "?")\n\(entry.toolArguments ?? "{}")"
                messages.append(.init(role: .assistant, content: body))
            case .toolOutput:
                // Tool outputs are surfaced as a `user` message labeled with
                // the tool name. Most chat models do not have a "tool" role
                // in their template; folding into user is the safest fallback.
                let body = "[Tool result for \(entry.toolName ?? "?")]\n\(entry.content)"
                messages.append(.init(role: .user, content: body))
            }
        }

        if let schema {
            let json = (try? Self.schemaToJSONString(schema)) ?? "{}"
            systemParts.append(
                "You MUST respond with a single JSON value that conforms to this schema. "
                + "Do not include any prose, code fences, or explanation. Schema:\n\(json)"
            )
        }

        if !tools.isEmpty {
            systemParts.append(Self.toolsSystemPrompt(tools))
        }

        if !systemParts.isEmpty {
            // Prepend a single consolidated system message. We assemble at the
            // front so the model templating treats it as the system turn.
            let merged = systemParts.joined(separator: "\n\n")
            messages.insert(.init(role: .system, content: merged), at: 0)
        }

        return messages
    }

    static let toolCallMarker = "TOOL_CALL:"

    static func toolsSystemPrompt(_ tools: [AnyTool]) -> String {
        let entries = tools.map { tool -> String in
            let schemaJSON = (try? Self.schemaToJSONString(tool.argumentsSchema)) ?? "{}"
            return """
            - name: \(tool.name)
              description: \(tool.description)
              arguments_schema: \(schemaJSON)
            """
        }.joined(separator: "\n")
        return """
        You have access to the following tools. To call a tool, respond with EXACTLY:

        \(toolCallMarker) <tool_name>
        <single-line JSON arguments object>

        Do not call a tool unless it is required to answer the user. If you can answer directly, do so without invoking a tool.

        Tools:
        \(entries)
        """
    }

    static func schemaToJSONString(_ schema: GenerationSchema) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(schema)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Output parsing (text / tool call detection)

    static func parse(
        raw: String,
        tools: [AnyTool],
        schema: GenerationSchema?
    ) -> BackendGeneration {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tool call detection
        if !tools.isEmpty, let range = trimmed.range(of: toolCallMarker) {
            let after = String(trimmed[range.upperBound...])
            let lines = after.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            guard let firstLine = lines.first else {
                return BackendGeneration(text: trimmed)
            }
            let toolName = firstLine.trimmingCharacters(in: .whitespaces)
            let rest: String
            if lines.count > 1 {
                rest = String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                rest = ""
            }
            // Try to extract a JSON object from `rest`. Small models often
            // surround the JSON with prose ("here are the args: { ... }
            // please call ..."), so look for the outermost balanced
            // `{ ... }` instead of trusting the model to put bare JSON on
            // the line.
            let cleaned = extractJSONObject(rest) ?? stripCodeFence(rest)
            // If after cleaning we still don't have a leading `{`, the
            // model didn't actually emit a tool call — treat the whole
            // output as text and let the session decide what to do.
            let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedCleaned.hasPrefix("{") else {
                return BackendGeneration(text: trimmed)
            }
            return BackendGeneration(text: nil, toolCalls: [
                .init(name: toolName, argumentsJSON: trimmedCleaned)
            ])
        }

        // Schema-constrained: extract a single JSON object the model emitted.
        if schema != nil {
            if let json = extractJSONObject(trimmed) {
                return BackendGeneration(text: json)
            }
            return BackendGeneration(text: stripCodeFence(trimmed))
        }

        return BackendGeneration(text: trimmed)
    }

    /// Delegate to the shared `JSONExtraction.firstBalancedObject` helper.
    /// Kept under the original name so existing call sites in this file
    /// don't need to change.
    static func extractJSONObject(_ text: String) -> String? {
        JSONExtraction.firstBalancedObject(in: text)
    }

    static func stripCodeFence(_ s: String) -> String {
        JSONExtraction.stripCodeFence(s)
    }
}

/// Serializes calls into the underlying CoreMLLLM so two sessions sharing the
/// same backend don't trip its internal KV cache on top of each other.
final actor SerialQueue {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await body()
    }
}
