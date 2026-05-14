import Foundation
// `#hubDownloader()` expands to a wrapper around `HuggingFace.HubClient`,
// and `#huggingFaceTokenizerLoader()` expands to code that uses
// `Tokenizers.AutoTokenizer` — both symbols must be in scope at the
// macro expansion site.
import HuggingFace
import MLXHuggingFace
import MLXLLM
// Linking MLXVLM is enough to register the VLM model factory with
// `ModelFactoryRegistry.shared` (via NSClassFromString trampoline), so
// `loadModelContainer(id:)` will pick up `mlx-community/*-VL-*` repos
// automatically.
import MLXVLM
import MLXLMCommon
import PrivateFoundationModels
import Tokenizers

/// MLX-Swift backend factory. Wraps ml-explore/mlx-swift-lm so the same
/// `LanguageModelSession.respond(...)` call sites that drive the CoreML
/// backend can run any `mlx-community/*` model — Llama, Qwen, Gemma,
/// Mistral, Phi, and the rest — under the Apple-FM-shaped surface.
///
/// ```swift
/// import PrivateFoundationModels
/// import PrivateFoundationModelsMLX
///
/// SystemLanguageModel.default = SystemLanguageModel(
///     backend: try await MLXLanguageModel.load(.qwen3_4B_4bit)
/// )
///
/// let session = LanguageModelSession(instructions: "Be brief.")
/// print(try await session.respond(to: "Hello!").content)
/// ```
public enum MLXLanguageModel {
    /// A curated set of `mlx-community/*` repos that work well as
    /// out-of-the-box choices. `.custom("user/repo")` covers anything
    /// else `mlx-swift-lm` can load.
    public enum Catalog: Sendable, Hashable {
        case qwen3_4B_4bit
        case llama3_2_3B_4bit
        case gemma2_2B_4bit
        case mistral7B_4bit
        case phi3_5_mini_4bit
        case qwen25_VL_7B_4bit       // vision-language (MLXVLM)
        case qwen2_VL_7B_4bit        // vision-language (MLXVLM)
        case custom(String)

        public var id: String {
            switch self {
            case .qwen3_4B_4bit:      return "mlx-community/Qwen3-4B-4bit"
            case .llama3_2_3B_4bit:   return "mlx-community/Llama-3.2-3B-Instruct-4bit"
            case .gemma2_2B_4bit:     return "mlx-community/gemma-2-2b-it-4bit"
            case .mistral7B_4bit:     return "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
            case .phi3_5_mini_4bit:   return "mlx-community/Phi-3.5-mini-instruct-4bit"
            case .qwen25_VL_7B_4bit:  return "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
            case .qwen2_VL_7B_4bit:   return "mlx-community/Qwen2-VL-7B-Instruct-4bit"
            case .custom(let r):      return r
            }
        }
    }

    /// Load (downloading on first call) an MLX model bundle and wrap it
    /// as a `LanguageModelBackend`. The returned value installs cleanly
    /// as `SystemLanguageModel.default`'s backend.
    public static func load(
        _ model: Catalog,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> MLXBackend {
        onProgress?("Resolving \(model.id)…")
        let hub = #hubDownloader()
        let loader = #huggingFaceTokenizerLoader()
        let container = try await loadModelContainer(
            from: hub,
            using: loader,
            id: model.id,
            progressHandler: { progress in
                let fraction = progress.fractionCompleted
                onProgress?(String(format: "Downloading %.0f%%", fraction * 100))
            }
        )
        onProgress?("Loaded \(model.id)")
        return MLXBackend(container: container, modelIdentifier: "mlx://\(model.id)")
    }

    /// Where a LoRA / DoRA adapter lives. The directory — local, or
    /// downloaded from HuggingFace — must contain the layout
    /// `mlx_lm.lora` produces: an `adapter_config.json` (with a
    /// `fine_tune_type` of `"lora"` or `"dora"`) plus the adapter
    /// `*.safetensors` weights.
    public enum Adapter: Sendable {
        /// A local directory of adapter files.
        case directory(URL)
        /// A HuggingFace repo id holding the adapter; downloaded on
        /// first use, cached afterwards.
        case huggingFace(String, revision: String = "main")

        var identifier: String {
            switch self {
            case .directory(let url):       return url.lastPathComponent
            case .huggingFace(let repo, _): return repo
            }
        }

        var configuration: ModelConfiguration {
            switch self {
            case .directory(let url):
                return ModelConfiguration(directory: url)
            case .huggingFace(let repo, let revision):
                return ModelConfiguration(id: repo, revision: revision)
            }
        }
    }

    /// Load a base model and apply a LoRA / DoRA adapter on top, then
    /// wrap the result as a `LanguageModelBackend`. The adapter is
    /// applied into the model's layers in memory — the same
    /// `LanguageModelSession.respond(...)` call site then runs the
    /// fine-tuned model with no further changes.
    ///
    /// ```swift
    /// SystemLanguageModel.default = SystemLanguageModel(
    ///     backend: try await MLXLanguageModel.load(
    ///         .custom("mlx-community/Qwen3-4B-4bit"),
    ///         adapter: .huggingFace("my-org/qwen3-support-lora")
    ///     )
    /// )
    /// ```
    public static func load(
        _ model: Catalog,
        adapter: Adapter,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> MLXBackend {
        onProgress?("Resolving \(model.id)…")
        let hub = #hubDownloader()
        let loader = #huggingFaceTokenizerLoader()
        let container = try await loadModelContainer(
            from: hub,
            using: loader,
            id: model.id,
            progressHandler: { progress in
                onProgress?(String(format: "Downloading base %.0f%%",
                                     progress.fractionCompleted * 100))
            }
        )

        onProgress?("Resolving adapter \(adapter.identifier)…")
        let modelAdapter = try await ModelAdapterFactory.shared.load(
            from: hub,
            configuration: adapter.configuration,
            progressHandler: { progress in
                onProgress?(String(format: "Downloading adapter %.0f%%",
                                     progress.fractionCompleted * 100))
            }
        )

        // Apply the adapter into the model's layers in place. Every
        // later `perform` on this container sees the adapted weights.
        try await container.perform { (context: ModelContext) in
            try context.model.load(adapter: modelAdapter)
        }

        onProgress?("Applied adapter \(adapter.identifier)")
        return MLXBackend(
            container: container,
            modelIdentifier: "mlx://\(model.id)+adapter:\(adapter.identifier)"
        )
    }
}
