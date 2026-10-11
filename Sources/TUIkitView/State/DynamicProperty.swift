//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicProperty.swift
//
//  SwiftUI's protocol for a stored property that the framework updates before a
//  view's body runs — what lets an app write its own property wrapper out of
//  `@State`, `@Environment` and friends.
//
//  Created by Wade Tregaskis
//  License: MIT

/// An interface for a stored variable that updates an external property of a
/// view.
///
/// Conform a property wrapper to it and the `@State`, `@Environment` and other
/// dynamic properties it holds behave as they would on the view itself: the
/// state is kept for the place the view is in the tree, and the environment is
/// the one in force there.
///
/// ```swift
/// @propertyWrapper
/// struct Shouting: DynamicProperty {
///     @Environment(\.locale) private var locale
///     let text: String
///
///     var wrappedValue: String { text.uppercased(with: locale) }
/// }
/// ```
///
/// ``update()`` is called before every evaluation of the view's `body`, after
/// the properties inside it have been given their values, and what it changes
/// in the property's own stored values is what `body` then reads, as in
/// SwiftUI: the property is written back into the view `body` is evaluated on.
/// A property in a class the view holds is not: only a struct's own fields
/// are written back.
public protocol DynamicProperty {
    /// Updates the underlying value of the stored value.
    ///
    /// Called before the view's `body` is evaluated. The default does nothing.
    mutating func update()
}

extension DynamicProperty {
    /// Does nothing: most dynamic properties have nothing to update.
    public mutating func update() {}
}

/// The dynamic properties TUIkit itself provides, which the property walks
/// handle directly and need not look inside.
package protocol FrameworkDynamicProperty: DynamicProperty {}

extension State: FrameworkDynamicProperty {}
extension Binding: FrameworkDynamicProperty {}
extension Environment: FrameworkDynamicProperty {}

/// What the property walks do with one stored value that is not itself bound
/// or resolved: descend into it if it holds properties of its own — an app's
/// ``DynamicProperty`` or a ``ViewModifier`` — and say whether it is one.
///
/// A ``FrameworkDynamicProperty`` that the walk did not otherwise handle is a
/// leaf, not a container: looking inside a `Binding` finds only its closures.
enum NestedProperties {
    /// The value, if the walk should descend into it.
    static func container(_ value: Any) -> Any? {
        if value is any FrameworkDynamicProperty { return nil }
        if value is any DynamicProperty || value is any ViewModifier { return value }
        return nil
    }

    /// Whether `value` is an app's ``DynamicProperty`` — one whose
    /// ``DynamicProperty/update()`` the framework runs.
    static func isAppProperty(_ value: Any) -> Bool {
        value is any DynamicProperty && !(value is any FrameworkDynamicProperty)
    }
}

// MARK: - Writing back what update() did

/// Runs ``DynamicProperty/update()`` on every app property `root` stores —
/// and on those they store, innermost first — and writes each back into
/// `root`, so `body` evaluated on `root` reads what `update()` left.
///
/// Called by the property walks on a copy of a view whose type holds such a
/// property (``bindStateProperties(of:identity:storage:)`` says so), after
/// its `@State` is bound and its `@Environment` resolved, and never for any
/// other: a view with none pays nothing.
///
/// The fields are found through ``RuntimeFields`` — the runtime's field
/// metadata, which gives each stored field's declared type and byte offset —
/// and each container is read and written in place at its offset, as its
/// declared type. `Mirror` reads fields but cannot write one, and the stdlib's
/// writable-key-path walk (`_forEachFieldWithKeyPath`) is SPI that Xcode's
/// SDKs do not ship (see `RuntimeFields.swift`). A struct's own fields only:
/// a class, or a field the runtime holds weakly, is left as it is.
///
/// `@usableFromInline` for ``updatedDynamicProperties(of:hasAppProperties:)``,
/// which is inlined into the modules above (CONTRIBUTING.md, "Crossing a
/// module boundary"); its own body is not inlinable.
@MainActor
@usableFromInline
package func updateDynamicProperties<Root>(of root: inout Root) {
    guard RuntimeFields.Kind(of: Root.self) == .struct else { return }
    let fields = RuntimeFields.fields(of: Root.self)
    guard !fields.isEmpty else { return }
    withUnsafeMutableBytes(of: &root) { bytes in
        guard let base = bytes.baseAddress else { return }
        for field in fields where field.isStrong {
            // `field.type` is an `Any.Type`, opened here to the field's own type.
            writeBackDynamicProperties(at: base + field.offset, as: field.type)
        }
    }
}

/// One field of ``updateDynamicProperties(of:)``, at `address` and of declared
/// type `Field`: if it is a container, its own properties updated and written
/// back into it, it updated if it is an app property, and the result stored.
@MainActor
private func writeBackDynamicProperties<Field>(at address: UnsafeMutableRawPointer, as _: Field.Type) {
    let slot = address.assumingMemoryBound(to: Field.self)
    guard NestedProperties.container(slot.pointee) != nil else { return }
    var field = slot.pointee
    updateDynamicProperties(of: &field)
    if var property = field as? any DynamicProperty, !(property is any FrameworkDynamicProperty) {
        property.update()
        guard let updated = property as? Field else { return }
        field = updated
    }
    slot.pointee = field
}

/// `view` with its app properties updated and written back, or `nil` when
/// `hasAppProperties` says it has none — which is the walk's answer, so a view
/// without them is neither copied nor reflected again.
///
/// `@inlinable` as well as always inlined: `@inline(__always)` alone reaches
/// only this module's callers, and the alignment-guide walk
/// (TUIkitFoundation) and the `App` root (TUIkitApp) call it from others, where
/// it would be an unspecialised call for every view, app property or not.
@MainActor
@inlinable
@inline(__always)
package func updatedDynamicProperties<V>(of view: V, hasAppProperties: Bool) -> V? {
    guard hasAppProperties else { return nil }
    var updated = view
    updateDynamicProperties(of: &updated)
    return updated
}
