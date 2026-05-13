import Foundation

/// The active default backend used by `LanguageModelSession` when no explicit
/// model is passed. Mirrors `FoundationModels.SystemLanguageModel`.
///
/// Unlike Apple's framework, this `SystemLanguageModel` is *settable* — you
/// install your backend once at app startup and every session created
/// without an explicit model picks it up. There is no implicit Apple FM
/// dependency.
///
/// ```swift
/// // App.swift
/// import PrivateFoundationModels
/// import PrivateFoundationModelsCoreML
///
/// @main struct MyApp: App {
///     init() {
///         SystemLanguageModel.default = SystemLanguageModel(
///             backend: CoreMLLanguageModel.default()
///         )
///     }
///     ...
/// }
/// ```
public final class SystemLanguageModel: @unchecked Sendable {
    /// Storage for `default`. Thread-safe via `NSLock`.
    private static let _defaultStorage = DefaultStorage()

    /// The process-wide default. Pre-installed at startup is a placeholder
    /// backend that throws `.unavailable(.modelNotReady)` for every call —
    /// you must replace it with a real backend (CoreML, MLX, GGUF, …) before
    /// constructing a session, or pass a model explicitly to the session
    /// initializer.
    ///
    /// Setting this once at app startup before any `LanguageModelSession` is
    /// constructed is the supported pattern. Re-setting it after sessions
    /// exist is allowed (new sessions will pick up the new backend) but
    /// existing sessions keep using the model they were constructed against.
    public static var `default`: SystemLanguageModel {
        get { _defaultStorage.get() }
        set { _defaultStorage.set(newValue) }
    }

    /// Process-wide default embedding backend. Independent from
    /// `SystemLanguageModel.default` because embedding models and
    /// chat / Generable models almost always live in separate
    /// bundles. Installed once at app startup; `pfm-serve`'s
    /// `/v1/embeddings` endpoint reads from this slot.
    public static var defaultEmbedder: (any EmbeddingBackend)? {
        get { _embedderStorage.get() }
        set { _embedderStorage.set(newValue) }
    }
    private static let _embedderStorage = EmbedderStorage()

    private final class DefaultStorage: @unchecked Sendable {
        private var value: SystemLanguageModel
        private let lock = NSLock()
        init() { self.value = SystemLanguageModel(backend: PlaceholderBackend()) }
        func get() -> SystemLanguageModel { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ v: SystemLanguageModel) { lock.lock(); defer { lock.unlock() }; value = v }
    }

    private final class EmbedderStorage: @unchecked Sendable {
        private var value: (any EmbeddingBackend)?
        private let lock = NSLock()
        func get() -> (any EmbeddingBackend)? { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ v: (any EmbeddingBackend)?) { lock.lock(); defer { lock.unlock() }; value = v }
    }

    /// The backend instance this model wraps. Public so advanced callers
    /// (benchmarks, debug UI) can introspect it, but the public API contract
    /// is `availability` + the `LanguageModelBackend` protocol.
    public let backend: any LanguageModelBackend

    public init(backend: any LanguageModelBackend) {
        self.backend = backend
    }

    /// Whether this model can currently service generation calls. The
    /// session checks this before dispatching to the backend; callers can
    /// also check it to decide whether to fall back to a cloud model.
    public var availability: Availability {
        backend.availability
    }

    /// Convenience.
    public var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Why a backend cannot service calls.
    public enum Availability: Sendable, Equatable {
        case available
        case unavailable(UnavailableReason)
    }

    public enum UnavailableReason: Sendable, Equatable, CustomStringConvertible {
        /// The hardware can't run this backend (e.g. asking for ANE on an
        /// Intel Mac, asking for a 4-bit MLX model on a device with <8 GB).
        case deviceNotEligible

        /// On Apple FM specifically: the user has Apple Intelligence
        /// disabled. We keep the case for API parity even though our default
        /// backend never produces it.
        case appleIntelligenceNotEnabled

        /// The backend exists but hasn't finished loading its weights /
        /// tokenizer yet. Re-check after a short delay.
        case modelNotReady

        /// A custom reason a third-party backend wants to surface.
        case custom(String)

        public var description: String {
            switch self {
            case .deviceNotEligible:            return "deviceNotEligible"
            case .appleIntelligenceNotEnabled:  return "appleIntelligenceNotEnabled"
            case .modelNotReady:                return "modelNotReady"
            case .custom(let m):                return "custom(\(m))"
            }
        }
    }
}

/// A backend that always reports `.modelNotReady`. Installed as
/// `SystemLanguageModel.default` until the host app picks a real one.
private struct PlaceholderBackend: LanguageModelBackend {
    var availability: SystemLanguageModel.Availability {
        .unavailable(.modelNotReady)
    }
    var modelIdentifier: String { "placeholder" }
    func prewarm() async { /* nothing to warm */ }
    func generate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) async throws -> BackendGeneration {
        throw GenerationError.unavailable(.modelNotReady)
    }
    func streamGenerate(
        transcript: Transcript,
        options: GenerationOptions,
        schema: GenerationSchema?,
        tools: [AnyTool]
    ) -> AsyncThrowingStream<BackendDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GenerationError.unavailable(.modelNotReady))
        }
    }
}
