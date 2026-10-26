//  🖥️ TUI — A Terminal UI framework for Swift
//  Namespace.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

// MARK: - Namespace

/// A dynamic property whose value names a namespace that belongs to the view
/// holding it. Mirrors SwiftUI's `@Namespace`.
///
/// ```swift
/// struct Settings: View {
///     @Namespace private var settings
///     @Environment(\.resetFocus) private var resetFocus
///
///     var body: some View {
///         VStack {
///             TextField("Name", text: $name)
///                 .prefersDefaultFocus(in: settings)
///             Button("Start over") { resetFocus(in: settings) }
///         }
///         .focusScope(settings)
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
/// It is what ``View/focusScope(_:)``, ``View/prefersDefaultFocus(_:in:)`` and
/// ``ResetFocusAction`` key a scope by.
///
/// Read before the view first renders — in an initializer, say — the value is
/// a placeholder unique to this property value, as SwiftUI's is outside a
/// body.
@propertyWrapper
public struct Namespace: DynamicProperty, RenderIdentityBindable, Sendable {
    /// Where the bound id lives: a reference, so the binding made at render
    /// reaches the copy of the property `body` reads.
    private let box: Box

    /// Creates a namespace.
    public init() {
        box = Box()
    }

    /// A namespace whose id lives in `box`: a copy given a box of its own at a
    /// second place (``PlaceBoundIdentity``).
    private init(box: Box) {
        self.box = box
    }

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
        /// Where it was last bound (``PlaceBoundIdentity``).
        var stamp = PlaceStamp<String>()
    }
}

/// Bound for each place a view value is drawn at: a copy at a second place in
/// one pass — `HStack { tally; tally }` — takes a box of its own, as SwiftUI
/// gives each place its own namespace (measured, `twoplaces.out`).
extension Namespace: PlaceBoundIdentity {
    package static func bindRenderIdentity(
        at address: UnsafeMutableRawPointer, path: String, propertyIndex: Int, pass: UInt32
    ) -> Bool {
        let namespace = address.assumingMemoryBound(to: Self.self)
        let id = ID(bound: "namespace::\(path)::\(propertyIndex)")
        let box = namespace.pointee.box
        if box.stamp.isSecondPlace(path, in: pass) {
            let own = Box()
            own.id = id
            own.stamp.stamp(path, in: pass)
            namespace.pointee = Namespace(box: own)
            return true
        }
        if box.id != id { box.id = id }
        box.stamp.stamp(path, in: pass)
        return false
    }
}

/// Handled by the property walks directly (``RenderIdentityBindable``), so
/// they need not look inside it.
extension Namespace: FrameworkDynamicProperty {}
