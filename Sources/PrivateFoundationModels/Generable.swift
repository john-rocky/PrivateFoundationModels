import Foundation

/// A type the model can produce as structured output. Mirrors
/// `FoundationModels.Generable`.
///
/// Apple's `@Generable` macro auto-derives `generationSchema` from the type's
/// stored properties. Until we ship the equivalent macro, conformers must
/// supply `generationSchema` by hand. The protocol is `Codable` so structured
/// responses round-trip through JSON, which is what the backend renders into.
///
/// ```swift
/// struct WeatherReport: Generable {
///     let city: String
///     let temperatureCelsius: Double
///     let conditions: String
///
///     static var generationSchema: GenerationSchema {
///         GenerationSchema(
///             type: "object",
///             properties: [
///                 "city":               .init(type: "string"),
///                 "temperatureCelsius": .init(type: "number"),
///                 "conditions":         .init(type: "string"),
///             ],
///             required: ["city", "temperatureCelsius", "conditions"]
///         )
///     }
/// }
/// ```
public protocol Generable: Codable, Sendable {
    /// JSON-Schema-shaped description of the expected output. The backend
    /// renders this into a grammar / format directive understood by the
    /// underlying model.
    static var generationSchema: GenerationSchema { get }
}

/// JSON-Schema-style description used to constrain structured generation.
/// Intentionally narrow — we only model the subset of JSON Schema that maps
/// cleanly to GBNF / Outlines / Apple's grammar-constrained sampler.
public struct GenerationSchema: Sendable, Codable, Hashable {
    /// JSON Schema primitive: "object", "array", "string", "number",
    /// "integer", "boolean", or "null".
    public let type: String

    /// For "object" schemas: property name → child schema.
    public let properties: [String: GenerationSchema]?

    /// For "object" schemas: which property names must be present.
    public let required: [String]?

    /// For "array" schemas: schema of each element.
    public let items: Box<GenerationSchema>?

    /// For "string" / "integer" / "number" schemas: enum of permitted values.
    /// Rendered into the grammar as a top-level alternation.
    public let `enum`: [String]?

    /// Free-text describing what this field is for. Models that support
    /// schema descriptions (Apple FM, Gemini, GPT-4o structured outputs) use
    /// this as a per-field instruction.
    public let description: String?

    public init(
        type: String,
        properties: [String: GenerationSchema]? = nil,
        required: [String]? = nil,
        items: GenerationSchema? = nil,
        `enum`: [String]? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items.map(Box.init)
        self.enum = `enum`
        self.description = description
    }

    /// Reference wrapper. `GenerationSchema` is recursive via `items`, and
    /// Swift structs cannot contain themselves directly.
    public final class Box<T: Sendable & Codable & Hashable>: @unchecked Sendable, Codable, Hashable {
        public let value: T
        public init(_ value: T) { self.value = value }

        public init(from decoder: Decoder) throws {
            self.value = try T(from: decoder)
        }
        public func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
        public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool { lhs.value == rhs.value }
        public func hash(into hasher: inout Hasher) { hasher.combine(value) }
    }
}

// MARK: - Conformances for primitives

extension String: Generable {
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: "string")
    }
}

extension Int: Generable {
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: "integer")
    }
}

extension Double: Generable {
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: "number")
    }
}

extension Bool: Generable {
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: "boolean")
    }
}

extension Array: Generable where Element: Generable {
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: "array", items: Element.generationSchema)
    }
}
