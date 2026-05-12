import Foundation

/// A system-message-style preamble that biases the model toward a given role,
/// style, or constraint. Mirrors `FoundationModels.Instructions`.
///
/// Instructions are sent once at session construction and persist for the
/// lifetime of the session. They are recorded as the first entry in
/// `LanguageModelSession.transcript` and survive `transcript.serialize()` /
/// `init(transcript:)` round-trips.
///
/// ```swift
/// let session = LanguageModelSession(
///     instructions: Instructions("You are a Swift documentation assistant. Always answer in English.")
/// )
/// ```
public struct Instructions: Sendable, Hashable, Codable {
    /// The instruction text rendered into the model's prompt.
    public let text: String

    public init(_ text: String) {
        self.text = text
    }
}

extension Instructions: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.text = value
    }
}

extension Instructions: CustomStringConvertible {
    public var description: String { text }
}
