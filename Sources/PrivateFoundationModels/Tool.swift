import Foundation

/// A function the model can call. Mirrors `FoundationModels.Tool`.
///
/// A tool is registered with a session at construction time:
/// `LanguageModelSession(tools: [...])`. During `respond` / `streamResponse`,
/// if the model emits a tool call, the session will invoke `call(arguments:)`
/// on the matching tool, append a `.toolCall` + `.toolOutput` pair to the
/// transcript, and feed the output back into the model for the final
/// response.
///
/// ```swift
/// struct WeatherTool: Tool {
///     struct Arguments: Generable {
///         let city: String
///         static var generationSchema: GenerationSchema {
///             GenerationSchema(
///                 type: "object",
///                 properties: ["city": .init(type: "string")],
///                 required: ["city"]
///             )
///         }
///     }
///     let name = "weather"
///     let description = "Look up current weather for a city."
///     func call(arguments: Arguments) async throws -> String {
///         "Sunny, 22°C in \(arguments.city)"
///     }
/// }
/// ```
public protocol Tool: Sendable {
    associatedtype Arguments: Generable
    associatedtype Output: Sendable

    /// Stable identifier the model uses in `<tool_call>`. Must match `[a-z_][a-z0-9_]*`
    /// for the broadest backend compatibility.
    var name: String { get }

    /// Free-text shown to the model so it knows when to invoke the tool.
    var description: String { get }

    /// Whether the tool's output should be added back to the model's context
    /// for a follow-up response. Apple's framework defaults this to `true`;
    /// set to `false` for side-effect-only tools (e.g. `playSound`) where the
    /// model doesn't need to react to the result.
    var includesSchemaInInstructions: Bool { get }

    /// Invoke the tool. Throwing aborts the surrounding `respond` call.
    func call(arguments: Arguments) async throws -> Output
}

extension Tool {
    public var includesSchemaInInstructions: Bool { true }
}

/// Type-erased tool, used internally by `LanguageModelSession` so it can hold
/// a heterogeneous list of tools.
public struct AnyTool: Sendable {
    public let name: String
    public let description: String
    public let argumentsSchema: GenerationSchema
    public let invoke: @Sendable (_ argumentsJSON: String) async throws -> String

    public init<T: Tool>(_ tool: T) {
        self.name = tool.name
        self.description = tool.description
        self.argumentsSchema = T.Arguments.generationSchema
        self.invoke = { argumentsJSON in
            let data = Data(argumentsJSON.utf8)
            let arguments = try JSONDecoder().decode(T.Arguments.self, from: data)
            let output = try await tool.call(arguments: arguments)
            return try Self.stringify(output)
        }
    }

    /// Erase an existential `any Tool`. Used by the
    /// `LanguageModelSession(tools: [any Tool], ...)` convenience initializer.
    public static func erased(_ tool: any Tool) -> AnyTool {
        // Re-bind through a generic helper so the concrete-type `init<T: Tool>`
        // overload is selected.
        return _eraseHelper(tool)
    }

    private static func stringify(_ value: Any) throws -> String {
        if let s = value as? String { return s }
        if let encodable = value as? any Encodable {
            let data = try JSONEncoder().encode(AnyEncodable(encodable))
            return String(data: data, encoding: .utf8) ?? "null"
        }
        return String(describing: value)
    }
}

// Tiny helper so we can erase Encodable without requiring Generable on the
// tool's output type.
private struct AnyEncodable: Encodable {
    let wrapped: any Encodable
    init(_ wrapped: any Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}

// Free helper that opens the existential, picking the concrete-type init.
private func _eraseHelper<T: Tool>(_ tool: T) -> AnyTool {
    AnyTool(tool)
}
