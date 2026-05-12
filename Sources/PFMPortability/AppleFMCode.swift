// SPDX-License-Identifier: MIT
//
// =============================================================================
//  Apple FoundationModels portability proof
// =============================================================================
//
//  The code in this file is written *exactly* the way an iOS 26 app would
//  use Apple's `FoundationModels` framework. The only differences from the
//  Apple equivalent are:
//
//     1.  The `import FoundationModels` line is replaced with
//         `import PrivateFoundationModels`.
//     2.  A single one-line backend install runs at startup (see
//         `main.swift`); this has no equivalent on Apple FM, but it is
//         additive — no Apple-style call needs to be removed or rewritten.
//
//  Everything else compiles and runs unchanged. The compiler is the proof:
//  if this file builds, the surface is source-compatible with Apple FM at
//  the level a real consumer of the framework would care about.
//
// =============================================================================

import PrivateFoundationModels   // <- the only delta from Apple FM
import Foundation

// MARK: - 1. Basic single-turn

/// A vanilla one-shot question/answer flow. The exact shape of this function
/// would not need a single character changed when migrating to Apple FM —
/// the import on line 22 above is the entire diff.
public func firstAnswer() async throws -> String {
    let session = LanguageModelSession(instructions: "Be brief.")
    let response = try await session.respond(to: "What is the capital of France?")
    return response.content
}

// MARK: - 2. Multi-turn chat

public func miniChat() async throws -> Transcript {
    let session = LanguageModelSession {
        "You are a Swift documentation assistant."
        "Answer in 1-2 sentences and never apologize."
    }

    _ = try await session.respond(to: "What is `async let`?")
    _ = try await session.respond(to: "And how does it differ from `Task`?")

    return session.transcript  // sync access — matches Apple FM
}

// MARK: - 3. Streaming

public func streamSky() async throws -> [String] {
    let session = LanguageModelSession(instructions: "Two sentences max.")
    var snapshots: [String] = []
    let stream = session.streamResponse(to: "Why is the sky blue?")
    for try await snapshot in stream {
        snapshots.append(snapshot.content)
    }
    return snapshots
}

// MARK: - 4. GenerationOptions

public func deterministic() async throws -> String {
    let session = LanguageModelSession()
    let options = GenerationOptions(
        sampling: .greedy,
        temperature: 0.0,
        maximumResponseTokens: 48
    )
    let response = try await session.respond(to: "Pick a primary color.", options: options)
    return response.content
}

// MARK: - 5. Structured output via Generable

public struct LandmarkFact: Generable, Sendable {
    public let landmark: String
    public let country: String
    public let famousFor: String

    public static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "landmark":  .init(type: "string"),
                "country":   .init(type: "string"),
                "famousFor": .init(type: "string"),
            ],
            required: ["landmark", "country", "famousFor"]
        )
    }
}

public func famousLandmark() async throws -> LandmarkFact {
    let session = LanguageModelSession {
        "You return only valid JSON. No prose, no code fences."
    }
    let response = try await session.respond(
        to: "Pick one famous landmark and describe it briefly.",
        generating: LandmarkFact.self,
        includeSchemaInPrompt: true
    )
    return response.content
}

// MARK: - 6. Tools

public struct LookupTool: Tool {
    public struct Arguments: Generable {
        public let topic: String
        public static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: ["topic": .init(type: "string")],
                required: ["topic"]
            )
        }
    }

    public let name = "lookup"
    public let description = "Look up a quick fact about a topic."

    public func call(arguments: Arguments) async throws -> String {
        // In a real app this would hit an API or a local index.
        "[stub fact about \(arguments.topic)]"
    }
}

public func researchAssistant(question: String) async throws -> String {
    let session = LanguageModelSession(
        tools: [LookupTool()],
        instructions: Instructions("Use the lookup tool when asked about facts you don't know.")
    )
    let response = try await session.respond(to: question)
    return response.content
}

// MARK: - 7. Transcript persistence

public func saveAndRestoreSession() async throws -> Transcript {
    let original = LanguageModelSession(instructions: "Be terse.")
    _ = try await original.respond(to: "Hi")

    // Round-trip through JSON — what an app would store in a file or
    // Core Data. Apple FM's Transcript is Codable too.
    let data = try original.transcript.serialized()
    let restored = try Transcript(serialized: data)
    let resumed = LanguageModelSession(transcript: restored)

    _ = try await resumed.respond(to: "Continue.")
    return resumed.transcript
}

// MARK: - 8. Availability + prewarm

public func warmupAndCheck() -> Bool {
    guard SystemLanguageModel.default.isAvailable else { return false }
    let session = LanguageModelSession(instructions: "Greet briefly.")
    session.prewarm()                       // bare form
    session.prewarm(promptPrefix: "Hello.") // Apple-shape form
    return !session.isResponding            // sync access — matches Apple FM
}

// MARK: - 9. Concurrent rejection

public func cannotInterleave() async throws {
    let session = LanguageModelSession()
    Task { _ = try? await session.respond(to: "one") }
    // Apple FM throws `.concurrentRequests` here too.
    _ = try await session.respond(to: "two")
}
