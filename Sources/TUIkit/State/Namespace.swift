//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Namespace.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - Namespace

/// A dynamic property whose value names a namespace that belongs to the view
/// holding it. Mirrors SwiftUI's `@Namespace`.
///
/// ```swift
/// struct Gallery: View {
///     @Namespace private var gallery
///
///     var body: some View {
///         Grid { … }
///             .onAppear { print(gallery) }
///     }
/// }
/// ```
///
/// The ``ID`` is derived from the persistent identity of the view that holds
/// the property, and from the property's place among that view's other
/// dynamic properties, so it is the same on every frame for as long as the
/// view stays where it is in the tree, and two `@Namespace` properties — on one
/// view or on two — never share one.
///
/// Read before the view first renders — in an initializer, say — the value is
/// a placeholder unique to this property value, as SwiftUI's is outside a
/// body.
@propertyWrapper
public struct Namespace: DynamicProperty, RenderIdentityBindable, Sendable {
    /// Where the bound id lives: a reference, so the binding made at render
    /// reaches the copy of the property `body` reads.
    private let box = Box()

    /// Creates a namespace.
    public init() {}

    /// The namespace's identifier.
    public var wrappedValue: ID {
        box.id ?? ID(unbound: ObjectIdentifier(box))
    }

    public func bindRenderIdentity(path: String, propertyIndex: Int) {
        let id = ID(bound: "namespace::\(path)::\(propertyIndex)")
        if box.id != id { box.id = id }
    }

    /// The identifier of a namespace — what the focus-scope modifiers and
    /// ``ResetFocusAction`` take.
    public struct ID: Hashable, Sendable {
        private enum Storage: Hashable, Sendable {
            /// Derived from the holding view's render identity.
            case bound(String)
            /// Read before any render: unique to the property value, and
            /// never equal to a bound id.
            case unbound(ObjectIdentifier)
        }

        private let storage: Storage

        fileprivate init(bound key: String) {
            storage = .bound(key)
        }

        fileprivate init(unbound box: ObjectIdentifier) {
            storage = .unbound(box)
        }
    }

    /// The bound id, shared by every copy of the property.
    ///
    /// Unchecked because it is written only by the render walk and read by
    /// views and their event closures, all on the main actor — the same
    /// rationale as `AssignedFocusID`.
    private final class Box: @unchecked Sendable {
        var id: ID?
    }
}

/// Handled by the property walks directly (``RenderIdentityBindable``), so
/// they need not look inside it.
extension Namespace: FrameworkDynamicProperty {}
