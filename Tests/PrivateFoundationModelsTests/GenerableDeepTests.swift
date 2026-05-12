import Foundation
import Testing
@testable import PrivateFoundationModels

/// Deterministic verification of every Generable shape we publicly claim to
/// support. Driven by `StubBackend` so the assertions exercise our own
/// schema → prompt → JSON-decode plumbing without depending on any
/// particular model's quality. Real-model end-to-end coverage lives in the
/// `pfm-deep` executable.
@Suite("Generable (deep)")
struct GenerableDeepTests {

    // MARK: - 1. Nested object

    struct Address: Generable, Equatable {
        let street: String
        let city: String
        let postalCode: String
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "street":     .init(type: "string"),
                    "city":       .init(type: "string"),
                    "postalCode": .init(type: "string"),
                ],
                required: ["street", "city", "postalCode"]
            )
        }
    }

    struct Person: Generable, Equatable {
        let name: String
        let age: Int
        let address: Address
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "name":    .init(type: "string"),
                    "age":     .init(type: "integer"),
                    "address": Address.generationSchema,
                ],
                required: ["name", "age", "address"]
            )
        }
    }

    @Test func nestedObjectDecodes() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: """
        {"name":"Alice","age":34,"address":{"street":"1 Main St","city":"Osaka","postalCode":"530-0001"}}
        """))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(
            to: "Introduce yourself",
            generating: Person.self
        )
        let expected = Person(
            name: "Alice",
            age: 34,
            address: Address(street: "1 Main St", city: "Osaka", postalCode: "530-0001")
        )
        #expect(response.content == expected)

        // Backend got a nested schema, not flattened.
        let schema = stub.lastSchema
        #expect(schema?.type == "object")
        #expect(schema?.properties?["address"]?.type == "object")
        #expect(schema?.properties?["address"]?.properties?["city"]?.type == "string")
    }

    // MARK: - 2. Array of strings

    struct Recipe: Generable, Equatable {
        let name: String
        let ingredients: [String]
        let steps: [String]
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "name":        .init(type: "string"),
                    "ingredients": GenerationSchema(type: "array", items: .init(type: "string")),
                    "steps":       GenerationSchema(type: "array", items: .init(type: "string")),
                ],
                required: ["name", "ingredients", "steps"]
            )
        }
    }

    @Test func arrayOfStringsDecodes() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: """
        {"name":"Toast","ingredients":["bread","butter"],"steps":["toast bread","spread butter"]}
        """))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(to: "A recipe", generating: Recipe.self)
        #expect(response.content.name == "Toast")
        #expect(response.content.ingredients == ["bread", "butter"])
        #expect(response.content.steps.count == 2)
    }

    // MARK: - 3. Primitive type mix (Int, Double, Bool)

    struct Metric: Generable, Equatable {
        let name: String
        let value: Double
        let samples: Int
        let active: Bool
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "name":    .init(type: "string"),
                    "value":   .init(type: "number"),
                    "samples": .init(type: "integer"),
                    "active":  .init(type: "boolean"),
                ],
                required: ["name", "value", "samples", "active"]
            )
        }
    }

    @Test func primitivesRoundTrip() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"name":"latency","value":12.5,"samples":1000,"active":true}"#))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(to: "metric", generating: Metric.self)
        #expect(response.content == Metric(name: "latency", value: 12.5, samples: 1000, active: true))
    }

    // MARK: - 4. Array of objects (nested array)

    struct Item: Generable, Equatable {
        let title: String
        let done: Bool
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "title": .init(type: "string"),
                    "done":  .init(type: "boolean"),
                ],
                required: ["title", "done"]
            )
        }
    }

    struct TodoList: Generable, Equatable {
        let owner: String
        let items: [Item]
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "owner": .init(type: "string"),
                    "items": GenerationSchema(type: "array", items: Item.generationSchema),
                ],
                required: ["owner", "items"]
            )
        }
    }

    @Test func arrayOfObjectsDecodes() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: """
        {"owner":"Alice","items":[{"title":"groceries","done":false},{"title":"laundry","done":true}]}
        """))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(to: "todo", generating: TodoList.self)
        #expect(response.content.owner == "Alice")
        #expect(response.content.items == [
            Item(title: "groceries", done: false),
            Item(title: "laundry", done: true),
        ])
    }

    // MARK: - 5. Optional fields

    struct OptionalReport: Generable, Equatable {
        let title: String
        let summary: String?
        let confidence: Double?
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "title":      .init(type: "string"),
                    "summary":    .init(type: "string"),
                    "confidence": .init(type: "number"),
                ],
                required: ["title"]
            )
        }
    }

    @Test func optionalsAccepted_present() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"title":"hello","summary":"world","confidence":0.9}"#))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(to: "x", generating: OptionalReport.self)
        #expect(response.content == OptionalReport(title: "hello", summary: "world", confidence: 0.9))
    }

    @Test func optionalsAccepted_absent() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"title":"hello"}"#))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        let response = try await session.respond(to: "x", generating: OptionalReport.self)
        #expect(response.content == OptionalReport(title: "hello", summary: nil, confidence: nil))
    }

    // MARK: - 6. includeSchemaInPrompt = false

    @Test func includeSchemaInPromptFalse() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"title":"only"}"#))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        _ = try await session.respond(
            to: "x",
            generating: OptionalReport.self,
            includeSchemaInPrompt: false
        )
        // Backend must NOT see a schema in that case.
        #expect(stub.lastSchema == nil)
    }

    // MARK: - 7. decodingFailure surfaces raw output

    @Test func decodingFailureReturnsRawText() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "not a json object"))
        let session = LanguageModelSession(model: SystemLanguageModel(backend: stub))

        do {
            _ = try await session.respond(to: "x", generating: Recipe.self)
            Issue.record("expected decodingFailure")
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                #expect(raw == "not a json object")
            } else {
                Issue.record("expected decodingFailure, got \(error)")
            }
        }
    }
}
