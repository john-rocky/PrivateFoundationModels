import Foundation

/// A complete, replayable record of a session's turns. Mirrors
/// `FoundationModels.Transcript`.
///
/// The transcript is what makes a `LanguageModelSession` portable: serialize
/// it, store it (UserDefaults / Core Data / a file), then re-hydrate a new
/// session with the same conversation state via
/// `LanguageModelSession(transcript:)`. Each call to `respond` /
/// `streamResponse` appends one or more entries.
public struct Transcript: Sendable, Codable, Hashable {
    /// Entries in chronological order. The first entry is `.instructions` if
    /// the session was constructed with an `Instructions` value; otherwise
    /// the transcript starts at the first `.prompt`.
    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// One turn in the conversation. The `kind` discriminator carries all
    /// associated values so the whole struct round-trips through `Codable`.
    public struct Entry: Sendable, Codable, Hashable {
        public enum Kind: String, Sendable, Codable, Hashable {
            case instructions
            case prompt
            case response
            case toolCall
            case toolOutput
        }

        /// What this entry represents. Drives interpretation of `content`,
        /// `toolName`, and `toolArguments`.
        public let kind: Kind

        /// For `.instructions` / `.prompt` / `.response` this is the raw text.
        /// For `.toolCall` this is a textual rendering of the call (e.g.
        /// "weatherTool(city: Tokyo)") used for transcript display; the
        /// machine-readable form is in `toolName` + `toolArguments`. For
        /// `.toolOutput` this is the tool's return value rendered as text.
        public let content: String

        /// Tool name. Populated only for `.toolCall` and `.toolOutput`.
        public let toolName: String?

        /// Tool arguments as the JSON the model emitted. Populated only for
        /// `.toolCall`. Stored as `String` (not `Data`) so the transcript
        /// remains diff-friendly.
        public let toolArguments: String?

        /// When this entry was appended. Set by the session at append time.
        public let timestamp: Date

        public init(
            kind: Kind,
            content: String,
            toolName: String? = nil,
            toolArguments: String? = nil,
            timestamp: Date = Date()
        ) {
            self.kind = kind
            self.content = content
            self.toolName = toolName
            self.toolArguments = toolArguments
            self.timestamp = timestamp
        }
    }
}

extension Transcript {
    /// Encode to JSON. Convenience over the `JSONEncoder` boilerplate.
    public func serialized() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decode from JSON produced by `serialized()`.
    public init(serialized data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(Transcript.self, from: data)
    }
}

extension Transcript: CustomStringConvertible {
    public var description: String {
        entries.map { entry in
            switch entry.kind {
            case .instructions: return "[instructions] \(entry.content)"
            case .prompt:       return "[user] \(entry.content)"
            case .response:     return "[assistant] \(entry.content)"
            case .toolCall:     return "[tool→ \(entry.toolName ?? "?")] \(entry.toolArguments ?? "")"
            case .toolOutput:   return "[tool← \(entry.toolName ?? "?")] \(entry.content)"
            }
        }.joined(separator: "\n")
    }
}
