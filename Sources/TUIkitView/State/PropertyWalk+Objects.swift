//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyWalk+Objects.swift
//
//  The property walk (`PropertyWalk.swift`) at a class instance: a class
//  property in a field, whatever its declared type and however it is held,
//  and what it holds.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension PropertyWalk {
    /// A walk that hands `environment`, the claimant's, to each
    /// `@Environment` that has none in an object another view claims
    /// (``ObjectContentsClaim/fillEnvironment(_:)``), and does nothing else.
    /// Without storage, it binds no `@State`, consults no claim and keeps no
    /// enum's case, so an object it reaches inside is filled the same way;
    /// it runs no `update()`, as it is handed ``UpdateMode/none``. It starts
    /// with the objects `walk` has reached, and what it reaches after is its
    /// own: an object it fills is still walked by `walk` if `walk` reaches it
    /// elsewhere.
    init(filling environment: EnvironmentValues, for walk: Self) {
        self.identity = walk.identity
        self.storage = nil
        self.environment = environment
        self.isMeasuring = walk.isMeasuring
        self.fillsEnvironmentOnly = true
        self.objectsReached = walk.objectsReached
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
    mutating func applyHeldPlainObject(
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
    func propertyClassPlan(_ type: Any.Type, in plan: DynamicClassPlan) -> (plan: ObjectPlan, isModifier: Bool)? {
        if ObjectIdentifier(type) == ObjectIdentifier(plan.type) || plan.empty.contains(type) { return nil }
        let exact = PropertyPlans.exact(type)
        guard case .object(let objectPlan) = exact.action else {
            plan.empty.insert(type)
            return nil
        }
        return (objectPlan, exact.isModifier)
    }

    /// A class instance in a field whose declared type `plan` names: what it
    /// holds, walked in place if this walk's view is the object's claimant —
    /// or, for a measure that reaches it before its claimant has walked it in
    /// the pass, each `@Environment` there that has none handed the
    /// claimant's last environment — and then its own `update()`.
    mutating func applyObject(
        _ plan: ObjectPlan, _ object: AnyObject, position: Int, scope: UInt64, updates: UpdateMode
    ) {
        let id = ObjectIdentifier(object)
        // Reached already in this walk — through another object, or another
        // field — it was walked and updated there.
        guard !objectsReached.contains(id) else { return }
        objectsReached.append(id)
        let claim =
            storage?.claimObjectContents(object, for: identity, environment: environment, isMeasuring: isMeasuring)
            ?? .walk
        switch claim {
        case .walk:
            let inner = NestedScope.container(at: position, ofType: type(of: object), in: scope)
            let outer = objectCaseDepth
            objectCaseDepth = caseDepth
            applyContents(of: object, scope: inner, isOwn: false, updates: updates)
            objectCaseDepth = outer
        case .fillEnvironment(let claimantEnvironment):
            var fill = Self(filling: claimantEnvironment, for: self)
            fill.applyContents(of: object, scope: scope, isOwn: false, updates: .none)
        case .skip:
            break
        }
        if updates == .inPlace, let updater = plan.updater {
            updater.updateObject(object)
        }
    }

    /// What `object` holds, walked in place: its storage is shared by every
    /// holder, so it is written where it lies.
    mutating func applyContents(of object: AnyObject, scope: UInt64, isOwn: Bool, updates: UpdateMode) {
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
