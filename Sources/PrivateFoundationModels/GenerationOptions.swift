import Foundation

/// Per-call generation settings. Mirrors `FoundationModels.GenerationOptions`.
///
/// All properties are optional. A `nil` value means "use the backend's
/// default for this knob"; a non-nil value forces that behavior even when the
/// underlying model has its own preferred setting.
public struct GenerationOptions: Sendable, Hashable {
    /// Token sampling policy. Defaults to `nil`, which lets the backend pick
    /// (typically `.random(top: 40, probabilityThreshold: 0.95)` for chat
    /// models, `.greedy` for tool-calling and structured-output models).
    public var sampling: SamplingMode?

    /// Softmax temperature. Higher = more random. Range is backend-dependent
    /// but typically `0...2`. `0` collapses to argmax regardless of the
    /// `sampling` setting.
    public var temperature: Double?

    /// Hard upper bound on tokens produced for this single `respond` /
    /// `streamResponse` call. The backend will stop emitting tokens once this
    /// count is reached, even mid-sentence. `nil` defers to the model's own
    /// context-window math.
    public var maximumResponseTokens: Int?

    public init(
        sampling: SamplingMode? = nil,
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil
    ) {
        self.sampling = sampling
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
    }
}

/// Token sampling policy. Mirrors `FoundationModels.SamplingMode`.
public enum SamplingMode: Sendable, Hashable {
    /// Always pick the highest-probability token. Deterministic.
    case greedy

    /// Sample from the top-k / top-p truncated softmax. All parameters are
    /// optional. `seed` makes the sampler deterministic for a given prompt +
    /// model + KV state.
    case random(top: Int? = nil, probabilityThreshold: Double? = nil, seed: UInt64? = nil)
}
