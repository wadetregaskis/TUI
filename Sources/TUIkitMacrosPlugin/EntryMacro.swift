//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EntryMacro.swift
//
//  The compiler plugin behind `@Entry`: from one property declared in an
//  extension of `EnvironmentValues`, `Transaction`, `ContainerValues` or
//  `FocusedValues`, the key type and the accessors an app would otherwise
//  write by hand.
//
//  Created by Wade Tregaskis
//  License: MIT

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Entry

/// Writes an entry's key and accessors, as SwiftUI's `@Entry` does: the
/// property reads and writes `self[__Key_name.self]`, and a private peer
/// `__Key_name` conforms to the key protocol of the type being extended, its
/// default value the property's initializer.
///
/// The expansion is SwiftUI's, spelled with TUIkit's modules (measured
/// 2026-10-18 with `-dump-macro-expansions` on macOS 15): the default value is
/// re-evaluated at each read (`@__EntryDefaultValue`, so a stored static never
/// has to be `Sendable`), an `Optional` with no initializer defaults to `nil`,
/// and a focused value's key names the type without its `?`.
public struct EntryMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let entry = Entry(declaration), Container(context) != nil else { return [] }
        return [
            "get { self[__Key_\(raw: entry.name).self] }",
            "set { self[__Key_\(raw: entry.name).self] = newValue }",
        ]
    }

    public static func expansion(
        of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let entry = Entry(declaration) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: EntryDiagnostic.notOneVariable))
            return []
        }
        guard let container = Container(context) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: EntryDiagnostic.notInAContainer))
            return []
        }
        let key = "__Key_\(entry.name)"
        if container == .focusedValues {
            // A focused value is absent until a view publishes one: the key
            // names the type the table holds, and the property reads it as an
            // optional of that.
            guard entry.initializer == nil, let wrapped = entry.type?.as(OptionalTypeSyntax.self)?.wrappedType
            else {
                context.diagnose(Diagnostic(node: Syntax(node), message: EntryDiagnostic.focusedNotOptional))
                return []
            }
            return [
                """
                private struct \(raw: key): \(raw: container.keyProtocol) {
                    typealias Value = \(wrapped.trimmed)
                }
                """
            ]
        }
        let value: String
        if let initializer = entry.initializer {
            value = initializer.trimmedDescription
        } else if entry.type?.is(OptionalTypeSyntax.self) == true
            || entry.type?.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) == true
        {
            value = "nil"
        } else {
            context.diagnose(Diagnostic(node: Syntax(node), message: EntryDiagnostic.noDefault(entry.name)))
            return []
        }
        let typeAnnotation = entry.type.map { ": \($0.trimmedDescription)" } ?? ""
        return [
            """
            private struct \(raw: key): \(raw: container.keyProtocol) {
                @TUIkitMacros.__EntryDefaultValue
                static var defaultValue\(raw: typeAnnotation) = \(raw: value)
            }
            """
        ]
    }

    /// The one property `@Entry` is attached to.
    private struct Entry {
        let name: String
        let type: TypeSyntax?
        let initializer: ExprSyntax?

        init?(_ declaration: some DeclSyntaxProtocol) {
            guard let variable = declaration.as(VariableDeclSyntax.self),
                variable.bindings.count == 1,
                let binding = variable.bindings.first,
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                binding.accessorBlock == nil
            else { return nil }
            name = identifier.identifier.text
            type = binding.typeAnnotation?.type
            initializer = binding.initializer?.value
        }
    }

    /// The four types an entry can extend, by the extension's own name.
    private enum Container {
        case environmentValues, transaction, containerValues, focusedValues

        /// The extension `@Entry` stands in, read from its last name
        /// component, so `extension TUIkit.EnvironmentValues` counts too.
        init?(_ context: some MacroExpansionContext) {
            guard let extensionDecl = context.lexicalContext.first?.as(ExtensionDeclSyntax.self) else {
                return nil
            }
            let name = extensionDecl.extendedType.trimmedDescription.split(separator: ".").last.map(String.init)
            switch name {
            case "EnvironmentValues": self = .environmentValues
            case "Transaction": self = .transaction
            case "ContainerValues": self = .containerValues
            case "FocusedValues": self = .focusedValues
            default: return nil
            }
        }

        /// The key protocol, by the module that declares it: an app imports
        /// `TUIkit`, which re-exports both.
        var keyProtocol: String {
            switch self {
            case .environmentValues: "TUIkitCore.EnvironmentKey"
            case .transaction: "TUIkitCore.TransactionKey"
            case .containerValues: "TUIkitFoundation.ContainerValueKey"
            case .focusedValues: "TUIkitFoundation.FocusedValueKey"
            }
        }
    }
}

// MARK: - @__EntryDefaultValue

/// Turns the key's `static var defaultValue = …` into a getter that returns
/// the initializer, so the default is made at each read, as SwiftUI's is, and
/// a static stored value never has to be `Sendable`. Not for apps: `@Entry`
/// writes it.
public struct EntryDefaultValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let initializer = declaration.as(VariableDeclSyntax.self)?.bindings.first?.initializer?.value
        else { return [] }
        return ["get { \(initializer.trimmed) }"]
    }
}

// MARK: - Diagnostics

enum EntryDiagnostic: DiagnosticMessage {
    case notOneVariable
    case notInAContainer
    case focusedNotOptional
    case noDefault(String)

    var message: String {
        switch self {
        case .notOneVariable:
            "@Entry applies to one stored 'var' with a single name"
        case .notInAContainer:
            "@Entry applies inside an extension of EnvironmentValues, Transaction, ContainerValues or FocusedValues"
        case .focusedNotOptional:
            "a FocusedValues entry is nil until a view publishes one: give it an Optional type and no initializer"
        case .noDefault(let name):
            "@Entry needs a default value for '\(name)': give it an initializer, or an Optional type"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .notOneVariable: MessageID(domain: "TUIkitMacros", id: "entryNotOneVariable")
        case .notInAContainer: MessageID(domain: "TUIkitMacros", id: "entryNotInAContainer")
        case .focusedNotOptional: MessageID(domain: "TUIkitMacros", id: "entryFocusedNotOptional")
        case .noDefault: MessageID(domain: "TUIkitMacros", id: "entryNoDefault")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
