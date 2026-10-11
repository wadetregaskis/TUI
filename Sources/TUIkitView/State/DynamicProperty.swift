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
/// What it reads of an `@Observable` object is observed as `body`'s reads
/// are, so a change to it draws the view again, as SwiftUI does (measured on
/// macOS 15).
/// A struct's own fields and an optional's wrapped value are written back.
/// In a view that is an enum, or a class the view holds, `update()` still
/// runs, on a copy, so what it changes is seen only through what the property
/// holds by reference. A property held `unowned` is updated where it is (it
/// is a class), and one held `weak` is not updated, as in SwiftUI (both
/// measured on macOS 15).
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

/// A dynamic property TUIkit itself provides that holds properties the walks
/// must reach — `@GestureState` keeps its value in a `@State` — but whose
/// ``DynamicProperty/update()`` does nothing: descended into as an app's
/// property is, but not counted as one, so a view holding it is not copied
/// on every body to run that `update()`.
package protocol FrameworkPropertyContainer: DynamicProperty {}

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
        guard let property = value as? any DynamicProperty else { return false }
        return runsUpdate(property)
    }

    /// Whether the framework runs `property`'s ``DynamicProperty/update()``:
    /// an app's property, not one of TUIkit's own, whose `update()` does
    /// nothing.
    static func runsUpdate(_ property: any DynamicProperty) -> Bool {
        !(property is any FrameworkDynamicProperty) && !(property is any FrameworkPropertyContainer)
    }

    /// Whether a stored value of declared type `type` is an app's property
    /// (``isAppProperty(_:)``), from the type alone.
    static func isAppPropertyType(_ type: Any.Type) -> Bool {
        type is any DynamicProperty.Type && !(type is any FrameworkDynamicProperty.Type)
            && !(type is any FrameworkPropertyContainer.Type)
    }

    /// Whether the stored property `label` of `parent` is held `weak` — or
    /// `unowned` as an optional — so that its declared type is an optional,
    /// which the write-back passes over: the binding walk then does not count
    /// it as an app property to update. Asked only of a child that is an app
    /// property, so a view holding none pays nothing; read from the runtime's
    /// field metadata once per type. A class's fields are not listed, so a
    /// property in one is counted, as before.
    @MainActor
    static func isHeldWeakly(_ label: String?, in parent: Any) -> Bool {
        guard let label else { return false }
        let type = Swift.type(of: parent)
        let key = ObjectIdentifier(type)
        if let names = TypeFacts.weakFieldNames.pointee[key] { return names.contains(label) }
        // A loop, not `lazy.filter` and `map`: a closure handed to the
        // standard library from here is a main-actor closure, and a release
        // build checks at run time that each call of it is on the main actor.
        var names: Set<String> = []
        for field in RuntimeFields.fields(of: type) where !field.isStrong && field.kind == .optional {
            names.insert(field.name)
        }
        TypeFacts.weakFieldNames.pointee[key] = names
        return names.contains(label)
    }

    /// Whether a stored value of declared type `type` may be one that
    /// ``container(_:)`` descends into — decided from the type alone, so the
    /// write-back loads no field that cannot be one.
    ///
    /// Not every field may be loaded as its declared type: the runtime's
    /// layout of a type is not always the one stored. A metatype with one
    /// value (`Int.Type`) is stored in no bytes, and a tuple or optional
    /// holding one is packed to match, where the runtime reports a pointer's
    /// layout for them all (`ValueHashPlan.swift`, "A metatype"); a load of
    /// one reads the bytes beside it. A property's own type is laid out as
    /// stored, and so is an optional of one. An existential — a constrained
    /// one (`any P<Int>`) too — or a class reference is loaded as well (its
    /// layout is never packed), because only its value says whether it holds
    /// a property, as the binding walk's `Mirror` sees it.
    static func mayBeContainer(_ type: Any.Type) -> Bool {
        if isContainerType(type) { return true }
        switch RuntimeFields.Kind(of: type) {
        case .optional:
            guard let optional = type as? any OptionalPropertyHolder.Type else { return false }
            return mayBeContainer(optional.wrappedType)
        case .existential, .extendedExistential:
            return true
        case let kind:
            return kind.isClass
        }
    }

    /// Whether a value of declared type `type` is one that ``container(_:)``
    /// descends into, whatever its value: an app's property, one of TUIkit's
    /// that holds properties (``FrameworkPropertyContainer``), or a modifier.
    static func isContainerType(_ type: Any.Type) -> Bool {
        if type is any FrameworkDynamicProperty.Type { return false }
        return type is any DynamicProperty.Type || type is any ViewModifier.Type
    }

    /// Whether what a property walk finds in a value of `type` can differ
    /// from one value of the type to another, so that one holding nothing to
    /// bind, resolve or update says nothing of the next: an enum, whose
    /// `Mirror` children are its current case's payload; an optional of
    /// something a walk acts on (`nil` holds none); and a struct with a field
    /// that is either, or that is a property or modifier for which this is
    /// `true` — at any depth, because the walks descend into a property's and
    /// a modifier's own fields (a modifier holding an optional property makes
    /// its `ModifiedContent` count). A property or modifier field that is a
    /// class counts too: what the walk finds in it is what its instance holds
    /// at the time. The walks keep a type as holding nothing only where this
    /// is `false`.
    ///
    /// Decided from declared types, so an existential field, or a class
    /// field whose subclass is a property, is not counted: what one holds is
    /// known only from its value. Asked only of a type a walk found nothing
    /// in, and kept per type, the types inside it included.
    @MainActor
    static func walkDependsOnValue(_ type: Any.Type) -> Bool {
        let key = ObjectIdentifier(type)
        if let known = TypeFacts.valueDependence.pointee[key] { return known }
        let depends: Bool
        switch RuntimeFields.Kind(of: type) {
        case .enum:
            depends = true
        case .optional:
            depends = optionalHoldsProperty(type)
        case .struct:
            depends = !RuntimeFields.forEach(of: type) { _, _, fieldType, kind in
                !fieldDependsOnValue(fieldType, kind: kind)
            }
        default:
            depends = false
        }
        TypeFacts.valueDependence.pointee[key] = depends
        return depends
    }

    /// One struct field of ``walkDependsOnValue(_:)``, of declared type
    /// `type`: an optional of something a walk acts on, or a property or
    /// modifier the walks descend into whose own values can differ. Struct
    /// containment has no cycles, so the recursion ends; an enum or a class
    /// answers without looking inside.
    @MainActor
    private static func fieldDependsOnValue(_ type: Any.Type, kind: RuntimeFields.Kind) -> Bool {
        if kind == .optional { return optionalHoldsProperty(type) }
        guard isContainerType(type) else { return false }
        return kind.isClass || walkDependsOnValue(type)
    }

    /// Whether `type`, an optional, wraps — at whatever depth — something a
    /// walk binds, resolves or descends into when it is there: a `@State`, a
    /// property bound to its view's identity, an `@Environment`, or a
    /// container (an app's property, a modifier). Not a `Binding` or another
    /// of TUIkit's own properties the walks pass over, which many controls
    /// hold as optionals.
    private static func optionalHoldsProperty(_ type: Any.Type) -> Bool {
        var wrapped = type
        // A metatype cast does not look through an optional, as a value's
        // does: only an `Optional` type is an `OptionalPropertyHolder`.
        while let optional = wrapped as? any OptionalPropertyHolder.Type {
            wrapped = optional.wrappedType
        }
        if wrapped is any StateBindable.Type || wrapped is any RenderIdentityBindable.Type
            || wrapped is any EnvironmentResolvable.Type {
            return true
        }
        return isContainerType(wrapped)
    }
}

/// What the property walks learn of a type from its declaration, kept for the
/// life of the process, since a declaration never changes:
/// ``NestedProperties/walkDependsOnValue(_:)``'s answers, and the names of
/// each type's fields held `weak` (or `unowned` as an optional), for
/// ``NestedProperties/isHeldWeakly(_:in:)``.
///
/// Each table is reached through a pointer held as a constant — the reason
/// `ObservationLeases` and `VolatileReadTracker` keep their state that way: a
/// static variable is checked for exclusivity at run time on every read and
/// every write (`swift_beginAccess`, then `swift_endAccess`), where a load
/// through a constant pointer is a plain load. Never freed, as a static's
/// value is not.
@MainActor
private enum TypeFacts {
    static let valueDependence = permanentTable([ObjectIdentifier: Bool]())
    static let weakFieldNames = permanentTable([ObjectIdentifier: Set<String>]())
}

/// `table`, moved into memory that is never freed — one of ``TypeFacts``'.
private func permanentTable<Table>(_ table: Table) -> UnsafeMutablePointer<Table> {
    let pointer = UnsafeMutablePointer<Table>.allocate(capacity: 1)
    pointer.initialize(to: table)
    return pointer
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
/// A field held `unowned` whose type is an app property is updated through
/// its reference; one held `weak` is not, its type being an optional, which
/// SwiftUI does not update either (measured on macOS 15).
@MainActor
package func updateDynamicProperties<Root>(of root: inout Root) {
    // `&root` goes to each helper as a typed pointer argument, not through a
    // closure passed to `withUnsafeMutableBytes`/`withUnsafeMutablePointer`:
    // in a release build each of those two closures carried a run-time check
    // that it ran on the main actor (`swift_task_isCurrentExecutor`), where a
    // call with a pointer argument carries none. Typed, because `&root` to a
    // raw pointer draws a warning for a type that may hold a reference.
    switch RuntimeFields.Kind(of: Root.self) {
    case .struct:
        let fields = RuntimeFields.fields(of: Root.self)
        guard !fields.isEmpty else { return }
        writeBackDynamicProperties(in: fields, at: &root)
    case .optional:
        // The binding walk's `Mirror` looks through an `Optional`, so this
        // does too: unwrapped, updated, and wrapped again.
        guard let optional = Root.self as? any OptionalPropertyHolder.Type else { return }
        optional.updateWrapped(at: &root)
    default:
        updateCopies(in: root)
    }
}

/// An `Optional` opened to its wrapped type, for ``updateDynamicProperties(of:)``
/// and ``NestedProperties/mayBeContainer(_:)``.
private protocol OptionalPropertyHolder {
    /// The type the optional wraps.
    static var wrappedType: Any.Type { get }

    @MainActor static func updateWrapped<Address>(at address: UnsafeMutablePointer<Address>)
}

extension Optional: OptionalPropertyHolder {
    static var wrappedType: Any.Type { Wrapped.self }

    /// Updates the value the optional at `address` wraps, if any, and writes
    /// it back. `Address` is this optional's own type, which the caller could
    /// not name: it holds only the existential metatype.
    @MainActor static func updateWrapped<Address>(at address: UnsafeMutablePointer<Address>) {
        let slot = UnsafeMutableRawPointer(address).assumingMemoryBound(to: Self.self)
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
    if var property = copy as? any DynamicProperty, NestedProperties.runsUpdate(property) {
        property.update()
    }
}

/// The struct fields of ``updateDynamicProperties(of:)``, in the struct at
/// `root`, each written back where it lies. Only a field whose type may hold a
/// property is loaded (``NestedProperties/mayBeContainer(_:)``): any other
/// may be stored at a layout other than the one its type reports.
@MainActor
private func writeBackDynamicProperties<Root>(in fields: [RuntimeFields.Field], at root: UnsafeMutablePointer<Root>) {
    let base = UnsafeMutableRawPointer(root)
    for field in fields {
        if field.isStrong {
            guard NestedProperties.mayBeContainer(field.type) else { continue }
            // `field.type` is an `Any.Type`, opened here to the field's own type.
            writeBackDynamicProperties(at: base + field.offset, as: field.type)
        } else if NestedProperties.isAppPropertyType(field.type) {
            updateReferent(of: field, in: root.pointee)
        }
    }
}

/// An `unowned` field of `root` whose type is an app property: a class, so
/// `update()` changes it where `body` reads it, and nothing is written back.
/// SwiftUI updates one; a `weak` one's type is an optional, not the
/// property's, and SwiftUI leaves it, as the caller does (measured on macOS
/// 15). Loaded through `Mirror`, which knows how the runtime keeps the
/// reference; a load as the declared type does not.
///
/// Found among `Mirror`'s children by its name and type, not its position: a
/// view with a `customMirror` (`CustomReflectable`) has `Mirror` list the
/// children it chooses, in its own order, where the field's index can name
/// another property — updated a second time, on a copy — or none. One a
/// custom mirror leaves out is not updated; the property walks, which find a
/// view's properties through the same `Mirror`, do not see it either.
@MainActor
private func updateReferent(of field: RuntimeFields.Field, in root: Any) {
    let name = field.name
    // A loop, not `first(where:)`, for `NestedProperties.isHeldWeakly`'s
    // reason: a closure would carry a run-time main-actor check.
    for child in Mirror(reflecting: root).children where child.label == name {
        if isValue(child.value, of: field.type) {
            _openExistential(child.value, do: updateCopy)
        }
        return
    }
}

/// Whether `value` is a `T` — for ``updateReferent(of:in:)``, a field's
/// declared type, opened by the call.
private func isValue<T>(_ value: Any, of _: T.Type) -> Bool {
    value is T
}

/// One field of ``updateDynamicProperties(of:)``, at `address` and of declared
/// type `Field`, a type that may hold a property: if it is a container, its
/// own properties updated and written back into it, it updated if it is an
/// app property, and the result stored.
@MainActor
private func writeBackDynamicProperties<Field>(at address: UnsafeMutableRawPointer, as _: Field.Type) {
    let slot = address.assumingMemoryBound(to: Field.self)
    guard NestedProperties.container(slot.pointee) != nil else { return }
    var field = slot.pointee
    updateDynamicProperties(of: &field)
    if var property = field as? any DynamicProperty, NestedProperties.runsUpdate(property) {
        property.update()
        guard let updated = property as? Field else { return }
        field = updated
    }
    slot.pointee = field
}

/// `view`'s `body`, evaluated on a copy of `view` whose app properties have
/// run `update()` and been written back (``updateDynamicProperties(of:)``).
///
/// The property walks call it only for a view that
/// ``bindStateProperties(of:identity:storage:)`` said holds an app property,
/// as `hasAppProperties ? updatedBody(of: view) : view.body`, and never
/// inline it, so the copy is made here and nowhere else. Held by the caller
/// instead — the copy, or an optional of it — it was paid for by every
/// composite view, holding a property or not: the caller is an unspecialised
/// generic, so it allocated a stack slot of the view's run-time size, behind
/// a stack-protector check, on every call, the branch that used it taken or
/// not, and a measure fetched the metadata of `Optional` of the view and of
/// its body as well (release Stress, Xcode 6.2.4: `measureCompositeBody`
/// gained two `Optional` metadata fetches and four `___chkstk_darwin` probes
/// per call, `evaluateCompositeBody`'s body closure two probes).
@MainActor
@inline(never)
package func updatedBody<V: View>(of view: V) -> V.Body {
    var updated = view
    updateDynamicProperties(of: &updated)
    return updated.body
}
