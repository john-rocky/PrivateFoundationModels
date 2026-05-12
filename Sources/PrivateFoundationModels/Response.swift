import Foundation

/// The return value of `LanguageModelSession.respond(...)`. Mirrors
/// `FoundationModels.Response`.
///
/// `content` is the final assistant output as the caller-requested type
/// (`String` for unconstrained responses, a `Generable` value for structured
/// ones). `transcriptEntries` are the entries appended to the session by this
/// call — typically one `.response`, optionally preceded by `.toolCall` /
/// `.toolOutput` pairs.
public struct Response<Content: Sendable>: Sendable {
    public let content: Content
    public let transcriptEntries: [Transcript.Entry]

    public init(content: Content, transcriptEntries: [Transcript.Entry]) {
        self.content = content
        self.transcriptEntries = transcriptEntries
    }
}
