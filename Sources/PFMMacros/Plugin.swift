import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PFMMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GenerableMacro.self,
        GuideMacro.self,
    ]
}
