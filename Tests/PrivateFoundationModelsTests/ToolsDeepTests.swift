import Foundation
import Testing
@testable import PrivateFoundationModels

/// Deterministic verification of the tool-dispatch surface. Tool selection,
/// argument decoding, error propagation, and multi-round chaining are all
/// session-side concerns we own; this suite locks them in via `StubBackend`
/// without depending on a particular model's tool-following ability.
@Suite("Tool calling (deep)")
struct ToolsDeepTests {

    // MARK: - Fixtures

    struct AddTool: Tool {
        struct Arguments: Generable {
            let a: Int
            let b: Int
            static var generationSchema: GenerationSchema {
                GenerationSchema(
                    type: "object",
                    properties: ["a": .init(type: "integer"), "b": .init(type: "integer")],
                    required: ["a", "b"]
                )
            }
        }
        let name = "add"
        let description = "Returns a + b."
        func call(arguments: Arguments) async throws -> String {
            "\(arguments.a + arguments.b)"
        }
    }

    struct MultiplyTool: Tool {
        struct Arguments: Generable {
            let a: Int
            let b: Int
            static var generationSchema: GenerationSchema {
                GenerationSchema(
                    type: "object",
                    properties: ["a": .init(type: "integer"), "b": .init(type: "integer")],
                    required: ["a", "b"]
                )
            }
        }
        let name = "multiply"
        let description = "Returns a × b."
        func call(arguments: Arguments) async throws -> String {
            "\(arguments.a * arguments.b)"
        }
    }

    struct ComplexSearchTool: Tool {
        struct Arguments: Generable {
            let query: String
            let limit: Int
            let categories: [String]
            let exact: Bool
            static var generationSchema: GenerationSchema {
                GenerationSchema(
                    type: "object",
                    properties: [
                        "query":      .init(type: "string"),
                        "limit":      .init(type: "integer"),
                        "categories": GenerationSchema(type: "array", items: .init(type: "string")),
                        "exact":      .init(type: "boolean"),
                    ],
                    required: ["query", "limit", "categories", "exact"]
                )
            }
        }
        let name = "search"
        let description = "Search the index."
        func call(arguments: Arguments) async throws -> String {
            "matched \(arguments.limit) items in [\(arguments.categories.joined(separator: ","))] for \"\(arguments.query)\" (exact=\(arguments.exact))"
        }
    }

    struct ThrowingTool: Tool {
        struct Arguments: Generable {
            let key: String
            static var generationSchema: GenerationSchema {
                GenerationSchema(type: "object",
                                  properties: ["key": .init(type: "string")],
                                  required: ["key"])
            }
        }
        struct Boom: Error {}
        let name = "throwing"
        let description = "Always throws."
        func call(arguments: Arguments) async throws -> String {
            throw Boom()
        }
    }

    // MARK: - 1. Multi-tool: model picks the right one

    @Test func multipleToolsRoutedByName() async throws {
        let stub = StubBackend()
        // Model "picks" multiply for the multiplication question.
        stub.enqueue(.init(toolCalls: [.init(name: "multiply", argumentsJSON: #"{"a":6,"b":7}"#)]))
        stub.enqueue(.init(text: "42"))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(
            model: model,
            tools: [AddTool(), MultiplyTool()],
            instructions: "Use a tool."
        )

        let reply = try await session.respond(to: "What is 6 × 7?")
        #expect(reply.content == "42")

        let transcript = session.transcript
        let entries = transcript.entries
        // .prompt, .toolCall, .toolOutput, .response
        #expect(entries.map(\.kind) == [.instructions, .prompt, .toolCall, .toolOutput, .response])
        let toolCall = entries.first { $0.kind == .toolCall }
        #expect(toolCall?.toolName == "multiply")
        let toolOutput = entries.first { $0.kind == .toolOutput }
        #expect(toolOutput?.content == "42")
    }

    // MARK: - 2. Complex tool argument schema (array + bool + int + string)

    @Test func complexArgumentsDecodedCorrectly() async throws {
        let stub = StubBackend()
        let argsJSON = #"{"query":"swift","limit":5,"categories":["language","mobile"],"exact":true}"#
        stub.enqueue(.init(toolCalls: [.init(name: "search", argumentsJSON: argsJSON)]))
        stub.enqueue(.init(text: "done"))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, tools: [ComplexSearchTool()])

        let reply = try await session.respond(to: "search swift")
        #expect(reply.content == "done")

        let transcript = session.transcript
        let toolOutput = transcript.entries.first { $0.kind == .toolOutput }
        #expect(toolOutput?.content == #"matched 5 items in [language,mobile] for "swift" (exact=true)"#)
    }

    // MARK: - 3. Throwing tool surfaces as .backend(error)

    @Test func throwingToolSurfacesError() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(toolCalls: [.init(name: "throwing", argumentsJSON: #"{"key":"x"}"#)]))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, tools: [ThrowingTool()])

        do {
            _ = try await session.respond(to: "boom")
            Issue.record("expected throw to propagate")
        } catch let error as GenerationError {
            if case .backend(let inner) = error {
                #expect(inner is ThrowingTool.Boom)
            } else {
                Issue.record("expected backend(_), got \(error)")
            }
        }
    }

    // MARK: - 4. Tool call chain: tool 1 → tool 2 → final text

    @Test func toolChainAcrossRounds() async throws {
        let stub = StubBackend()
        // Round 1: call add(2,3)
        stub.enqueue(.init(toolCalls: [.init(name: "add", argumentsJSON: #"{"a":2,"b":3}"#)]))
        // Round 2: call multiply(5,4) — using add's result as input
        stub.enqueue(.init(toolCalls: [.init(name: "multiply", argumentsJSON: #"{"a":5,"b":4}"#)]))
        // Round 3: final
        stub.enqueue(.init(text: "20"))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(
            model: model,
            tools: [AddTool(), MultiplyTool()]
        )

        let reply = try await session.respond(to: "Compute (2+3)*4")
        #expect(reply.content == "20")

        let kinds = session.transcript.entries.map(\.kind)
        #expect(kinds == [.prompt, .toolCall, .toolOutput, .toolCall, .toolOutput, .response])

        let calls = session.transcript.entries.filter { $0.kind == .toolCall }
        #expect(calls.map(\.toolName) == ["add", "multiply"])
    }

    // MARK: - 5. Unknown tool name → refusal

    @Test func unknownToolBecomesRefusal() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(toolCalls: [.init(name: "ghost", argumentsJSON: "{}")]))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, tools: [AddTool()])

        do {
            _ = try await session.respond(to: "x")
            Issue.record("expected refusal")
        } catch let error as GenerationError {
            if case .refusal(let message) = error {
                #expect(message.contains("ghost"))
            } else {
                Issue.record("expected refusal, got \(error)")
            }
        }
    }

    // MARK: - 6. Tool-call loop hard cap

    @Test func runawayLoopsCappedAtEight() async throws {
        let stub = StubBackend()
        // 9 consecutive tool calls — the session bails out at 8.
        for _ in 0..<9 {
            stub.enqueue(.init(toolCalls: [.init(name: "add", argumentsJSON: #"{"a":1,"b":1}"#)]))
        }

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, tools: [AddTool()])

        do {
            _ = try await session.respond(to: "loop forever")
            Issue.record("expected refusal after iteration cap")
        } catch let error as GenerationError {
            if case .refusal(let message) = error {
                #expect(message.contains("maximum tool-call iterations"))
            } else {
                Issue.record("expected refusal, got \(error)")
            }
        }
    }
}
