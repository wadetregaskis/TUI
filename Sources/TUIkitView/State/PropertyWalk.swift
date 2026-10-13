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
/// `isMeasuring` says whether the body is evaluated for a measure, whose
/// claim on a class property's contents is only provisional
/// (``StateStorage/claimObjectContents(_:for:isMeasuring:)``).
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
/// macOS 15, session notes `SKEY/probe/skey.out`). The walk keeps, beside the
/// state, which case it last saw and the keys of the state it created while
/// that case held (``EnumCaseRecord``); when another case replaces it, all of
/// that is dropped.
///
/// **An object.** A class instance in a property field can be shared by many
/// views, and one object has one set of stored properties. So what it holds —
/// its `@State`, `@Environment`, ids, nested properties and their `update()`
/// — belongs to one view, its claimant: in each render pass, the first view
/// drawn whose walk reaches it
/// (``StateStorage/claimObjectContents(_:for:isMeasuring:)``). Its `@State`
/// boxes are the object's, kept under the claimant's key whichever view
/// that is (``StatePlace/object(revivesDropped:)``), its `@Environment` is
/// the claimant's, and every other holder leaves it as the claimant left it.
/// Two views showing one object therefore read and write one state, as one
/// object implies, and the state goes with the object when another view
/// shows it; an object made anew with each view value, held by that view
/// alone, keeps its state from frame to frame. The object's own `update()`
/// still runs before the body of every view that holds it (SwiftUI runs it,
/// and installs nothing inside it: measured, DYNP `op.out` vii-f). Each
/// object is reached at most once per walk, so objects that reach each other
/// end the walk.
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
    private var objectsReached: [ObjectIdentifier] = []

    /// How many objects' storage the walk is inside, where what it walks
    /// can be reached, while it walks it, by anything holding the object.
    var objectDepth = 0

    /// Inside the contents of an object this walk's view claims, the
    /// ``caseDepth`` at which they were entered: a `@State` there is the
    /// object's (``StatePlace/object(revivesDropped:)``), and one deeper, in
    /// an enum's case inside the object, starts again at its default when the
    /// case comes back. `nil` outside one.
    private var objectCaseDepth: Int?

    /// How many times the walk has changed a value where it lies — given a
    /// `@State` a backing, or an `@Environment` a box, of its own, or run an
    /// app property's `update()` in place — so a copy it walked is assigned
    /// back only when it differs.
    private var changes = 0

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
            applyContents(of: object, scope: NestedScope.view, isOwn: true, updates: .inPlace)
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
            // ran its properties' `update()` twice).
            let stepUpdates = step.slot.isModifier && !step.appliesModifier ? UpdateMode.none : updates
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
            let place = objectCaseDepth.map { StatePlace.object(revivesDropped: caseDepth == $0) } ?? .value
            if caseDepth > 0 {
                // Binding finds the box under `key` or creates it, and the
                // count of what is stored grows only when it creates one, or
                // keeps an object's box there that was not.
                let stored = storage.count
                if state.bindState(at: address, to: storage, key: key, place: place) { changes += 1 }
                if storage.count != stored { created.append(key) }
            } else if state.bindState(at: address, to: storage, key: key, place: place) {
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
        // A modifier in an existential is stored, never the one applied.
        applyOpened(
            field, as: dynamicType, slot: slot, position: position, scope: scope, isOwn: isOwn,
            updates: slot.isModifier ? .none : updates)
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

    // MARK: Objects

    /// The object in a field declared as a plain class, which `plan` plans:
    /// walked as a class property if its class is one — a subclass of the
    /// declared class — and nothing otherwise. A class found not to be one
    /// is noted, so the next body that finds it there reads no further.
    private mutating func applyDynamicClass(
        _ plan: DynamicClassPlan, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64,
        updates: UpdateMode
    ) {
        guard case .type(let objectType) = DynamicTypes.object(at: UnsafeRawPointer(address)),
            let found = propertyClassPlan(objectType, in: plan)
        else { return }
        let object = address.assumingMemoryBound(to: AnyObject.self).pointee
        // A modifier class in a field is stored, never the one applied.
        applyObject(found.plan, object, position: position, scope: scope, updates: found.isModifier ? .none : updates)
    }

    /// The object in the field at `address`, declared as a plain class or a
    /// class-bound existential and held `weak` or `unowned`, which `plan`
    /// plans and `reference` says how to load: walked as a class property if
    /// its class is one, and nothing otherwise. An `unowned` one's class is
    /// read where the reference lies first, so an object of a class that is
    /// not a property is never loaded, which traps if it has gone (DYNV bug
    /// 9); a `weak` one is loaded, `nil` once it has gone.
    private mutating func applyHeldPlainObject(
        _ plan: DynamicClassPlan, _ reference: ReferenceField, at address: UnsafeMutableRawPointer, position: Int,
        scope: UInt64, updates: UpdateMode
    ) {
        let loaded: AnyObject
        let found: (plan: ObjectPlan, isModifier: Bool)
        if reference.readsClassInPlace {
            guard case .type(let objectType) = DynamicTypes.unownedObject(at: UnsafeRawPointer(address)),
                let classPlan = propertyClassPlan(objectType, in: plan),
                let held = reference.load(at: address)
            else { return }
            (loaded, found) = (held, classPlan)
        } else {
            guard let held = reference.load(at: address),
                let classPlan = propertyClassPlan(type(of: held), in: plan)
            else { return }
            (loaded, found) = (held, classPlan)
        }
        // A modifier class in a field is stored, never the one applied.
        applyObject(found.plan, loaded, position: position, scope: scope, updates: found.isModifier ? .none : updates)
    }

    /// The plan of `type`, the class of an object found in a field `plan`
    /// plans, if it is a property or modifier class — never the declared
    /// class, nor one noted as holding nothing, which a class found not to be
    /// one then is — and whether it is a modifier.
    private func propertyClassPlan(_ type: Any.Type, in plan: DynamicClassPlan) -> (plan: ObjectPlan, isModifier: Bool)? {
        if ObjectIdentifier(type) == ObjectIdentifier(plan.type) || plan.empty.contains(type) { return nil }
        let exact = PropertyPlans.exact(type)
        guard case .object(let objectPlan) = exact.action else {
            plan.empty.insert(type)
            return nil
        }
        return (objectPlan, exact.isModifier)
    }

    /// A class instance in a field whose declared type `plan` names: what it
    /// holds, walked in place if this walk's view is the object's claimant,
    /// and then its own `update()`.
    private mutating func applyObject(
        _ plan: ObjectPlan, _ object: AnyObject, position: Int, scope: UInt64, updates: UpdateMode
    ) {
        let id = ObjectIdentifier(object)
        // Reached already in this walk — through another object, or another
        // field — it was walked and updated there.
        guard !objectsReached.contains(id) else { return }
        objectsReached.append(id)
        let claim = storage?.claimObjectContents(object, for: identity, isMeasuring: isMeasuring) ?? .walk
        if claim != .skip {
            let inner = NestedScope.container(at: position, ofType: type(of: object), in: scope)
            let outer = objectCaseDepth
            objectCaseDepth = caseDepth
            applyContents(of: object, scope: inner, isOwn: false, updates: updates)
            objectCaseDepth = outer
        }
        if updates == .inPlace, let updater = plan.updater {
            updater.updateObject(object)
        }
    }

    /// What `object` holds, walked in place: its storage is shared by every
    /// holder, so it is written where it lies.
    private mutating func applyContents(of object: AnyObject, scope: UInt64, isOwn: Bool, updates: UpdateMode) {
        let contents = PropertyPlans.contents(ofClass: type(of: object))
        guard !contents.steps.isEmpty else { return }
        objectDepth += 1
        defer { objectDepth -= 1 }
        withExtendedLifetime(object) {
            let base = Unmanaged.passUnretained(object).toOpaque()
            applySteps(of: contents, at: base, scope: scope, isOwn: isOwn, updates: updates)
        }
    }
}
