import Foundation

// MARK: - Nested type aliases for Apple FoundationModels source compatibility

/// Apple ships `Response`, `ResponseStream`, and `GenerationError` as types
/// nested inside `LanguageModelSession`. The PrivateFoundationModels module
/// declares the same types at the top level so user code can type
/// `Response<MyType>` without the prefix. These typealiases re-export them
/// from the nested location so the alternate spelling
/// (`LanguageModelSession.Response<MyType>`, etc.) compiles identically.
extension LanguageModelSession {
    public typealias Response<Content: Sendable> = PrivateFoundationModels.Response<Content>
    public typealias ResponseStream<Content: Sendable> = PrivateFoundationModels.ResponseStream<Content>
    public typealias GenerationError = PrivateFoundationModels.GenerationError
}

// MARK: - InstructionsBuilder

/// Result-builder shim that lets callers write
/// `LanguageModelSession { "You are…" }` exactly like Apple's framework.
/// Apple's `@InstructionsBuilder` accepts a heterogeneous block of string
/// literals, `Prompt` references, and conditional logic; the v0.1 shim
/// implements the common subset: one or more string literals concatenated
/// with newlines.
@resultBuilder
public enum InstructionsBuilder {
    public static func buildBlock(_ components: String...) -> Instructions {
        Instructions(components.joined(separator: "\n"))
    }

    public static func buildBlock(_ components: Instructions...) -> Instructions {
        Instructions(components.map(\.text).joined(separator: "\n"))
    }

    public static func buildExpression(_ expression: String) -> Instructions {
        Instructions(expression)
    }

    public static func buildExpression(_ expression: Instructions) -> Instructions {
        expression
    }

    public static func buildEither(first component: Instructions) -> Instructions { component }
    public static func buildEither(second component: Instructions) -> Instructions { component }
    public static func buildOptional(_ component: Instructions?) -> Instructions {
        component ?? Instructions("")
    }
}
