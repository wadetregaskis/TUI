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
/// prepared (``prepareProperties(of:plan:identity:storage:environment:isMeasuring:)``)
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
///
/// `isMeasuring` says whether the body is evaluated for a measure. Not
/// `context`'s: a measure asked for from a render — a `ViewThatFits` choosing
/// its candidate — evaluates a composite's body with the render's context.
@MainActor
@inline(never)
package func preparedBody<V: View>(
    of view: V, plan: SlotPlan, context: RenderContext, isMeasuring: Bool
) -> V.Body {
    // A view whose fields say by their values whether the walk acts on them,
    // all holding nothing: evaluated as it is, with no copy made.
    if let probes = plan.probes, !probesFindSomething(in: view, probes) {
        return view.body
    }
    var prepared = view
    prepareProperties(
        of: &prepared, plan: plan, identity: context.identity, storage: context.stateStorage,
        environment: context.environment, isMeasuring: isMeasuring)
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
/// `isMeasuring` says whether the body is evaluated for a measure, which
/// makes, moves and drops nothing a view's key holds for a class property's
/// object (``State/bindObjectState(at:to:key:in:isMeasuring:)``).
@MainActor
package func prepareProperties<V>(
    of value: inout V, plan: SlotPlan, identity: ViewIdentity, storage: StateStorage?,
    environment: EnvironmentValues, isMeasuring: Bool
) {
    var walk = PropertyWalk(identity: identity, storage: storage, environment: environment, isMeasuring: isMeasuring)
    // `&value` goes as a typed pointer argument, not through a closure passed
    // to `withUnsafeMutablePointer`: in a release build such a closure
    // carries a run-time check that it runs on the main actor, where a call
    // with a pointer argument carries none. Typed, because `&value` to a raw
    // pointer draws a warning for a type that may hold a reference.
    walk.applyRoot(plan, at: &value)
}

/// Whether the app properties' `update()` runs where the walk is.
enum UpdateMode {
    /// Not at all: inside a `weak` field, as SwiftUI updates none there.
    case none
    /// In place, so `body` reads what it changed.
    case inPlace
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
/// macOS 15, `Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`). The walk keeps, beside the
/// state, which case it last saw and the keys of the state it created while
/// that case held (``EnumCaseRecord``); when another case replaces it, all of
/// that is dropped.
///
/// **An object.** A class instance in a property field can be shared by many
/// views, and one object has one set of stored properties. What it holds is
/// the object's, and every view holding it walks it before its body, measures
/// included: its `@State` is bound to the object's own boxes, which no view's
/// key holds (``State/bindObjectState(at:to:key:in:isMeasuring:)``), its ids
/// are the object's (``ObjectHub/idPath``), its nested properties are updated
/// in place, and then its own `update()` runs, as SwiftUI runs it before each
/// holder's body (measured: `Tools/SwiftUIProbes/Class properties held by
/// several views/cls.out`). Two views showing one object read and write one
/// state, which no change of the views holding it moves or drops. Every view
/// drawn holding it is registered on the object's hub (``ObjectHub``,
/// ``HolderToken``), so a write redraws each of them, one served from the
/// memo included. An object made with each value of the view holding it, in
/// the pass that walks it (session notes `DYNV2/notes.md` §4.11), takes its
/// `@State` from its place instead, as a view value's does, so the object
/// the next value makes finds it: the walk tells the two apart by when the
/// `@State` was made (``StateBacking/createdIn``). Its `@Environment` is
/// resolved by every holder's walk to that holder's environment, and put back
/// after the holder's content, so a body and what it built read their own
/// view's; at rest — in a closure, between passes — the object reads its
/// primary's, the first holder drawn (``ObjectHub/primary``). A measure makes,
/// moves and drops nothing a view's key holds for it. SwiftUI installs
/// nothing inside a class (measured: DYNP `op.out` vii-f). Each object is
/// reached at most once per walk, so objects that reach each other end the
/// walk.
@MainActor
struct PropertyWalk {
    /// The identity every key shares.
    let identity: ViewIdentity
    let storage: StateStorage?
    let environment: EnvironmentValues
    /// Whether the body is evaluated for a measure.
    let isMeasuring: Bool

    /// The next of the view's own declaration-order indices.
    private var ownIndex = 0

    /// The keys of the state the walk created inside the enum cases it is in,
    /// in the order it did: each enum's record takes those created in its
    /// case, and the key of the record of an enum inside it when that record
    /// is made — not what that record lists.
    var created: [StateStorage.StateKey] = []

    /// How many enum cases the walk is inside. It notes the state it creates
    /// only inside one.
    var caseDepth = 0

    /// The objects the walk has reached: each is walked and updated once, so
    /// objects that reach each other are not walked round until the stack
    /// runs out.
    var objectsReached: [ObjectIdentifier] = []

    /// How many objects' storage the walk is inside, where what it walks
    /// can be reached, while it walks it, by anything holding the object.
    var objectDepth = 0

    /// The object whose contents the walk is in, the innermost: `nil`
    /// outside every object.
    var objectWalk: ObjectWalk?

    /// How many times the walk has changed a value where it lies — given a
    /// `@State` a backing, or an `@Environment` a box, of its own, or run an
    /// app property's `update()` in place — so a copy it walked is assigned
    /// back only when it differs.
    var changes = 0

    init(identity: ViewIdentity, storage: StateStorage?, environment: EnvironmentValues, isMeasuring: Bool) {
        self.identity = identity
        self.storage = storage
        self.environment = environment
        self.isMeasuring = isMeasuring
    }

    /// Walks the value at `root`, whose type's root plan is `plan`.
    mutating func applyRoot<Root>(_ plan: SlotPlan, at root: UnsafeMutablePointer<Root>) {
        let base = UnsafeMutableRawPointer(root)
        if let own = plan.ownEnvironment {
            own.resolveOwnEnvironment(at: base, environment)
        }
        switch plan.action {
        case .fields(let fields):
            applySteps(of: fields, at: base, scope: NestedScope.view, isOwn: true, updates: .inPlace)
        case .enumeration(let enumeration):
            applyCase(of: enumeration, at: base, scope: NestedScope.view, updates: .inPlace)
        case .object:
            // A view that is a class: its fields are its own.
            let object = base.assumingMemoryBound(to: AnyObject.self).pointee
            objectsReached.append(ObjectIdentifier(object))
            applyContents(
                of: object, PropertyPlans.contents(ofClass: type(of: object)), scope: NestedScope.view, isOwn: true,
                updates: .inPlace)
        default:
            break
        }
    }

    /// Walks each field `fields` plans, in the value at `base` — a struct, or
    /// an object's storage.
    mutating func applySteps(
        of fields: FieldsPlan, at base: UnsafeMutableRawPointer, scope: UInt64, isOwn: Bool, updates: UpdateMode
    ) {
        for step in fields.steps {
            // A modifier stored here, not applied, has nothing in it updated:
            // it is updated where it is applied, once (DYNV bug 5: a modifier
            // stored in a view and applied, or wrapped by `.transaction(_:)`,
            // ran its properties' `update()` twice). But for a modifier class,
            // a property class wherever it is held (B-DYNVFIX-4).
            let stepUpdates = step.slot.storedCopySkipsUpdates && !step.appliesModifier ? UpdateMode.none : updates
            if let reference = step.reference {
                let referenceUpdates = reference.isOptional ? .none : stepUpdates
                guard let objectPlan = reference.object else {
                    if case .dynamicClass(let plan) = step.slot.action {
                        applyHeldPlainObject(
                            plan, reference, at: base + step.offset, position: step.position, scope: scope,
                            updates: referenceUpdates)
                    }
                    continue
                }
                guard let loaded = reference.load(at: base + step.offset) else { continue }
                applyObject(objectPlan, loaded, position: step.position, scope: scope, updates: referenceUpdates)
            } else {
                apply(
                    step.slot, at: base + step.offset, position: step.position, scope: scope, isOwn: isOwn,
                    updates: stepUpdates)
            }
        }
    }

    /// Walks one stored value at `address`, whose declared type `slot` plans,
    /// at `position` in `scope`.
    mutating func apply(
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
            applySteps(of: fields, at: address, scope: inner, isOwn: false, updates: updates)
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
                existential, at: address, as: existential.type, position: position, scope: scope, isOwn: isOwn,
                updates: updates)
        case .object(let plan):
            let object = address.assumingMemoryBound(to: AnyObject.self).pointee
            applyObject(plan, object, position: position, scope: scope, updates: updates)
        case .dynamicClass(let plan):
            applyDynamicClass(plan, at: address, position: position, scope: scope, updates: updates)
        }
    }

    /// One of TUIkit's own properties at `address`.
    private mutating func applyLeaf(
        _ leaf: Leaf, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64, isOwn: Bool
    ) {
        if let object = objectWalk {
            applyObjectLeaf(leaf, at: address, position: position, scope: scope, in: object)
            return
        }
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
                if state.bindState(at: address, to: storage, key: key) { changes += 1 }
                if storage.count != stored { created.append(key) }
            } else if state.bindState(at: address, to: storage, key: key) {
                changes += 1
            }
        }
        if let bound = leaf.identity {
            let path = isOwn ? identity.path : NestedScope.identityPath(of: identity, in: scope)
            bound.bindRenderIdentity(at: address, path: path, propertyIndex: index)
        }
        if let placed = leaf.placeEnvironment {
            if placed.resolveEnvironment(at: address, environment, place: identity, storage: storage) {
                changes += 1
            }
        } else if let resolvable = leaf.environment {
            resolvable.resolveEnvironment(at: address, environment)
        }
    }

    /// An app property's own `update()`, after what it holds has been walked.
    private mutating func runUpdate(
        _ updater: (any DynamicProperty.Type)?, at address: UnsafeMutableRawPointer, updates: UpdateMode
    ) {
        guard let updater else { return }
        guard updates == .inPlace else { return }
        updater.updateInPlace(at: address)
        changes += 1
    }

    // MARK: Existentials

    /// The existential of declared type `Existential` at `address`, which
    /// `plan` plans: what it holds, walked by its dynamic type's plan on a copy
    /// that is then assigned back. Assigned, not written in place: a value too
    /// big for the existential's inline buffer lies in a box its copies share.
    /// The dynamic type is read where the value lies (``DynamicTypes``), and
    /// one found holding nothing is noted, so the next body that finds it
    /// there — and the probe before a view is copied — reads no further.
    private mutating func applyExistential<Existential>(
        _ plan: ExistentialPlan, at address: UnsafeMutableRawPointer, as _: Existential.Type, position: Int,
        scope: UInt64, isOwn: Bool, updates: UpdateMode
    ) {
        let field = address.assumingMemoryBound(to: Existential.self)
        let dynamicType: Any.Type
        switch DynamicTypes.existential(at: UnsafeRawPointer(address), plan.layout) {
        case .empty:
            return
        case .type(let type):
            dynamicType = type
        case .unknown:
            // `type(of:)` of the value as `Any` is its dynamic type, however
            // deeply existentials are nested — `Existential` is generic here,
            // so `as Any` wraps the existential itself rather than what it
            // holds.
            dynamicType = type(of: field.pointee as Any)
        }
        if plan.empty.contains(dynamicType) { return }
        let slot = PropertyPlans.exact(dynamicType)
        if slot.isNone {
            plan.empty.insert(dynamicType)
            return
        }
        // A modifier in an existential is stored, never the one applied: but
        // for a modifier class, a property class wherever it is held.
        applyOpened(
            field, as: dynamicType, slot: slot, position: position, scope: scope, isOwn: isOwn,
            updates: slot.storedCopySkipsUpdates ? .none : updates)
    }

    /// ``applyExistential(_:at:as:position:scope:isOwn:updates:)``, with what
    /// the existential at `field` holds cast out to `Value`, its own type: a
    /// cast between two generic types is made at run time, and unwraps the
    /// existential however deeply it is nested.
    private mutating func applyOpened<Existential, Value>(
        _ field: UnsafeMutablePointer<Existential>, as _: Value.Type, slot: SlotPlan, position: Int,
        scope: UInt64, isOwn: Bool, updates: UpdateMode
    ) {
        guard var copy = field.pointee as? Value else { return }
        let changesBefore = changes
        applyTyped(slot, at: &copy, position: position, scope: scope, isOwn: isOwn, updates: updates)
        // Assigned back only if the walk changed the copy: an `update()` run
        // in it, or a `@State` or `@Environment` at a second place given a
        // backing or box of its own, which must reach the field. Nothing
        // else: making the existential anew allocates a box for a value too
        // big for its buffer.
        guard changes != changesBefore, let updated = copy as? Existential else { return }
        field.pointee = updated
    }

    /// ``apply(_:at:position:scope:isOwn:updates:)`` on the value `pointer`
    /// points to, typed so that `&value` reaches it without a closure.
    mutating func applyTyped<Value>(
        _ slot: SlotPlan, at pointer: UnsafeMutablePointer<Value>, position: Int, scope: UInt64, isOwn: Bool,
        updates: UpdateMode
    ) {
        apply(
            slot, at: UnsafeMutableRawPointer(pointer), position: position, scope: scope, isOwn: isOwn,
            updates: updates)
    }
}
