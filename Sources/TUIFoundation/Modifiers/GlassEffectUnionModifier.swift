//  🖥️ TUI — A Terminal UI framework for Swift
//  GlassEffectUnionModifier.swift
//
//  `glassEffectUnion(id:namespace:)`: glass that a container draws as one
//  shape wherever its members are.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Associates any glass effects defined within this view to a union with
    /// the provided id — mirrors SwiftUI's `glassEffectUnion(id:namespace:)`.
    ///
    /// In a ``GlassEffectContainer``, the glass of every view in one union —
    /// the same `id` in the same `namespace`, the same glass and the same kind
    /// of shape — is drawn as one shape: the smallest rectangle round all of
    /// them, wherever they are, as SwiftUI's union is one shape round all of
    /// its members.
    ///
    /// ```swift
    /// GlassEffectContainer {
    ///     HStack {
    ///         ForEach(items) { item in
    ///             Text(item.id)
    ///                 .padding()
    ///                 .glassEffect()
    ///                 .glassEffectUnion(id: item.placement, namespace: namespace)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Outside a container, or with a `nil` id, the glass is its own.
    ///
    /// - Parameters:
    ///   - id: The union the glass joins, or `nil` for none.
    ///   - namespace: The namespace the id is in.
    /// - Returns: The view, its glass in the union.
    public func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View {
        environment(\.glassEffectUnion, id.map { GlassNamespacedID(namespace: namespace, id: AnyHashable($0)) })
    }
}

/// An id in a namespace, as ``View/glassEffectUnion(id:namespace:)`` names a
/// union.
struct GlassNamespacedID: Hashable {
    let namespace: Namespace.ID
    let id: AnyHashable
}

private struct GlassEffectUnionKey: EnvironmentKey {
    static var defaultValue: GlassNamespacedID? { nil }
}

extension EnvironmentValues {
    /// The union the glass in this subtree belongs to, or `nil`.
    var glassEffectUnion: GlassNamespacedID? {
        get { self[GlassEffectUnionKey.self] }
        set { self[GlassEffectUnionKey.self] = newValue }
    }
}
