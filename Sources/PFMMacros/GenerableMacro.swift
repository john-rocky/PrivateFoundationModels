import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Drop-in clone of Apple's `@Generable` macro. Walks a struct's stored
/// properties, infers the JSON-Schema-shaped `generationSchema`, emits
/// the static var directly on the type, and adds an empty
/// `: Generable` conformance extension. The member-attached emission is
/// what lets `@Generable` work on nested types — the synthesized property
/// resolves names in the enclosing type's scope rather than at module
/// scope.
///
/// Supported field types: `String`, `Int`/`Int32`/`Int64`/`UInt`/`UInt32`/`UInt64`,
/// `Double`/`Float`/`CGFloat`, `Bool`, `[T]` where `T` is any of the above
/// (or another `@Generable` type), and optional variants. Nested
/// `@Generable` types are referenced by their static `generationSchema`
/// so the schema composes naturally.
///
/// Optional fields (`T?`) drop out of `required`. A peer `@Guide(description:)`
/// attribute on a stored property sets the schema's `description` for that
/// field.
public struct GenerableMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro: emit `static var generationSchema` inside the type

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let memberBlock = memberBlockOf(declaration, attribute: node, in: context) else {
            return []
        }
        let macroDescription = extractMacroDescription(from: node)
        let fields = collectFields(in: memberBlock)
        let body = renderSchemaLiteral(fields: fields, macroDescription: macroDescription)
        let decl: DeclSyntax = """
        public static var generationSchema: PrivateFoundationModels.GenerationSchema {
            \(raw: body)
        }
        """
        return [decl]
    }

    // MARK: - ExtensionMacro: empty `: Generable` conformance

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let decl = try ExtensionDeclSyntax(
            "extension \(raw: type.trimmedDescription): PrivateFoundationModels.Generable {}"
        )
        return [decl]
    }

    // MARK: - Old-path helper to surface diagnostics

    private static func memberBlockOf(
        _ declaration: some DeclGroupSyntax,
        attribute node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> MemberBlockSyntax? {
        if let s = declaration.as(StructDeclSyntax.self) { return s.memberBlock }
        if let c = declaration.as(ClassDeclSyntax.self)  { return c.memberBlock }
        context.diagnose(
            Diagnostic(
                node: Syntax(node),
                message: PFMDiagnostic(
                    id: "Generable.notAStruct",
                    message: "@Generable can only be applied to struct or class declarations.",
                    severity: .error
                )
            )
        )
        return nil
    }

    private static func renderSchemaLiteral(
        fields: [Field],
        macroDescription: String?
    ) -> String {
        let propertyEntries = fields.map { field -> String in
            let schemaExpr = schemaExpression(for: field.typeSyntax)
            let withDescription: String
            if let description = field.description {
                withDescription = withDescriptionInjected(
                    base: schemaExpr,
                    description: description,
                    typeSyntax: field.typeSyntax
                )
            } else {
                withDescription = schemaExpr
            }
            return "        \"\(field.name)\": \(withDescription),"
        }.joined(separator: "\n")

        let requiredList = fields
            .filter { !$0.isOptional }
            .map { "\"\($0.name)\"" }
            .joined(separator: ", ")

        let macroDescriptionLine = macroDescription.map { d in
            ",\n    description: \(stringLiteral(d))"
        } ?? ""

        return """
        PrivateFoundationModels.GenerationSchema(
            type: "object",
            properties: [
        \(propertyEntries)
            ],
            required: [\(requiredList)]\(macroDescriptionLine)
        )
        """
    }

    private static func collectFields(in memberBlock: MemberBlockSyntax) -> [Field] {
        var out: [Field] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            if varDecl.bindings.contains(where: { $0.accessorBlock != nil }) { continue }
            if varDecl.modifiers.contains(where: {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            }) {
                continue
            }
            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let typeAnno = binding.typeAnnotation else { continue }
                let (isOptional, baseTypeSyntax) = unwrapOptional(typeAnno.type)
                let description = extractGuideDescription(from: varDecl)
                out.append(Field(
                    name: identifier,
                    typeSyntax: baseTypeSyntax,
                    isOptional: isOptional,
                    description: description
                ))
            }
        }
        return out
    }


    // MARK: - Helpers

    private struct Field {
        let name: String
        let typeSyntax: TypeSyntax
        let isOptional: Bool
        let description: String?
    }

    /// `T?`, `Optional<T>` → (true, T). Anything else → (false, anything).
    private static func unwrapOptional(_ type: TypeSyntax) -> (isOptional: Bool, base: TypeSyntax) {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return (true, optional.wrappedType)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return (true, implicit.wrappedType)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self),
           identifier.name.text == "Optional",
           let inner = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
            return (true, inner)
        }
        return (false, type)
    }

    /// Render the schema expression for a Swift type. Maps primitives to
    /// JSON-Schema types and falls back to `T.generationSchema` for
    /// user-defined types (which must conform to `Generable`).
    private static func schemaExpression(for type: TypeSyntax) -> String {
        // Array<T> sugar.
        if let arr = type.as(ArrayTypeSyntax.self) {
            let element = schemaExpression(for: arr.element)
            return "PrivateFoundationModels.GenerationSchema(type: \"array\", items: \(element))"
        }
        // Optional already stripped by caller, but be defensive.
        let (isOptional, base) = unwrapOptional(type)
        if isOptional { return schemaExpression(for: base) }

        let trimmed = type.trimmedDescription
        switch trimmed {
        case "String":
            return ".init(type: \"string\")"
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return ".init(type: \"integer\")"
        case "Double", "Float", "Float32", "Float64", "CGFloat":
            return ".init(type: \"number\")"
        case "Bool":
            return ".init(type: \"boolean\")"
        default:
            // Treat as user-defined Generable; reference its static schema.
            return "\(trimmed).generationSchema"
        }
    }

    /// Inject a `description:` argument into a schema literal. The schema
    /// builder we generate uses `.init(type: ...)` for primitives, which
    /// happens to be `GenerationSchema.init(type:properties:required:items:enum:description:)`,
    /// so the description slot is named.
    private static func withDescriptionInjected(
        base: String,
        description: String,
        typeSyntax: TypeSyntax
    ) -> String {
        let literal = stringLiteral(description)
        // For ".init(type: \"string\")" we can splice description before
        // the closing paren. Same for full GenerationSchema(...) literals.
        if let lastParenIndex = base.lastIndex(of: ")") {
            let head = base[..<lastParenIndex]
            return "\(head), description: \(literal))"
        }
        return base
    }

    private static func extractGuideDescription(from varDecl: VariableDeclSyntax) -> String? {
        for attribute in varDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            let name = attr.attributeName.trimmedDescription
            if name == "Guide" || name == "PrivateFoundationModels.Guide" {
                if case let .argumentList(args) = attr.arguments {
                    for arg in args {
                        let label = arg.label?.text
                        if label == "description" || label == nil {
                            if let str = arg.expression.as(StringLiteralExprSyntax.self) {
                                return str.segments
                                    .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
                                    .joined()
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func extractMacroDescription(from node: AttributeSyntax) -> String? {
        guard case let .argumentList(args) = node.arguments else { return nil }
        for arg in args {
            if arg.label?.text == "description",
               let str = arg.expression.as(StringLiteralExprSyntax.self) {
                return str.segments
                    .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
                    .joined()
            }
        }
        return nil
    }

    /// Produce a Swift string literal expression with a payload. We use
    /// double quotes and escape backslashes / quotes / newlines.
    private static func stringLiteral(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count + 2)
        escaped.append("\"")
        for char in text {
            switch char {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default:   escaped.append(char)
            }
        }
        escaped.append("\"")
        return escaped
    }
}

/// Trivial diagnostic message used for emit-and-bail errors.
struct PFMDiagnostic: DiagnosticMessage {
    let id: String
    let message: String
    let severity: DiagnosticSeverity

    var diagnosticID: MessageID { MessageID(domain: "PFMMacros", id: id) }
}
