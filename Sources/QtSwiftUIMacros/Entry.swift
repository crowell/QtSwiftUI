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
        return ["get { self[\(raw: key).self] }", "set { self[\(raw: key).self] = newValue }", "_modify { yield &self[\(raw: key).self] }"]
    }
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let entry = try EntryDeclaration(declaration)
        let key = "__Key_" + entry.name
        let container = context.lexicalContext.compactMap { $0.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription }.first
        let protocolName = container?.split(separator: ".").last == "ContainerValues" ? "ContainerValueKey" : "EnvironmentKey"
        if let type = entry.type {
            let initial = entry.initial ?? "nil"
            return ["""
                private enum \(raw: key): SwiftUI.\(raw: protocolName) {
                    static var defaultValue: \(type) { \(initial) }
                }
                """]
        }
        guard let initial = entry.initial else { throw MacroExpansionErrorMessage("@Entry requires a type or initial value") }
        return ["""
            private enum \(raw: key): SwiftUI.\(raw: protocolName) {
                @SwiftUI.__EntryDefaultValue static var defaultValue = \(initial)
            }
            """]
    }
}

// A computed getter keeps Swift's inferred initializer type without sharing a non-Sendable value.
public struct EntryDefaultValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let value = try EntryDeclaration(declaration).initial else {
            throw MacroExpansionErrorMessage("An entry default requires an initializer")
        }
        return ["get { \(value) }"]
    }
}

@main struct QtSwiftUIPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [EntryMacro.self, EntryDefaultValueMacro.self]
}
