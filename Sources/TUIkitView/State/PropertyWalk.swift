//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyWalk.swift
//
//  The property walk: before each body, the value's `@State` bound, its
//  `@Environment` resolved, its `@FocusState` and `@Namespace` given their ids,
//  and its app properties' `update()` run and written back — everywhere its
//  type's plan (`PropertyPlans`) says one may be.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The plan for `V`'s values when a body is evaluated on one, or `nil` when
/// no value of `V` holds anything the property walk acts on — nearly every
/// view, which then pays this one lookup, and `body` is evaluated on the
/// value as it is.
@MainActor
@inline(__always)
package func propertyPlan<V>(for _: V.Type) -> SlotPlan? {
    PropertyPlans.root(V.self)
}

/// `view`'s `body`, evaluated on a copy of `view` that the property walk has
/// prepared (``prepareProperties(of:plan:identity:storage:environment:)``)
/// with `plan`, its type's (``propertyPlan(for:)``).
///
/// Never inlined, so the copy is made here and nowhere else. Held by the
/// caller instead — the copy, or an optional of it — it was paid for by every
/// composite view, holding a property or not: the caller is an unspecialised
/// generic, so it allocated a stack slot of the view's run-time size, behind
/// a stack-protector check, on every call, the branch that used it taken or
/// not, and a measure fetched the metadata of `Optional` of the view and of
/// its body as well (release Stress, Xcode 6.2.4: `measureCompositeBody`
/// gained two `Optional` metadata fetches and four `___chkstk_darwin` probes
/// per call, `evaluateCompositeBody`'s body closure two probes).
@MainActor
@inline(never)
package func preparedBody<V: View>(of view: V, plan: SlotPlan, context: RenderContext) -> V.Body {
    var prepared = view
    prepareProperties(
        of: &prepared, plan: plan, identity: context.identity, storage: context.stateStorage,
        environment: context.environment)
    return prepared.body
}

/// Prepares `value` for its `body`: binds every `@State` to the storage kept
/// for `identity` (and `@FocusState` and `@Namespace` to ids from it), hands
/// every `@Environment` `environment`, and runs each app property's
/// ``DynamicProperty/update()``, innermost first, writing back what it
/// changed — wherever `plan` (``propertyPlan(for:)``) says one may be.
///
/// `value` is not constrained to `View`: the render loop prepares an `App`
/// with it too, at the root identity, before evaluating `App.body`. Without
/// `storage` (a guide asked for outside a render), no `@State` is bound.
@MainActor
package func prepareProperties<V>(
    of value: inout V, plan: SlotPlan, identity: ViewIdentity, storage: StateStorage?,
    environment: EnvironmentValues
) {
    var walk = PropertyWalk(identity: identity, storage: storage, environment: environment)
    // `&value` goes as a typed pointer argument, not through a closure passed
    // to `withUnsafeMutablePointer`: in a release build such a closure
    // carries a run-time check that it runs on the main actor, where a call
    // with a pointer argument carries none. Typed, because `&value` to a raw
    // pointer draws a warning for a type that may hold a reference.
    walk.applyRoot(plan, at: &value)
}

/// How the app properties' `update()` runs where the walk is.
enum UpdateMode {
    /// Not at all: inside a `weak` field, as SwiftUI updates none there.
    case none
    /// In place, so `body` reads what it changed.
    case inPlace
    /// On a copy, keeping nothing: inside a class instance.
    case onCopies
}

/// One walk of a value's properties, by its type's plan (``SlotPlan``).
///
/// **Keys.** A view's own `@State`, `@FocusState` and `@Namespace` are keyed
/// by counting them in declaration order, at the view's identity. One the view
/// holds inside something else is keyed by its position there, in a scope
/// derived from the path down to it (``NestedScope``).
///
/// **An enum's case.** A value that is an enum — a view that is one, or a
/// property or modifier — holds what its current case's payload holds. When
/// the case changes, the new case's `@State` starts at its defaults, and so
/// does the old case's when it comes back, as SwiftUI's does (measured on
/// macOS 15, session notes `SKEY/probe/skey.out`). The walk keeps, beside the
/// state, which case it last saw and the keys of the state it created while
/// that case held (``EnumCaseRecord``); when another case replaces it, all of
/// that is dropped.
@MainActor
struct PropertyWalk {
    /// The identity every key shares.
    let identity: ViewIdentity
    let storage: StateStorage?
    let environment: EnvironmentValues

    /// The next of the view's own declaration-order indices.
    private var ownIndex = 0

    /// The keys of the state the walk created inside the enum cases it is in,
    /// in the order it did: each enum's record takes those created in its
    /// case, and the key of the record of an enum inside it when that record
    /// is made — not what that record lists.
    private var created: [StateStorage.StateKey] = []

    /// How many enum cases the walk is inside. It notes the state it creates
    /// only inside one.
    private var caseDepth = 0

    /// The objects whose contents the walk is inside: objects that reach each
    /// other are not walked round until the stack runs out.
    private var objectsEntered: [ObjectIdentifier] = []

    init(identity: ViewIdentity, storage: StateStorage?, environment: EnvironmentValues) {
        self.identity = identity
        self.storage = storage
        self.environment = environment
    }

    /// Walks the value at `root`, whose type's root plan is `plan`.
    mutating func applyRoot<Root>(_ plan: SlotPlan, at root: UnsafeMutablePointer<Root>) {
        let base = UnsafeMutableRawPointer(root)
        if let own = plan.ownEnvironment {
            own.resolveOwnEnvironment(at: base, environment)
        }
        switch plan.action {
        case .fields(let fields):
            applySteps(of: fields, at: base, in: nil, scope: NestedScope.view, isOwn: true, updates: .inPlace)
        case .enumeration(let enumeration):
            applyCase(of: enumeration, at: base, scope: NestedScope.view, updates: .inPlace)
        case .object:
            // A view that is a class: its fields are its own.
            let object = base.assumingMemoryBound(to: AnyObject.self).pointee
            applyContents(of: object, scope: NestedScope.view, isOwn: true, updates: .onCopies)
        default:
            break
        }
    }

    /// Walks each field `fields` plans, in the value at `base` — or, when
    /// `object` is given, in that object, whose storage `base` is.
    private mutating func applySteps(
        of fields: FieldsPlan, at base: UnsafeMutableRawPointer, in object: AnyObject?, scope: UInt64,
        isOwn: Bool, updates: UpdateMode
    ) {
        for step in fields.steps {
            if let reference = step.reference {
                let loaded =
                    if let object {
                        PropertyPlans.loadReference(reference, in: object)
                    } else {
                        PropertyPlans.loadReference(reference, at: base)
                    }
                guard let loaded else { continue }
                applyObject(
                    reference.object, loaded, position: step.position, scope: scope,
                    updates: reference.isOptional ? .none : updates)
            } else {
                apply(
                    step.slot, at: base + step.offset, position: step.position, scope: scope, isOwn: isOwn,
                    updates: updates)
            }
        }
    }

    /// Walks one stored value at `address`, whose declared type `slot` plans,
    /// at `position` in `scope`.
    private mutating func apply(
        _ slot: SlotPlan, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64, isOwn: Bool,
        updates: UpdateMode
    ) {
        switch slot.action {
        case .none:
            return
        case .leaf(let leaf):
            applyLeaf(leaf, at: address, position: position, scope: scope, isOwn: isOwn)
        case .fields(let fields):
            let inner = NestedScope.container(at: position, ofType: fields.type, in: scope)
            applySteps(of: fields, at: address, in: nil, scope: inner, isOwn: false, updates: updates)
            runUpdate(fields.updater, at: address, updates: updates)
        case .enumeration(let enumeration):
            let inner = NestedScope.container(at: position, ofType: enumeration.type, in: scope)
            applyCase(of: enumeration, at: address, scope: inner, updates: updates)
            runUpdate(enumeration.updater, at: address, updates: updates)
        case .optional(let optional):
            guard optional.type.hasValue(at: address) else { return }
            // The payload lies at the optional's own address.
            apply(optional.wrapped, at: address, position: position, scope: scope, isOwn: isOwn, updates: updates)
        case .existential(let existential):
            applyExistential(
                at: address, as: existential.type, position: position, scope: scope, isOwn: isOwn,
                updates: updates)
        case .object(let plan):
            let object = address.assumingMemoryBound(to: AnyObject.self).pointee
            applyObject(plan, object, position: position, scope: scope, updates: updates)
        }
    }

    /// One of TUIkit's own properties at `address`.
    private mutating func applyLeaf(
        _ leaf: Leaf, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64, isOwn: Bool
    ) {
        var index = position
        if isOwn, leaf.isIndexed {
            // `@State`, `@FocusState` and `@Namespace` share the one counter,
            // so mixing them keeps stable keys whatever their order.
            index = ownIndex
            ownIndex += 1
        }
        if let state = leaf.state, let storage {
            let key =
                isOwn
                ? StateStorage.StateKey(identity: identity, propertyIndex: index)
                : StateStorage.StateKey(identity: identity, propertyIndex: index, scope: scope)
            if caseDepth > 0 {
                // Binding finds the box under `key` or creates it, and the
                // count of what is stored grows only when it creates one.
                let stored = storage.count
                state.bindState(at: address, to: storage, key: key)
                if storage.count != stored { created.append(key) }
            } else {
                state.bindState(at: address, to: storage, key: key)
            }
        }
        if let bound = leaf.identity {
            let path = isOwn ? identity.path : NestedScope.identityPath(of: identity, in: scope)
            bound.bindRenderIdentity(at: address, path: path, propertyIndex: index)
        }
        if let resolvable = leaf.environment {
            resolvable.resolveEnvironment(at: address, environment)
        }
    }

    /// An app property's own `update()`, after what it holds has been walked.
    private func runUpdate(
        _ updater: (any DynamicProperty.Type)?, at address: UnsafeMutableRawPointer, updates: UpdateMode
    ) {
        guard let updater else { return }
        switch updates {
        case .none: return
        case .inPlace: updater.updateInPlace(at: address)
        case .onCopies: updater.updateCopy(at: address)
        }
    }

    // MARK: Existentials

    /// The existential of declared type `Existential` at `address`: what it
    /// holds, walked by its dynamic type's plan on a copy that is then
    /// assigned back. Assigned, not written in place: a value too big for the
    /// existential's inline buffer lies in a box its copies share.
    private mutating func applyExistential<Existential>(
        at address: UnsafeMutableRawPointer, as _: Existential.Type, position: Int, scope: UInt64, isOwn: Bool,
        updates: UpdateMode
    ) {
        let field = address.assumingMemoryBound(to: Existential.self)
        // `type(of:)` of the value as `Any` is its dynamic type, however
        // deeply existentials are nested — `Existential` is generic here, so
        // `as Any` wraps the existential itself rather than what it holds.
        let dynamicType = type(of: field.pointee as Any)
        let slot = PropertyPlans.slot(dynamicType)
        if slot.isNone { return }
        applyOpened(
            field, as: dynamicType, slot: slot, position: position, scope: scope, isOwn: isOwn, updates: updates)
    }

    /// ``applyExistential(at:as:position:scope:isOwn:updates:)``, with what
    /// the existential at `field` holds cast out to `Value`, its own type: a
    /// cast between two generic types is made at run time, and unwraps the
    /// existential however deeply it is nested.
    private mutating func applyOpened<Existential, Value>(
        _ field: UnsafeMutablePointer<Existential>, as _: Value.Type, slot: SlotPlan, position: Int,
        scope: UInt64, isOwn: Bool, updates: UpdateMode
    ) {
        guard var copy = field.pointee as? Value else { return }
        applyTyped(slot, at: &copy, position: position, scope: scope, isOwn: isOwn, updates: updates)
        guard updates == .inPlace, let updated = copy as? Existential else { return }
        field.pointee = updated
    }

    /// ``apply(_:at:position:scope:isOwn:updates:)`` on the value `pointer`
    /// points to, typed so that `&value` reaches it without a closure.
    private mutating func applyTyped<Value>(
        _ slot: SlotPlan, at pointer: UnsafeMutablePointer<Value>, position: Int, scope: UInt64, isOwn: Bool,
        updates: UpdateMode
    ) {
        apply(
            slot, at: UnsafeMutableRawPointer(pointer), position: position, scope: scope, isOwn: isOwn,
            updates: updates)
    }

    // MARK: Objects

    /// A class instance in a field whose declared type `plan` names: what it
    /// holds, walked in place, and then its own `update()`.
    private mutating func applyObject(
        _ plan: ObjectPlan, _ object: AnyObject, position: Int, scope: UInt64, updates: UpdateMode
    ) {
        let id = ObjectIdentifier(object)
        // An object the walk is already inside is one reached again through
        // another: walked and updated where it was first reached.
        guard !objectsEntered.contains(id) else { return }
        let inner = NestedScope.container(at: position, ofType: type(of: object), in: scope)
        applyContents(of: object, scope: inner, isOwn: false, updates: updates == .none ? .none : .onCopies)
        if updates != .none, let updater = plan.updater {
            updater.updateObject(object)
        }
    }

    /// What `object` holds, walked in place: its storage is shared by every
    /// holder, so it is written where it lies.
    private mutating func applyContents(of object: AnyObject, scope: UInt64, isOwn: Bool, updates: UpdateMode) {
        let contents = PropertyPlans.contents(ofClass: type(of: object))
        guard !contents.steps.isEmpty else { return }
        objectsEntered.append(ObjectIdentifier(object))
        withExtendedLifetime(object) {
            let base = Unmanaged.passUnretained(object).toOpaque()
            applySteps(of: contents, at: base, in: object, scope: scope, isOwn: isOwn, updates: updates)
        }
        objectsEntered.removeLast()
    }

    // MARK: Enums

    /// What the enum at `address` holds: its case's payload, in a scope of
    /// that case's. When the case is not the one last recorded at `scope`,
    /// the state created while that one held is dropped first, so the new
    /// case's `@State` starts at its defaults, and nothing of the old case is
    /// left for it to find when it comes back.
    private mutating func applyCase(
        of plan: EnumPlan, at address: UnsafeMutableRawPointer, scope: UInt64, updates: UpdateMode
    ) {
        let (label, payload) = EnumCases.current(at: address, as: plan.type)
        let recordKey = StateStorage.StateKey(
            identity: identity, propertyIndex: StateStorage.StateKey.enumCaseIndex, scope: scope)
        let record = storage?.enumCaseRecord(at: recordKey)
        if let record, record.label != label {
            storage?.removeValues(forKeys: record.keys)
            record.keys.removeAll()
            record.label = label
        }
        guard let payload else { return }
        let caseScope = NestedScope.enumCase(label, in: scope)
        let createdBefore = created.count
        caseDepth += 1
        applyPayload(payload, scope: caseScope, updates: updates)
        caseDepth -= 1
        // An enum whose cases have created no state keeps no record.
        guard created.count > createdBefore, let storage else { return }
        if let record {
            record.keys.append(contentsOf: created[createdBefore...])
        } else {
            storage.setEnumCaseRecord(
                EnumCaseRecord(label: label, keys: Array(created[createdBefore...])), at: recordKey)
        }
        // What this case created is this record's alone. An enclosing case's
        // record lists this record instead — once, when it is made — and
        // drops what it lists with it (``StateStorage/removeValues(forKeys:)``).
        created.removeSubrange(createdBefore...)
        if record == nil, caseDepth > 0 { created.append(recordKey) }
    }

    /// A case's payload, a copy the runtime made: what it holds walked on
    /// that copy, so `update()` changes nothing `body` reads.
    private mutating func applyPayload(_ payload: Any, scope: UInt64, updates: UpdateMode) {
        func opened<Payload>(_ payload: Payload) {
            applyPayloadOpened(payload, scope: scope, updates: updates)
        }
        _openExistential(payload, do: opened)
    }

    private mutating func applyPayloadOpened<Payload>(_ payload: Payload, scope: UInt64, updates: UpdateMode) {
        var copy = payload
        if RuntimeFields.Kind(of: Payload.self) == .tuple {
            // A case holding more than one value: each walked by its
            // position, as SwiftUI takes each case's payload as a tuple and
            // keeps the elements that are properties.
            let fields = PropertyPlans.payloadPlan(of: Payload.self)
            applyTypedSteps(of: fields, at: &copy, scope: scope, updates: updates)
        } else {
            applyTyped(PropertyPlans.slot(Payload.self), at: &copy, position: 0, scope: scope, isOwn: false, updates: updates)
        }
    }

    private mutating func applyTypedSteps<Value>(
        of fields: FieldsPlan, at pointer: UnsafeMutablePointer<Value>, scope: UInt64, updates: UpdateMode
    ) {
        applySteps(of: fields, at: UnsafeMutableRawPointer(pointer), in: nil, scope: scope, isOwn: false, updates: updates)
    }
}

/// An enum's current case, as the runtime's reflection reads it: never
/// through a `customMirror`.
enum EnumCases {
    /// The name of the case of the enum at `address` — `""` for a case with
    /// no payload — and a copy of its payload.
    static func current<Enum>(at address: UnsafeMutableRawPointer, as _: Enum.Type) -> (label: String, payload: Any?) {
        let value = address.assumingMemoryBound(to: Enum.self).pointee
        guard RuntimeChildren.count(of: value, as: Enum.self) > 0 else { return ("", nil) }
        let child = RuntimeChildren.child(of: value, as: Enum.self, at: 0)
        return (child.name ?? "", child.value)
    }
}

// MARK: - Reaching each kind of property through its type

extension StateBindable {
    /// ``StateBindable/bindState(to:key:)`` on the `@State` at `address`.
    static func bindState(at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey) {
        address.assumingMemoryBound(to: Self.self).pointee.bindState(to: storage, key: key)
    }
}

extension RenderIdentityBindable {
    /// ``RenderIdentityBindable/bindRenderIdentity(path:propertyIndex:)`` on
    /// the property at `address`.
    static func bindRenderIdentity(at address: UnsafeMutableRawPointer, path: String, propertyIndex: Int) {
        address.assumingMemoryBound(to: Self.self).pointee.bindRenderIdentity(path: path, propertyIndex: propertyIndex)
    }
}

extension EnvironmentResolvable {
    /// ``EnvironmentResolvable/resolveEnvironment(_:)`` on the property at
    /// `address`.
    static func resolveEnvironment(at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues) {
        address.assumingMemoryBound(to: Self.self).pointee.resolveEnvironment(environment)
    }
}

extension ResolvesOwnEnvironment {
    /// ``ResolvesOwnEnvironment/resolveOwnEnvironment(_:)`` on the view at
    /// `address` — and, the first time its type is drawn in a debug build, a
    /// check that it resolved every `@Environment` of its own.
    static func resolveOwnEnvironment(at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues) {
        address.assumingMemoryBound(to: Self.self).pointee.resolveOwnEnvironment(environment)
        #if DEBUG
            OwnResolutionCheck.verify(Self.self, at: address)
        #endif
    }
}

#if DEBUG
    /// The ``ResolvesOwnEnvironment`` types whose own resolution a debug build
    /// has checked.
    @MainActor
    private enum OwnResolutionCheck {
        static var verified: Set<ObjectIdentifier> = []

        /// Checks, once per type, that the view at `address` of `type` had
        /// every `@Environment` of its own resolved.
        static func verify(_ type: Any.Type, at address: UnsafeMutableRawPointer) {
            guard verified.insert(ObjectIdentifier(type)).inserted else { return }
            for field in RuntimeFields.fields(of: type) {
                guard let inspectable = field.type as? any ResolutionInspectable.Type else { continue }
                assert(
                    inspectable.isResolved(at: address + field.offset),
                    "\(type).resolveOwnEnvironment(_:) does not resolve \(field.name)")
            }
        }
    }

    extension ResolutionInspectable {
        static func isResolved(at address: UnsafeMutableRawPointer) -> Bool {
            address.assumingMemoryBound(to: Self.self).pointee.isResolved
        }
    }
#endif

extension DynamicProperty {
    /// ``DynamicProperty/update()`` on the property at `address`, where it
    /// lies.
    static func updateInPlace(at address: UnsafeMutableRawPointer) {
        address.assumingMemoryBound(to: Self.self).pointee.update()
    }

    /// ``DynamicProperty/update()`` on a copy of the property at `address`,
    /// which is then dropped.
    static func updateCopy(at address: UnsafeMutableRawPointer) {
        var copy = address.assumingMemoryBound(to: Self.self).pointee
        copy.update()
    }

    /// ``DynamicProperty/update()`` on `object`, an instance of this type, a
    /// class.
    static func updateObject(_ object: AnyObject) {
        guard var property = object as? Self else { return }
        property.update()
    }
}
