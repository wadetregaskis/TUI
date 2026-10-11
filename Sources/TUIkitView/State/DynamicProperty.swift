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
/// A struct's own fields and an optional's wrapped value are written back.
/// In a view that is an enum, or a class the view holds, `update()` still
/// runs, on a copy, so what it changes is seen only through what the property
/// holds by reference.
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
/// SDKs do not ship (see `RuntimeFields.swift`). A struct's own fields, and an
/// `Optional`'s wrapped value, are written back. Anything else the binding
/// walk's `Mirror` looks into — an enum's payload (a view that is an enum),
/// a class's fields — has its properties updated on copies, which is what
/// TUIkit did for every property before write-back: `update()` runs, and
/// what it changes is seen only through what it holds by reference. An
/// enum's payload is not written in place because a multi-payload enum may
/// keep its case in the payload's spare bits, which a write would clear.
///
/// `@usableFromInline` for ``updatedDynamicProperties(of:hasAppProperties:)``,
/// which is inlined into the modules above (CONTRIBUTING.md, "Crossing a
/// module boundary"); its own body is not inlinable.
@MainActor
@usableFromInline
package func updateDynamicProperties<Root>(of root: inout Root) {
    switch RuntimeFields.Kind(of: Root.self) {
    case .struct:
        let fields = RuntimeFields.fields(of: Root.self)
        guard !fields.isEmpty else { return }
        withUnsafeMutableBytes(of: &root) { bytes in
            guard let base = bytes.baseAddress else { return }
            for field in fields where field.isStrong {
                // `field.type` is an `Any.Type`, opened here to the field's own type.
                writeBackDynamicProperties(at: base + field.offset, as: field.type)
            }
        }
    case .optional:
        // The binding walk's `Mirror` looks through an `Optional`, so this
        // does too: unwrapped, updated, and wrapped again.
        guard let optional = Root.self as? any OptionalPropertyHolder.Type else { return }
        withUnsafeMutablePointer(to: &root) { optional.updateWrapped(at: UnsafeMutableRawPointer($0)) }
    default:
        updateCopies(in: root)
    }
}

/// An `Optional` opened to its wrapped type, for ``updateDynamicProperties(of:)``.
private protocol OptionalPropertyHolder {
    @MainActor static func updateWrapped(at address: UnsafeMutableRawPointer)
}

extension Optional: OptionalPropertyHolder {
    /// Updates the value the optional at `address` wraps, if any, and writes
    /// it back.
    @MainActor static func updateWrapped(at address: UnsafeMutableRawPointer) {
        let slot = address.assumingMemoryBound(to: Self.self)
        guard var wrapped = slot.pointee else { return }
        updateDynamicProperties(of: &wrapped)
        slot.pointee = wrapped
    }
}

/// Runs ``DynamicProperty/update()`` on a copy of each app property `value`
/// holds where its fields cannot be written — innermost first, as the
/// write-back does — and keeps nothing.
@MainActor
private func updateCopies(in value: Any) {
    for child in Mirror(reflecting: value).children {
        guard let container = NestedProperties.container(child.value) else { continue }
        // An `Any` no constraint can open: `_openExistential` finds its type.
        _openExistential(container, do: updateCopy)
    }
}

/// One container of ``updateCopies(in:)``: its own properties updated (and
/// written back into the copy, where they can be), then its `update()`.
@MainActor
private func updateCopy<Value>(of value: Value) {
    var copy = value
    updateDynamicProperties(of: &copy)
    if var property = copy as? any DynamicProperty, !(property is any FrameworkDynamicProperty) {
        property.update()
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
