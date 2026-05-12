import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macro that reads `@Guide(description:)` annotations off stored
/// properties so the `@Generable` extension can inject per-field
/// descriptions into the generated schema. Has no own expansion — it
/// exists purely so the compiler recognizes `@Guide(...)` as a valid
/// attribute slot. The `@Generable` extension macro walks the same
/// attribute list directly.
public struct GuideMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
