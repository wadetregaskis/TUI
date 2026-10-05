//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableMacro.swift
//
//  The compiler plugin behind `@Animatable` and `@AnimatableIgnored`
//  (decisions A52): it writes the `animatableData` a type would otherwise
//  spell by hand, from its stored properties.
//
//  Created by Wade Tregaskis
//  License: MIT

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct TUIkitMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [AnimatableMacro.self, AnimatableIgnoredMacro.self]
}

// MARK: - @Animatable

/// Synthesises `Animatable`'s `animatableData` from a type's animatable stored
/// properties, as SwiftUI's macro of the same name does, and the conformance
/// where the type does not already have it.
///
/// An animatable property is a stored instance `var` with its type written
/// out and no `@AnimatableIgnored`. The data is an `AnimatableValues` of each
/// one's own `AnimatableData`, in declaration order — what a type writes by
/// hand when it has several (`AnimatablePair` nests only two).
public struct AnimatableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let properties = animatableProperties(of: declaration, in: context)
        guard !properties.isEmpty else {
            context.diagnose(
                Diagnostic(node: Syntax(node), message: AnimatableDiagnostic.noProperties))
            return []
        }
        let access = accessLevel(of: declaration)
        let types = properties.map { "\($0.type).AnimatableData" }.joined(separator: ", ")
        let reads = properties.map { "\($0.name).animatableData" }.joined(separator: ", ")
        let writes =
            properties.count == 1
            ? "\(properties[0].name).animatableData = newValue.value"
            : "(\(reads)) = newValue.value"
        // `@MainActor` because TUIkit's `Animatable` is: the properties' own
        // `animatableData` are main-actor members, and a nonisolated getter
        // could not read them.
        return [
            """
            @MainActor \(raw: access)var animatableData: TUIkitCore.AnimatableValues<\(raw: types)> {
                get { TUIkitCore.AnimatableValues(\(raw: reads)) }
                set { \(raw: writes) }
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The compiler names only the conformances the type does not already
        // have: none, and the type is Animatable already. Nor for a type with
        // nothing to animate, which the member role has already said is an
        // error: a conformance with no data would only add a second one.
        guard !protocols.isEmpty, !animatableProperties(of: declaration, in: nil).isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): TUIkitCore.Animatable {}")]
    }

    /// The animatable stored properties of `declaration`, with their written
    /// types; a property that would be one but has no written type is
    /// diagnosed in `context`, since the data's type is spelt from it.
    static func animatableProperties(
        of declaration: some DeclGroupSyntax, in context: (any MacroExpansionContext)?
    ) -> [(name: String, type: String)] {
        var found: [(name: String, type: String)] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                variable.bindingSpecifier.tokenKind == .keyword(.var),
                !variable.modifiers.contains(where: {
                    [.keyword(.static), .keyword(.class), .keyword(.lazy)].contains($0.name.tokenKind)
                }),
                !variable.attributes.contains(where: { isAnimatableIgnored($0) })
            else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                    isStored(binding)
                else { continue }
                guard let type = binding.typeAnnotation?.type ?? sharedType(of: binding, in: variable) else {
                    context?.diagnose(
                        Diagnostic(
                            node: Syntax(binding), message: AnimatableDiagnostic.untypedProperty(identifier.identifier.text)))
                    continue
                }
                found.append((identifier.identifier.text, type.trimmedDescription))
            }
        }
        return found
    }

    /// `var a, b: Double` writes the type once, on the last binding.
    private static func sharedType(of binding: PatternBindingSyntax, in variable: VariableDeclSyntax) -> TypeSyntax? {
        guard binding.initializer == nil else { return nil }
        let bindings = Array(variable.bindings)
        guard let index = bindings.firstIndex(where: { $0.id == binding.id }) else { return nil }
        return bindings[index...].first { $0.typeAnnotation != nil }?.typeAnnotation?.type
    }

    /// Whether `binding` stores a value: no accessors, or only observers.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }  // a getter body
        return list.allSatisfy {
            [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind)
        }
    }

    private static func isAnimatableIgnored(_ element: AttributeListSyntax.Element) -> Bool {
        guard case .attribute(let attribute) = element else { return false }
        return attribute.attributeName.trimmedDescription.hasSuffix("AnimatableIgnored")
    }

    /// The access the conformance's witness needs: the type's own, for a
    /// public or package type, so the conformance can be used where it can.
    private static func accessLevel(of declaration: some DeclGroupSyntax) -> String {
        for modifier in declaration.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open): return "public "
            case .keyword(.package): return "package "
            default: continue
            }
        }
        return ""
    }
}

// MARK: - @AnimatableIgnored

/// Marks a property `@Animatable` leaves out of `animatableData`. A marker
/// only: it adds no accessor, so the property stores as it did.
public struct AnimatableIgnoredMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        []
    }
}

// MARK: - Diagnostics

enum AnimatableDiagnostic: DiagnosticMessage {
    case noProperties
    case untypedProperty(String)

    var message: String {
        switch self {
        case .noProperties:
            "@Animatable needs a stored 'var' property to animate; a type with none has no animatable data"
        case .untypedProperty(let name):
            "@Animatable needs the type of '\(name)' written out, to spell the animatable data from it; "
                + "write it, or mark the property @AnimatableIgnored"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .noProperties: MessageID(domain: "TUIkitMacros", id: "noProperties")
        case .untypedProperty: MessageID(domain: "TUIkitMacros", id: "untypedProperty")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
