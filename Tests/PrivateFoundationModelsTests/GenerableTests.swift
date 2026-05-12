import Foundation
import Testing
@testable import PrivateFoundationModels

@Suite("Generable + GenerationSchema")
struct GenerableTests {
    struct Report: Generable, Equatable {
        let city: String
        let temperature: Double
        let conditions: String

        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "city":        .init(type: "string"),
                    "temperature": .init(type: "number"),
                    "conditions":  .init(type: "string"),
                ],
                required: ["city", "temperature", "conditions"]
            )
        }
    }

    @Test func primitives() {
        #expect(String.generationSchema.type == "string")
        #expect(Int.generationSchema.type == "integer")
        #expect(Double.generationSchema.type == "number")
        #expect(Bool.generationSchema.type == "boolean")
        #expect([Int].generationSchema.type == "array")
        #expect([Int].generationSchema.items?.value.type == "integer")
    }

    @Test func objectSchema() {
        let schema = Report.generationSchema
        #expect(schema.type == "object")
        #expect(schema.required?.contains("city") == true)
        #expect(schema.properties?["temperature"]?.type == "number")
    }

    @Test func schemaSerializes() throws {
        let schema = Report.generationSchema
        let data = try JSONEncoder().encode(schema)
        let restored = try JSONDecoder().decode(GenerationSchema.self, from: data)
        #expect(restored == schema)
    }

    @Test func reportRoundTrips() throws {
        let report = Report(city: "Tokyo", temperature: 22.5, conditions: "Sunny")
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(Report.self, from: data)
        #expect(decoded == report)
    }
}
