import Foundation
import Testing
@testable import PrivateFoundationModels

@Suite("@Generable macro")
struct GenerableMacroTests {

    // MARK: - 1. Basic primitives

    @Generable
    struct WeatherReport: Equatable {
        let city: String
        let temperatureCelsius: Double
        let humidity: Int
        let raining: Bool
    }

    @Test func primitivesGenerateCorrectSchema() {
        let schema = WeatherReport.generationSchema
        #expect(schema.type == "object")
        #expect(schema.properties?["city"]?.type == "string")
        #expect(schema.properties?["temperatureCelsius"]?.type == "number")
        #expect(schema.properties?["humidity"]?.type == "integer")
        #expect(schema.properties?["raining"]?.type == "boolean")
        let required = Set(schema.required ?? [])
        #expect(required == ["city", "temperatureCelsius", "humidity", "raining"])
    }

    @Test func primitivesDecodeFromJSON() throws {
        let json = #"{"city":"Tokyo","temperatureCelsius":22.5,"humidity":60,"raining":false}"#
        let report = try JSONDecoder().decode(WeatherReport.self, from: Data(json.utf8))
        #expect(report == WeatherReport(
            city: "Tokyo",
            temperatureCelsius: 22.5,
            humidity: 60,
            raining: false
        ))
    }

    // MARK: - 2. Optional fields drop out of `required`

    @Generable
    struct Profile: Equatable {
        let name: String
        let nickname: String?
        let age: Int?
    }

    @Test func optionalFieldsAreNotRequired() {
        let required = Set(Profile.generationSchema.required ?? [])
        #expect(required == ["name"])
        #expect(Profile.generationSchema.properties?["nickname"]?.type == "string")
        #expect(Profile.generationSchema.properties?["age"]?.type == "integer")
    }

    @Test func optionalsDecodePresent() throws {
        let json = #"{"name":"Alice","nickname":"Al","age":34}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p == Profile(name: "Alice", nickname: "Al", age: 34))
    }

    @Test func optionalsDecodeAbsent() throws {
        let json = #"{"name":"Alice"}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p == Profile(name: "Alice", nickname: nil, age: nil))
    }

    // MARK: - 3. Array fields

    @Generable
    struct ShoppingList: Equatable {
        let title: String
        let items: [String]
    }

    @Test func arrayFieldsBecomeArraySchemas() {
        let itemsSchema = ShoppingList.generationSchema.properties?["items"]
        #expect(itemsSchema?.type == "array")
        #expect(itemsSchema?.items?.value.type == "string")
    }

    // MARK: - 4. Nested @Generable

    @Generable
    struct Address: Equatable {
        let city: String
        let country: String
    }

    @Generable
    struct Person: Equatable {
        let name: String
        let address: Address
    }

    @Test func nestedGenerableComposes() {
        let nested = Person.generationSchema.properties?["address"]
        #expect(nested?.type == "object")
        #expect(nested?.properties?["city"]?.type == "string")
        #expect(nested?.properties?["country"]?.type == "string")
        let nestedRequired = Set(nested?.required ?? [])
        #expect(nestedRequired == ["city", "country"])
    }

    @Test func nestedGenerableDecodes() throws {
        let json = """
        {"name":"Alice","address":{"city":"Osaka","country":"Japan"}}
        """
        let p = try JSONDecoder().decode(Person.self, from: Data(json.utf8))
        #expect(p == Person(name: "Alice", address: Address(city: "Osaka", country: "Japan")))
    }

    // MARK: - 5. @Guide(description:)

    @Generable
    struct Annotated {
        @Guide(description: "Full given + family name.")
        let name: String

        @Guide(description: "Age in years, integer.")
        let age: Int
    }

    @Test func guideDescriptionsFlowIntoSchema() {
        let schema = Annotated.generationSchema
        #expect(schema.properties?["name"]?.description == "Full given + family name.")
        #expect(schema.properties?["age"]?.description == "Age in years, integer.")
    }

    // MARK: - 6. Macro-level description

    @Generable(description: "A simple identifier object.")
    struct ID {
        let value: String
    }

    @Test func macroDescriptionFlowsIntoTopLevelSchema() {
        #expect(ID.generationSchema.description == "A simple identifier object.")
    }

    // MARK: - 7. End-to-end with LanguageModelSession.respond(generating:)

    @Generable
    struct Card: Equatable {
        let suit: String
        let rank: Int
    }

    @Test func sessionDecodesMacroSynthesizedGenerable() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"suit":"hearts","rank":11}"#))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let reply = try await session.respond(to: "Deal a card.", generating: Card.self)
        #expect(reply.content == Card(suit: "hearts", rank: 11))

        // Confirm the backend received the macro-generated schema.
        #expect(stub.lastSchema?.type == "object")
        #expect(Set(stub.lastSchema?.required ?? []) == ["suit", "rank"])
    }
}
