import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private struct EntryDeclaration {
    let name: String
    let type: TypeSyntax?
    let initial: ExprSyntax?
    init(_ declaration: some DeclSyntaxProtocol) throws {
        guard let variable = declaration.as(VariableDeclSyntax.self), variable.bindingSpecifier.text == "var",
              variable.bindings.count == 1, let binding = variable.bindings.first, binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MacroExpansionErrorMessage("@Entry requires one stored variable")
        }
        name = identifier.identifier.text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        type = binding.typeAnnotation?.type
        initial = binding.initializer?.value
    }
}

public struct EntryMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        let key = "__Key_" + (try EntryDeclaration(declaration)).name
        return ["get { self[\(raw: key).self] }", "set { self[\(raw: key).self] = newValue }"]
    }
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let entry = try EntryDeclaration(declaration)
        let key = "__Key_" + entry.name
        if let type = entry.type {
            let initial = entry.initial ?? "nil"
            return ["""
                private enum \(raw: key): SwiftUI.EnvironmentKey {
                    static var defaultValue: \(type) { \(initial) }
                }
                """]
        }
        guard let initial = entry.initial else { throw MacroExpansionErrorMessage("@Entry requires a type or initial value") }
        return ["""
            private enum \(raw: key): SwiftUI.EnvironmentKey {
                static let defaultValue = \(initial)
            }
            """]
    }
}

@main struct QtSwiftUIPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [EntryMacro.self]
}
