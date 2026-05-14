import CoreML
import CoreMLLLM
import Foundation
import PrivateFoundationModels
import Tokenizers

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

        /// HuggingFace repo to pull tokenizer files from when the CoreML
        /// repo doesn't ship them. Returns `nil` for catalogs whose CoreML
        /// repo already embeds the tokenizer.
        var tokenizerSourceRepo: String? {
            switch self {
            case .qwen3_5_0_8B:      return "Qwen/Qwen3.5-0.8B"
            case .qwen3_5_2B:        return "Qwen/Qwen3.5-2B"
            case .qwen3VL2BStateful: return "Qwen/Qwen3-VL-2B-Instruct"
            case .lfm2_5_350M, .gemma4E2B, .gemma4E4B, .custom:
                return nil
            }
        }
    }

    /// Load (downloading on first call) a CoreML LLM bundle and wrap it as a
    /// `LanguageModelBackend`. The returned value is safe to install as
    /// `SystemLanguageModel.default`'s backend.
    ///
    /// The first call downloads the repo via a foreground URLSession to the
    /// cache directory (`~/Library/Application Support/PrivateFoundationModels/<repo-basename>`).
    /// Subsequent calls skip files whose on-disk size matches the HF-reported
    /// size. The download path works from a plain CLI / Xcode Preview /
    /// unit-test process, unlike CoreML-LLM's upstream background downloader.
    ///
    /// `cacheDirectory` overrides the cache root. `hfToken` is forwarded to
    /// HuggingFace for gated repos.
    ///
    /// Routing: LFM2.5 and Gemma 4 go through `CoreMLLLM.load(from:)`. The
    /// Qwen3.5 family (`.qwen3_5_0_8B`, `.qwen3_5_2B`) is served by
    /// `Qwen3Backend`, which wraps `Qwen35MLKVGenerator` and a tokenizer
    /// pulled from the source HuggingFace repo (the mlboydaisuke CoreML
    /// repos don't ship tokenizer files).
    public static func load(
        _ model: Catalog,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        cacheDirectory: URL? = nil,
        hfToken: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> any LanguageModelBackend {
        let modelDir = try resolveCacheDirectory(for: model, override: cacheDirectory)
        onProgress?("Fetching \(model.repo) → \(modelDir.path)")
        try await HFFetcher().ensure(repo: model.repo, in: modelDir, token: hfToken) { event in
            onProgress?(event.description)
        }

        switch model {
        case .qwen3_5_0_8B, .qwen3_5_2B:
            return try await loadQwen3(model, modelDir: modelDir, computeUnits: computeUnits,
                                       hfToken: hfToken, onProgress: onProgress)
        case .qwen3VL2BStateful:
            throw LoadError.unsupportedCatalogV02(
                "Qwen3-VL needs vision input on `LanguageModelSession`, which lands in v0.3. "
                + "Use `.lfm2_5_350M` / `.gemma4E2B` / `.qwen3_5_0_8B` for v0.2.")
        case .lfm2_5_350M, .gemma4E2B, .gemma4E4B, .custom:
            onProgress?("Loading model…")
            let llm = try await CoreMLLLM.load(from: modelDir,
                                                computeUnits: computeUnits,
                                                onProgress: { stage in onProgress?(stage) })
            return CoreMLBackendImpl(llm: llm, modelIdentifier: "coreml://\(model.repo)")
        }
    }

    private static func loadQwen3(
        _ model: Catalog,
        modelDir: URL,
        computeUnits: MLComputeUnits,
        hfToken: String?,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> Qwen3Backend {
        guard let tokenizerSource = model.tokenizerSourceRepo else {
            throw LoadError.missingTokenizerSource(model.repo)
        }
        let tokenizerDir = modelDir.appendingPathComponent("hf_model")
        onProgress?("Fetching tokenizer from \(tokenizerSource) → \(tokenizerDir.lastPathComponent)/")
        try await HFFetcher().ensureFiles(
            ["tokenizer.json", "tokenizer_config.json"],
            repo: tokenizerSource,
            in: tokenizerDir,
            token: hfToken,
            onProgress: { event in onProgress?(event.description) }
        )

        onProgress?("Loading Qwen3.5 generator (ANE prewarm ~200 ms)…")
        let cfg: Qwen35MLKVGenerator.Config
        switch model {
        case .qwen3_5_0_8B: cfg = .default0_8B
        case .qwen3_5_2B:   cfg = .default2B
        default:
            throw LoadError.unsupportedCatalogV02("internal: unexpected Qwen route for \(model.repo)")
        }
        let generator = Qwen35MLKVGenerator(cfg: cfg)
        generator.setModelFolder(modelDir)
        generator.setComputeUnits(computeUnits)
        try await generator.load()

        onProgress?("Loading tokenizer…")
        let tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerDir)

        return Qwen3Backend(
            generator: generator,
            tokenizer: tokenizer,
            modelIdentifier: "coreml://\(model.repo)"
        )
    }

    public enum LoadError: Error, LocalizedError {
        case unsupportedCatalogV02(String)
        case missingTokenizerSource(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedCatalogV02(let m): return m
            case .missingTokenizerSource(let repo):
                return "No tokenizer source repo configured for \(repo). " +
                    "Add an entry to `Catalog.tokenizerSourceRepo`."
            }
        }
    }

    /// Return the directory this catalog entry should live in. Defaults to
    /// `~/Library/Application Support/PrivateFoundationModels/<repo-basename>`
    /// — outside `~/Documents/Models` so we don't collide with CoreML-LLM's
    /// own cache.
    public static func defaultCacheDirectory(for model: Catalog) throws -> URL {
        try resolveCacheDirectory(for: model, override: nil)
    }

    private static func resolveCacheDirectory(for model: Catalog, override: URL?) throws -> URL {
        let folder = (model.repo as NSString).lastPathComponent
        if let override {
            return override.appendingPathComponent(folder)
        }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("PrivateFoundationModels", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }

    /// Wrap an already-loaded `CoreMLLLM` instance. Useful if you constructed
    /// the underlying model with custom paths or compute units.
    public static func wrap(_ llm: CoreMLLLM, identifier: String) -> CoreMLBackendImpl {
        CoreMLBackendImpl(llm: llm, modelIdentifier: identifier)
    }

    /// Load a CoreML-LLM bundle directly from a local directory. Skips the
    /// HuggingFace fetch path — useful for sideloaded models on iPhone
    /// (drop a `Documents/Models/<name>/` tree on-device), CI rigs that
    /// pre-stage weights, and offline development.
    ///
    /// The directory must contain whatever layout `CoreMLLLM.load(from:)`
    /// expects for the underlying architecture — typically `chunk*.mlmodelc`
    /// (or `.mlpackage`), an `hf_model/` tokenizer dir, and any per-model
    /// weight bins / npy tables alongside `model_config.json`.
    ///
    /// ## Adapters / LoRA
    /// CoreML has no runtime adapter-apply step — unlike the MLX backend,
    /// which loads a LoRA on top of base weights in memory via
    /// `MLXLanguageModel.load(_:adapter:)`. For CoreML the adapter is
    /// **merged into the weights at conversion time**, producing a
    /// standalone model bundle. To run a fine-tuned CoreML model, point
    /// this method at that merged bundle — it loads exactly like any
    /// other bundle. There is nothing extra to wire up on the PFM side.
    public static func load(
        localBundle directory: URL,
        identifier: String? = nil,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> CoreMLBackendImpl {
        onProgress?("Loading sideloaded bundle at \(directory.lastPathComponent)…")
        let llm = try await CoreMLLLM.load(from: directory,
                                            computeUnits: computeUnits,
                                            onProgress: { stage in onProgress?(stage) })
        let id = identifier ?? "coreml-local://\(directory.lastPathComponent)"
        return CoreMLBackendImpl(llm: llm, modelIdentifier: id)
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

    public func tokenCount(_ text: String) async -> Int? {
        underlying.tokenizerRef.encode(text: text).count
    }

    public func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        try await generate(transcript: transcript, attachments: [],
                            options: options, schema: schema, tools: tools)
    }

    public func generate(
        transcript: Transcript,
        attachments: [BackendAttachment],
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        try await queue.run { [underlying] in
            let messages = Self.render(transcript: transcript, schema: schema, tools: tools)
            let maxTokens = options.maximumResponseTokens ?? 2048
            let image = Self.firstImage(in: attachments)
            let raw: String
            do {
                if let image, underlying.supportsVision {
                    raw = try await underlying.generate(messages, image: image, maxTokens: maxTokens)
                } else {
                    // Vision unsupported (text-only model) or no image attached
                    // — fall back to text-only generation.
                    raw = try await underlying.generate(messages, maxTokens: maxTokens)
                }
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
        streamGenerate(transcript: transcript, attachments: [],
                        options: options, schema: schema, tools: tools)
    }

    public func streamGenerate(
        transcript: Transcript,
        attachments: [BackendAttachment],
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
                        let image = Self.firstImage(in: attachments)
                        let stream: AsyncStream<String>
                        do {
                            if let image, underlying.supportsVision {
                                stream = try await underlying.stream(messages, image: image, maxTokens: maxTokens)
                            } else {
                                stream = try await underlying.stream(messages, maxTokens: maxTokens)
                            }
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

    // MARK: - Attachment helpers

    static func firstImage(in attachments: [BackendAttachment]) -> CGImage? {
        for attachment in attachments {
            if case .image(let img) = attachment.kind {
                return img
            }
        }
        return nil
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
        // Reasoning models (Qwen3, DeepSeek-R1, etc.) prefix output with
        // <think>...</think>. Strip first so downstream parsing sees the
        // actual answer.
        let dethought = JSONExtraction.stripThinkBlocks(raw)
        let trimmed = dethought.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tool call detection
        if !tools.isEmpty, let range = trimmed.range(of: toolCallMarker) {
            let after = String(trimmed[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            // Two layouts:
            //   1.  TOOL_CALL: <name>\n<json>      (canonical)
            //   2.  TOOL_CALL: <name> <json>       (same-line)
            //   3.  TOOL_CALL: <json>              (small model omits name)
            // Find the `{` that opens the JSON object; everything before
            // it is the tool name, everything from it on is the payload.
            if let braceIndex = after.firstIndex(of: "{") {
                // The tool name is the first whitespace-delimited token
                // before the `{`. Models often run the JSON onto a line
                // separated from the marker by extra prose ("TOOL_CALL:
                // add\nSINGLE-LINE JSON arguments:\n{...}"), so taking the
                // entire interior region would yield garbage tool names.
                let namePart = String(after[..<braceIndex])
                    .components(separatedBy: .whitespacesAndNewlines)
                    .first(where: { !$0.isEmpty }) ?? ""
                let jsonPart = String(after[braceIndex...])
                let cleaned = extractJSONObject(jsonPart) ?? stripCodeFence(jsonPart)
                let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCleaned.hasPrefix("{") {
                    let resolvedName: String
                    if !namePart.isEmpty {
                        resolvedName = namePart
                    } else if tools.count == 1 {
                        // Model omitted the name; only one tool is registered,
                        // so the call is unambiguous.
                        resolvedName = tools[0].name
                    } else {
                        // Ambiguous: model emitted JSON only but several tools
                        // are registered. Fall back to treating the output as
                        // text rather than guessing wrong.
                        return BackendGeneration(text: trimmed)
                    }
                    return BackendGeneration(text: nil, toolCalls: [
                        .init(name: resolvedName, argumentsJSON: trimmedCleaned)
                    ])
                }
            }
            // Marker present but no JSON object — treat as text.
            return BackendGeneration(text: trimmed)
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
