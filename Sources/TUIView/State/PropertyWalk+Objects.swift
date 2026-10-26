//  🖥️ TUI — A Terminal UI framework for Swift
//  PropertyWalk+Objects.swift
//
//  The property walk (`PropertyWalk.swift`) at a class instance: a class
//  property in a field, whatever its declared type and however it is held,
//  and what it holds.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension PropertyWalk {
    /// The object whose contents the walk is in (``PropertyWalk/objectWalk``),
    /// and what the walk knows of it.
    struct ObjectWalk {
        /// The object.
        let object: AnyObject
        /// Its hub; `nil` for a measure that reached it before any render
        /// walk made one, or a walk without storage.
        let hub: ObjectHub?
        /// The view's record of holding it in this field, made or moved by
        /// this walk; `nil` for a measure, or a walk without storage.
        let token: HolderToken?
        /// What its ids are made from (``ObjectHub/idPath``): `nil` binds
        /// none.
        let idPath: String?
        /// The scope of the field it lies in, in the key space of the view
        /// the walk is for (``PropertyWalk/keyScope(_:)``).
        let placeScope: UInt64
        /// Whether a `@State` in it made in the pass may take a box its place
        /// keeps already (``ObjectStateContext/adoptsPlace``).
        let adoptsPlace: Bool
        /// The hub of the object such a box is taken from
        /// (``ObjectStateContext/predecessor``).
        var predecessor: ObjectHub?
        /// What the walk notes of what it hands the object's `@Environment`s
        /// (``StateStorage/restoreEnvironments(to:)``).
        let environmentNotes: EnvironmentNotes
        /// Which walks hand the environment to the object's properties that
        /// keep what they take from it in one store every copy shares — a
        /// `@FocusState`'s focus manager, `@FocusedValue`, `@FocusedBinding` —
        /// which nothing puts back (``PropertyWalk/resolvesSharedStores(of:)``).
        let sharedStores: SharedStores
        /// What its `@State` has said of it so far in this walk.
        var found = ObjectKind.unknown
    }

    /// Which walks of an object hand the environment to its properties that
    /// keep what they take in one store every copy shares
    /// (``ObjectWalk/sharedStores``). None drawn as a backdrop does — the page
    /// beneath a modal, a covered navigation root, a `.dimmed()` view — whose
    /// focus manager focuses nothing and goes with the frame: a focus set from
    /// a closure through it goes nowhere. Of the rest, the object's primary
    /// holder's, so the object reads its primary's, not a later holder's; and
    /// while the primary is drawn as a backdrop, any other holder's.
    enum SharedStores: UInt8 {
        /// Any walk not drawn as a backdrop: before the object has a primary,
        /// a measure by the primary, a walk without storage.
        case unlessBackdrop
        /// A render walk by the primary, which also notes on the hub whether it
        /// is drawn as a backdrop (``ObjectHub/primaryDrawsBackdrop``).
        case primary
        /// Another holder's walk: only while the primary's last render walk
        /// was drawn as a backdrop, and this one is not.
        case whilePrimaryDrawsBackdrop
    }

    /// Whether this walk hands `object`'s properties that keep what they take
    /// from the environment in a store every copy shares the environment
    /// (``SharedStores``). Asked only at such a property: an object holding
    /// none reads nothing more.
    func resolvesSharedStores(of object: ObjectWalk) -> Bool {
        let drawsBackdrop = environment.drawsBackdrop
        switch object.sharedStores {
        case .unlessBackdrop:
            return !drawsBackdrop
        case .primary:
            object.hub?.primaryDrawsBackdrop = drawsBackdrop
            return !drawsBackdrop
        case .whilePrimaryDrawsBackdrop:
            return !drawsBackdrop && object.hub?.primaryDrawsBackdrop == true
        }
    }

    /// What a walk of an object notes of what it hands the object's
    /// `@Environment`s, so that its view's content reads its view's
    /// environment and, after that, the object reads what it read before.
    enum EnvironmentNotes {
        /// Nothing: the walk has no storage to note it in.
        case none
        /// What each box held, put back after the view's content
        /// (``StateStorage/pushEnvironmentRestore(_:previous:)``): every walk
        /// but a render walk by the object's primary holder.
        case putBack
        /// That the environment is the object's at rest: a render walk by its
        /// primary holder (``StateStorage/notePrimaryEnvironment(_:_:)``).
        case atRest
    }

    /// `scope`, a scope inside the object the walk is in, in the key space of
    /// the view the walk is for: joined to the scope of the field the object
    /// lies in. Outside every object, `scope` itself.
    ///
    /// An object's contents are walked in scopes of their own, rooted at the
    /// object (``NestedScope/view``), so its ids are the same whichever view
    /// and field hold it (``ObjectHub/idPath``). The `@State` of an object
    /// made with a view value, and the records of the enums in it, are keyed
    /// at the view instead: the scope inside the object, XORed with the
    /// field's, which is never `0`. XOR, as ``StateStorage/StateKey`` folds a
    /// scope into the index's word: two codes from different fields meet only
    /// by a 64-bit coincidence, and the object's own fields, at its root
    /// `0`, are keyed at the field's scope, where they were before objects'
    /// contents had a root of their own.
    func keyScope(_ scope: UInt64) -> UInt64 {
        guard let objectWalk else { return scope }
        return scope ^ objectWalk.placeScope
    }

    /// The object in a field declared as a plain class, which `plan` plans:
    /// walked as a class property if its class is one — a subclass of the
    /// declared class — and nothing otherwise. A class found not to be one
    /// is noted, so the next body that finds it there reads no further.
    mutating func applyDynamicClass(
        _ plan: DynamicClassPlan, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64,
        updates: UpdateMode
    ) {
        guard case .type(let objectType) = DynamicTypes.object(at: UnsafeRawPointer(address)),
            let found = propertyClassPlan(objectType, in: plan)
        else { return }
        let object = address.assumingMemoryBound(to: AnyObject.self).pointee
        // A modifier class too: a property class wherever it is held (B-DYNVFIX-4).
        applyObject(found, object, position: position, scope: scope, updates: updates)
    }

    /// The object in the field at `address`, declared as a plain class or a
    /// class-bound existential and held `weak` or `unowned`, which `plan`
    /// plans and `reference` says how to load: walked as a class property if
    /// its class is one, and nothing otherwise. An `unowned` one's class is
    /// read where the reference lies first, so an object of a class that is
    /// not a property is never loaded, which traps if it has gone (DYNV bug
    /// 9); a `weak` one is loaded, `nil` once it has gone.
    mutating func applyHeldPlainObject(
        _ plan: DynamicClassPlan, _ reference: ReferenceField, at address: UnsafeMutableRawPointer, position: Int,
        scope: UInt64, updates: UpdateMode
    ) {
        let loaded: AnyObject
        let found: ObjectPlan
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
        // A modifier class too: a property class wherever it is held (B-DYNVFIX-4).
        applyObject(found, loaded, position: position, scope: scope, updates: updates)
    }

    /// The plan of `type`, the class of an object found in a field `plan`
    /// plans, if it is a property or modifier class — never the declared
    /// class, nor one noted as holding nothing, which a class found not to be
    /// one then is.
    func propertyClassPlan(_ type: Any.Type, in plan: DynamicClassPlan) -> ObjectPlan? {
        if ObjectIdentifier(type) == ObjectIdentifier(plan.type) || plan.empty.contains(type) { return nil }
        guard case .object(let objectPlan) = PropertyPlans.exact(type).action else {
            plan.empty.insert(type)
            return nil
        }
        return objectPlan
    }

    /// A class instance in a field whose declared type `plan` names: what it
    /// holds, walked in place — its `@State`, ids and `@Environment`
    /// (``applyObjectLeaf(_:at:position:scope:in:)``) and its nested
    /// properties' `update()` — and then its own `update()`, before the body
    /// of every view holding it, as SwiftUI runs it (measured:
    /// `Tools/SwiftUIProbes/Class properties held by several views/cls.out`).
    ///
    /// A render walk registers the view as holding it (``StateStorage/registerHolder(_:of:at:kind:)``),
    /// so a write to its state redraws the view; a measure makes, moves and
    /// drops nothing a view's key holds. An object whose class holds nothing
    /// a walk installs has no hub: only the `update()`s in it run.
    mutating func applyObject(
        _ plan: ObjectPlan, _ object: AnyObject, position: Int, scope: UInt64, updates: UpdateMode
    ) {
        let id = ObjectIdentifier(object)
        // Reached already in this walk — through another object, or another
        // field — it was walked and updated there.
        guard !objectsReached.contains(id) else { return }
        objectsReached.append(id)
        let contents = PropertyPlans.contents(ofClass: type(of: object))
        if !contents.steps.isEmpty {
            let placeScope = NestedScope.container(at: position, ofType: type(of: object), in: keyScope(scope))
            let outer = objectWalk
            objectWalk = entering(object, contents, placeScope: placeScope)
            applyContents(of: object, contents, scope: NestedScope.view, isOwn: false, updates: updates)
            if let walked = objectWalk {
                if let token = walked.token, walked.found != .unknown { token.lastObject = walked.found }
                // Ids from a chain whose `@State` the walk found made before
                // the pass, where none at a fixed offset could say so first:
                // its own from the next walk on.
                if walked.found == .longLived, let hub = walked.hub, hub.takesChainIDs, let storage {
                    storage.giveOwnIDs(to: hub)
                }
            }
            objectWalk = outer
        }
        if updates == .inPlace, let updater = plan.updater {
            updater.updateObject(object)
        }
    }

    /// What the walk knows of `object`, about to walk what it holds —
    /// `contents` — lying in the field whose scope is `placeScope`: a render
    /// walk registers the view as holding it, if its class may hold anything
    /// a walk installs.
    private func entering(_ object: AnyObject, _ contents: FieldsPlan, placeScope: UInt64) -> ObjectWalk {
        guard contents.mayInstall, let storage else {
            return ObjectWalk(
                object: object, hub: nil, token: nil, idPath: nil, placeScope: placeScope, adoptsPlace: false,
                environmentNotes: .none, sharedStores: .unlessBackdrop)
        }
        // Whether the object was made in this pass, with a value of the view
        // holding it, as its first `@State` says before any of its ids is
        // bound: asked only where the object's ids may come from a chain.
        let base = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
        let pass = storage.currentPass
        func kind() -> ObjectKind { contents.objectKind(at: base, in: pass) }
        if !isMeasuring {
            let (hub, token, previous, predecessor) = storage.registerHolder(
                identity, of: object, at: placeScope, kind: kind)
            // The primary's environment is the object's at rest, for closures
            // and whatever else reads it outside every holder's content.
            let isPrimary = hub.primary == identity
            return ObjectWalk(
                object: object, hub: hub, token: token, idPath: hub.idPath, placeScope: placeScope,
                adoptsPlace: previous == .perValue, predecessor: predecessor,
                environmentNotes: isPrimary ? .atRest : .putBack,
                sharedStores: isPrimary ? .primary : .whilePrimaryDrawsBackdrop)
        }
        // A measure registers nothing, and puts back what it hands. Before
        // any render walk has made the object a hub, it binds the ids the
        // render will: those of the chain the object joins, if the view's last
        // object here was one of one.
        let previous = storage.holderToken(identity, at: placeScope)
        if let hub = storage.objectHub(of: object) {
            // What a render walk would do: the outcome is the same either way.
            if hub.takesChainIDs, kind() == .longLived { storage.giveOwnIDs(to: hub) }
            let primaryOrNone = hub.primary.map { $0 == identity } ?? true
            return ObjectWalk(
                object: object, hub: hub, token: nil, idPath: hub.idPath, placeScope: placeScope,
                adoptsPlace: previous?.lastObject == .perValue, environmentNotes: .putBack,
                sharedStores: primaryOrNone ? .unlessBackdrop : .whilePrimaryDrawsBackdrop)
        }
        let chained = previous.flatMap { $0.lastObject != .longLived && kind() != .longLived ? $0.hub.idPath : nil }
        return ObjectWalk(
            object: object, hub: nil, token: nil, idPath: chained, placeScope: placeScope,
            adoptsPlace: previous?.lastObject == .perValue, environmentNotes: .putBack, sharedStores: .unlessBackdrop)
    }

    /// What `object` holds, walked in place, in `scope`: its storage is
    /// shared by every holder, so it is written where it lies.
    mutating func applyContents(
        of object: AnyObject, _ contents: FieldsPlan, scope: UInt64, isOwn: Bool, updates: UpdateMode
    ) {
        objectDepth += 1
        defer { objectDepth -= 1 }
        withExtendedLifetime(object) {
            let base = Unmanaged.passUnretained(object).toOpaque()
            applySteps(of: contents, at: base, scope: scope, isOwn: isOwn, updates: updates)
        }
    }

    /// One of TUI's own properties at `address`, inside `object`'s object:
    /// its `@State` bound as the object's (``State/bindObjectState(at:to:key:in:isMeasuring:)``),
    /// its ids made from the object's (``ObjectHub/idPath``), and its
    /// `@Environment` resolved, in place, to the walking view's environment —
    /// put back after the view's content (``StateStorage/restoreEnvironments(to:)``),
    /// or, for a render walk by the object's primary holder, noted as the
    /// object's at rest (``StateStorage/notePrimaryEnvironment(_:_:)``). So
    /// while a holder's body and what it built run, the object reads that
    /// holder's environment, the innermost holder's where holders nest, and
    /// the outer one's again after the inner one's content; and anywhere else
    /// — an event's closure, a task, between passes — its primary's, as of
    /// the primary's last render walk. Its other properties that take from
    /// the environment keep it in a store every copy shares, which nothing
    /// puts back: the primary's walks hand it them, or another holder's while
    /// the primary is drawn as a backdrop, and none drawn as one does
    /// (``ObjectWalk/sharedStores``). A walk that hands one of them nothing
    /// still tells the memos above its view that the view reads it, if what
    /// it reads follows what no memo keys on (``UnkeyedEnvironmentReader``).
    mutating func applyObjectLeaf(
        _ leaf: Leaf, at address: UnsafeMutableRawPointer, position: Int, scope: UInt64, in object: ObjectWalk
    ) {
        if let state = leaf.state, let storage {
            let key = StateStorage.StateKey(identity: identity, propertyIndex: position, scope: keyScope(scope))
            let stored = caseDepth > 0 ? storage.count : 0
            let binding = state.bindObjectState(
                at: address, to: storage, key: key,
                in: ObjectStateContext(
                    object: object.object, hub: object.hub, adoptsPlace: object.adoptsPlace,
                    predecessor: object.predecessor),
                isMeasuring: isMeasuring)
            if binding.changed { changes += 1 }
            // A long-lived object's state anywhere in it says so: it ends the
            // chain of objects made with the view's values at this field.
            if objectWalk?.found != .longLived { objectWalk?.found = binding.kind }
            // An object made with a view value keeps the state of its enums'
            // cases at the view's key, recorded as a view value's is.
            if caseDepth > 0, storage.count != stored { created.append(key) }
        }
        if let bound = leaf.identity, let idPath = object.idPath {
            bound.bindRenderIdentity(
                at: address, path: NestedScope.identityPath(ofPath: idPath, in: scope), propertyIndex: position)
        }
        if let placed = leaf.placeEnvironment {
            let box = placed.environmentBox(at: address)
            if let storage {
                switch object.environmentNotes {
                case .putBack: storage.pushEnvironmentRestore(box, previous: box.environment)
                case .atRest: storage.notePrimaryEnvironment(box, environment)
                case .none: break
                }
            }
            box.environment = environment
        } else if let resolvable = leaf.environment {
            if resolvesSharedStores(of: object) {
                resolvable.resolveEnvironment(at: address, environment)
            } else if let reader = resolvable as? any UnkeyedEnvironmentReader.Type {
                // Handed nothing, it is read all the same: the memos above
                // this holder must not keep what its body draws from it.
                reader.noteUnkeyedRead(in: environment)
            }
        }
    }
}
