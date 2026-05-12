import Foundation

/// Errors thrown by `LanguageModelSession.respond` and
/// `streamResponse`. Mirrors `FoundationModels.LanguageModelSession.GenerationError`.
public enum GenerationError: Error, Sendable {
    /// The session is already producing a response and was asked to start
    /// another one. Mirrors Apple's `concurrentRequests` case.
    case concurrentRequests

    /// The model rejected the prompt — typically because it triggered a
    /// safety filter, exceeded the input context window, or hit a
    /// backend-specific abort condition. The associated message comes from
    /// the backend and is suitable for logging but not for showing to end
    /// users verbatim.
    case refusal(String)

    /// The structured output the model produced did not parse into the
    /// requested `Generable` type. The associated value is the raw text the
    /// model emitted, useful for debugging schema mismatches.
    case decodingFailure(String)

    /// The prompt + transcript exceeded the model's context window. Includes
    /// the token count the backend computed, so the caller can decide whether
    /// to truncate the transcript or chunk the prompt.
    case exceededContextWindowSize(tokens: Int)

    /// The active `SystemLanguageModel` cannot service this call right now.
    /// See `SystemLanguageModel.Availability` for why. Throwing this lets
    /// callers fall back to a cloud model without crashing.
    case unavailable(SystemLanguageModel.UnavailableReason)

    /// The session was cancelled (`Task.cancel()` propagated through the
    /// backend). The partial transcript is still accessible from
    /// `LanguageModelSession.transcript`.
    case cancelled

    /// The backend produced an internal error that doesn't fit one of the
    /// well-known cases. Wraps the original error so callers can inspect it.
    case backend(Error)
}

extension GenerationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .concurrentRequests:
            return "GenerationError.concurrentRequests: the session is already producing a response"
        case .refusal(let message):
            return "GenerationError.refusal: \(message)"
        case .decodingFailure(let raw):
            return "GenerationError.decodingFailure: model output did not parse into the requested type. Raw output: \(raw.prefix(200))"
        case .exceededContextWindowSize(let tokens):
            return "GenerationError.exceededContextWindowSize: prompt requires \(tokens) tokens"
        case .unavailable(let reason):
            return "GenerationError.unavailable: \(reason)"
        case .cancelled:
            return "GenerationError.cancelled"
        case .backend(let error):
            return "GenerationError.backend: \(error)"
        }
    }
}
