//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyPlans.swift
//
//  The plans of the property walk (`PropertyPlan.swift`), built once per type
//  from the runtime's field metadata (`RuntimeFields`) and kept for the life
//  of the process.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Building the plans

/// The plans, one per type, kept for the life of the process: a declaration
/// never changes.
///
/// Each table is reached through a pointer held as a constant — the reason
/// `ObservationLeases` and `VolatileReadTracker` keep their state that way: a
/// static variable is checked for exclusivity at run time on every read and
/// every write, where a load through a constant pointer is a plain load. Never
/// freed, as a static's value is not.
@MainActor
enum PropertyPlans {
    /// Each type's plan as a stored value.
    private static let slots = permanentTable([ObjectIdentifier: SlotPlan]())
    /// Each type's plan as the value a body is evaluated on.
    private static let roots = permanentTable([ObjectIdentifier: SlotPlan]())
    /// The types whose values hold nothing the walk acts on, as roots.
    private static let emptyRoots = permanentTable(Set<ObjectIdentifier>())
    /// Each class's contents.
    private static let classContents = permanentTable([ObjectIdentifier: FieldsPlan]())
    /// Each tuple's elements, as an enum case's payload.
    private static let payloads = permanentTable([ObjectIdentifier: FieldsPlan]())
    /// The plan of each class an object was found to be, as its exact type:
    /// an object plan for a property or modifier class, none for any other.
    private static let exactClasses = permanentTable([ObjectIdentifier: SlotPlan]())
    /// Every type an existential or a plain class field was found holding
    /// whose exact plan is none (``EmptyTypes``).
    static let emptyTypes = permanentTable(Set<ObjectIdentifier>())

    /// The plan for a value of `type` evaluated as a body's root, or `nil` if
    /// no value of it holds anything the walk acts on: nearly every view,
    /// which pays this one lookup and nothing else.
    @inline(__always)
    static func root(_ type: Any.Type) -> SlotPlan? {
        let key = ObjectIdentifier(type)
        if emptyRoots.pointee.contains(key) { return nil }
        if let plan = roots.pointee[key] { return plan }
        return buildRoot(type, key: key)
    }

    private static func buildRoot(_ type: Any.Type, key: ObjectIdentifier) -> SlotPlan? {
        let plan: SlotPlan
        switch RuntimeFields.Kind(of: type) {
        case .struct:
            var fields = fieldsPlan(of: type, updater: nil)
            if type is any AppliedModifierHolder.Type {
                fields = FieldsPlan(type: type, steps: markingAppliedModifier(in: fields, of: type), updater: nil)
            }
            if let own = type as? any ResolvesOwnEnvironment.Type {
                fields = FieldsPlan(type: type, steps: fields.steps.filter { !$0.isEnvironmentOnly }, updater: nil)
                plan = SlotPlan(.fields(fields), ownEnvironment: own)
            } else if fields.steps.isEmpty {
                plan = SlotPlan(.none)
            } else {
                plan = SlotPlan(.fields(fields), probes: rootProbes(fields))
            }
        case .enum:
            plan = SlotPlan(.enumeration(EnumPlan(type: type, updater: nil)))
        case let kind where kind.isClass:
            plan = SlotPlan(.object(ObjectPlan(type: type, updater: nil)))
        default:
            plan = SlotPlan(.none)
        }
        if plan.isNone {
            emptyRoots.pointee.insert(key)
            return nil
        }
        roots.pointee[key] = plan
        return plan
    }

    /// What is read of each of a view's fields before the view is copied, if
    /// every field the walk acts on is one whose value says whether it does
    /// (``SlotPlan/probes``): an existential, or an optional of one, laid out
    /// so that its dynamic type can be read where it lies, or a plain class.
    private static func rootProbes(_ fields: FieldsPlan) -> [RootProbe]? {
        var probes: [RootProbe] = []
        for step in fields.steps {
            guard !step.appliesModifier else { return nil }
            if let reference = step.reference {
                // A plain class held `unowned`: its class is read where it
                // lies, as a strong one's is; held `weak`: its object is
                // loaded, as the walk loads it. A property class is walked.
                guard case .dynamicClass(let plan) = step.slot.action else { return nil }
                let declared = UInt(bitPattern: ObjectIdentifier(plan.type))
                let kind: RootProbe.Kind =
                    reference.readsClassInPlace ? .unowned(declared: declared) : .weak(declared: declared)
                probes.append(RootProbe(offset: step.offset, kind: kind, empty: plan.empty))
                continue
            }
            var slot = step.slot
            if case .optional(let optional) = slot.action { slot = optional.wrapped }
            switch slot.action {
            case .existential(let existential) where existential.layout != .other:
                probes.append(
                    RootProbe(offset: step.offset, kind: .existential(existential.layout), empty: existential.empty))
            case .dynamicClass(let plan):
                probes.append(
                    RootProbe(
                        offset: step.offset, kind: .object(declared: UInt(bitPattern: ObjectIdentifier(plan.type))),
                        empty: plan.empty))
            default:
                return nil
            }
        }
        return probes
    }

    /// The plan for a value whose exact type is `type`, as an existential's
    /// or a plain class field's value is found to be: a class is planned by
    /// whether it is a property or modifier, as no subclass of it can be
    /// there; any other type as a stored value of it is.
    static func exact(_ type: Any.Type) -> SlotPlan {
        guard RuntimeFields.Kind(of: type).isClass else { return slot(type) }
        let key = ObjectIdentifier(type)
        if let plan = exactClasses.pointee[key] { return plan }
        let plan =
            isContainerType(type)
            ? SlotPlan(.object(ObjectPlan(type: type, updater: appPropertyType(type))), isModifier: type is any ViewModifier.Type)
            : SlotPlan(.none)
        exactClasses.pointee[key] = plan
        return plan
    }

    /// The plan for a stored value of declared type `type`.
    static func slot(_ type: Any.Type) -> SlotPlan {
        let key = ObjectIdentifier(type)
        if let plan = slots.pointee[key] { return plan }
        let action = action(forStored: type)
        let plan = SlotPlan(action, isModifier: isModifier(type, action))
        slots.pointee[key] = plan
        return plan
    }

    /// Whether a stored value of `type`, planned as `action`, is a modifier,
    /// or an optional of one.
    private static func isModifier(_ type: Any.Type, _ action: SlotPlan.Action) -> Bool {
        switch action {
        case .optional(let optional): optional.wrapped.isModifier
        case .fields, .enumeration, .object: type is any ViewModifier.Type
        default: false
        }
    }

    /// `fields`' steps, the step of `type`'s `modifier` field marked as the
    /// one whose modifier is applied: `type` is a ``ModifiedContent`` being
    /// drawn, whose body applies it.
    private static func markingAppliedModifier(in fields: FieldsPlan, of type: Any.Type) -> [FieldsPlan.Step] {
        let names = RuntimeFields.fields(of: type).map(\.name)
        var steps = fields.steps
        for index in steps.indices where names[steps[index].position] == "modifier" {
            steps[index].appliesModifier = true
        }
        return steps
    }

    /// What is done with a stored value of declared type `type`.
    private static func action(forStored type: Any.Type) -> SlotPlan.Action {
        if let leaf = Leaf.of(type) { return .leaf(leaf) }
        // Looking inside a `Binding` finds only its closures.
        if type is any FrameworkDynamicProperty.Type { return .none }
        switch RuntimeFields.Kind(of: type) {
        case .optional:
            guard let optional = type as? any OptionalPropertyHolder.Type else { return .none }
            let wrapped = slot(optional.wrappedType)
            return wrapped.isNone ? .none : .optional(OptionalPlan(type: optional, wrapped: wrapped))
        case .existential, .extendedExistential:
            // A stored view binds its own properties when it renders, and is
            // never looked inside: an `any View` is one.
            return type == (any View).self ? .none : .existential(ExistentialPlan(type: type))
        case .struct:
            guard isContainerType(type) else { return .none }
            let fields = fieldsPlan(of: type, updater: appPropertyType(type))
            return fields.steps.isEmpty && fields.updater == nil ? .none : .fields(fields)
        case .enum:
            guard isContainerType(type) else { return .none }
            return .enumeration(EnumPlan(type: type, updater: appPropertyType(type)))
        case let kind where kind.isClass:
            guard isContainerType(type) else {
                // A plain class held strongly: a subclass of it may be a
                // property, which SwiftUI never looks for (measured, session
                // notes DYNV/probe/dv2-main.out, `subclass`) and TUIkit did,
                // the owner kept (decisions-DYNVFIX B-DYNVFIX-1). Not a
                // Core Foundation class, which nothing subclasses. One held
                // `weak` or `unowned` is planned by `plainReferenceStep`.
                return kind == .foreignClass ? .none : .dynamicClass(DynamicClassPlan(type: type))
            }
            return .object(ObjectPlan(type: type, updater: appPropertyType(type)))
        default:
            // A tuple, a function, a metatype: not looked into, by SwiftUI
            // (measured) or here.
            return .none
        }
    }

    /// The fields of `type`, a struct or a tuple, that the walk acts on.
    static func fieldsPlan(of type: Any.Type, updater: (any DynamicProperty.Type)?) -> FieldsPlan {
        var steps: [FieldsPlan.Step] = []
        // A loop, not `compactMap`: a closure handed to the standard library
        // from here is a main-actor closure, and a release build checks at
        // run time that each call of it is on the main actor.
        for (position, field) in RuntimeFields.fields(of: type).enumerated() {
            if let step = step(for: field, position: position, owner: type, ownIndex: position) {
                steps.append(step)
            }
        }
        return FieldsPlan(type: type, steps: steps, updater: updater)
    }

    /// The step for one field at `position`, or `nil` if the walk does
    /// nothing with it. A field held `weak` or `unowned` is loaded only if its
    /// declared type is a property class, or a plain class whose object is of
    /// a subclass that is one; any other is never read, which matters for one
    /// whose object has gone. Its ownership is read from its mangled type
    /// name (``FieldDescriptors``), which the field metadata gives only as
    /// "not strong"; a field whose ownership cannot be read — where pointers
    /// are signed (arm64e, which TUIkit does not build) — is not reached.
    private static func step(
        for field: RuntimeFields.Field, position: Int, owner: Any.Type, ownIndex: Int
    ) -> FieldsPlan.Step? {
        if field.isStrong {
            let slot = slot(field.type)
            if slot.isNone { return nil }
            return FieldsPlan.Step(offset: field.offset, position: position, slot: slot, reference: nil)
        }
        var declared = field.type
        let isOptional = field.kind == .optional
        if isOptional, let optional = declared as? any OptionalPropertyHolder.Type {
            declared = optional.wrappedType
        }
        guard RuntimeFields.Kind(of: declared).isClass, isContainerType(declared) else {
            return plainReferenceStep(
                for: field, declared: declared, isOptional: isOptional, position: position, owner: owner,
                ownIndex: ownIndex)
        }
        guard let ownership = FieldDescriptors.ownership(ofField: ownIndex, named: field.name, in: owner),
            ownership != .strong
        else { return nil }
        let object = ObjectPlan(type: declared, updater: isOptional ? nil : appPropertyType(declared))
        return FieldsPlan.Step(
            offset: field.offset, position: position,
            slot: SlotPlan(.object(object), isModifier: declared is any ViewModifier.Type),
            reference: ReferenceField(ownership: ownership, isOptional: isOptional, object: object))
    }

    /// The step for a field held `weak` or `unowned` whose declared type,
    /// `declared`, is a plain class or a class-bound existential: its object
    /// may be of a class that is a property, which
    /// SwiftUI never looks for and TUIkit's walks found (decisions-DYNVFIX
    /// B-DYNVFIX-1). The field's ownership is read from its mangled type name
    /// (``FieldDescriptors``), which the field metadata gives only as "not
    /// strong":
    ///
    /// - `weak`: loaded each body, `nil` once its object has gone.
    /// - `unowned`, of a native Swift class: its object's class read where
    ///   the reference lies, and the object loaded only if that class is a
    ///   property — so one of any other class, dead or alive, is never loaded
    ///   (DYNV bug 9), and one of a property class traps if it has gone, as a
    ///   dead `unowned` property does (decided, as for a field declared as a
    ///   property class).
    /// - `unowned` of a class with an Objective-C ancestor: never loaded. Where
    ///   Objective-C interoperates, such a reference is kept as one of its weak
    ///   references, which only the runtime reads, and the runtime traps on
    ///   one whose object has gone.
    /// - `unowned`, of a class-bound existential: as of a native class, its
    ///   object's class read where the reference lies — unless, where
    ///   Objective-C interoperates, the reference says its object is an
    ///   Objective-C one, kept as above, whose class is then not read
    ///   (``DynamicTypes/unownedObject(at:)``).
    /// - `unowned(unsafe)`, or an ownership that cannot be read: never
    ///   loaded. Nothing keeps the object's memory, so nothing of it can be
    ///   read safely.
    private static func plainReferenceStep(
        for field: RuntimeFields.Field, declared: Any.Type, isOptional: Bool, position: Int, owner: Any.Type,
        ownIndex: Int
    ) -> FieldsPlan.Step? {
        // Not an Objective-C class or a Core Foundation one, which no Swift
        // subclass that is a property is declared as.
        let isClass = RuntimeFields.Kind(of: declared) == .class
        guard isClass || ExistentialLayout(declared) == .object else { return nil }
        guard let ownership = FieldDescriptors.ownership(ofField: ownIndex, named: field.name, in: owner) else {
            return nil
        }
        switch ownership {
        case .weak:
            break
        case .unowned where !isClass || isNativeClass(declared):
            break
        default:
            return nil
        }
        return FieldsPlan.Step(
            offset: field.offset, position: position, slot: SlotPlan(.dynamicClass(DynamicClassPlan(type: declared))),
            reference: ReferenceField(ownership: ownership, isOptional: isOptional, object: nil))
    }

    /// Whether every object of class `type`, a subclass's included, is a
    /// native Swift object: no class it descends from is an Objective-C
    /// class, which Swift reaches through a wrapper of another kind.
    private static func isNativeClass(_ type: Any.Type) -> Bool {
        #if _runtime(_ObjC)
            var next: AnyClass? = type as? AnyClass
            while let current = next {
                guard RuntimeFields.Kind(of: current) == .class else { return false }
                next = _getSuperclass(current)
            }
        #endif
        return true
    }

    /// The fields of `type`, a class, the walk acts on — its superclasses'
    /// included, each loaded by the class that declares it.
    static func contents(ofClass type: Any.Type) -> FieldsPlan {
        let key = ObjectIdentifier(type)
        if let plan = classContents.pointee[key] { return plan }
        // A field naming the class again plans an object, whose contents are
        // asked for only when one is reached: building this never recurses.
        var steps: [FieldsPlan.Step] = []
        var position = 0
        for owner in classChain(type) {
            let fields = RuntimeFields.ownClassFields(of: owner)
            for (ownIndex, field) in fields.enumerated() {
                if let step = step(for: field, position: position, owner: owner, ownIndex: ownIndex) {
                    steps.append(step)
                }
                position += 1
            }
        }
        let plan = FieldsPlan(type: type, steps: steps, updater: nil)
        classContents.pointee[key] = plan
        return plan
    }

    /// The elements of `type`, a tuple that is an enum case's payload, that
    /// the walk acts on. A tuple stored in a field is not looked into, by
    /// SwiftUI (measured) or here; one that is a payload is how a case holding
    /// more than one value holds them.
    static func payloadPlan(of type: Any.Type) -> FieldsPlan {
        let key = ObjectIdentifier(type)
        if let plan = payloads.pointee[key] { return plan }
        let plan = fieldsPlan(of: type, updater: nil)
        payloads.pointee[key] = plan
        return plan
    }

    /// `type` and its superclasses, root first, as the runtime lists their
    /// fields.
    private static func classChain(_ type: Any.Type) -> [Any.Type] {
        var chain: [Any.Type] = []
        var next: AnyClass? = type as? AnyClass
        while let current = next {
            chain.append(current)
            next = _getSuperclass(current)
        }
        return chain.reversed()
    }

    // MARK: Type questions

    /// Whether a value of declared type `type` is one the walk looks inside:
    /// an app's property, one of TUIkit's that holds properties
    /// (``FrameworkPropertyContainer``), or a modifier.
    static func isContainerType(_ type: Any.Type) -> Bool {
        if type is any FrameworkDynamicProperty.Type { return false }
        return type is any DynamicProperty.Type || type is any ViewModifier.Type
    }

    /// `type` as an app's property — one whose `update()` the framework
    /// runs, not one of TUIkit's own — or `nil`.
    static func appPropertyType(_ type: Any.Type) -> (any DynamicProperty.Type)? {
        guard let property = type as? any DynamicProperty.Type,
            !(type is any FrameworkDynamicProperty.Type), !(type is any FrameworkPropertyContainer.Type)
        else { return nil }
        return property
    }
}

/// `table`, moved into memory that is never freed — one of ``PropertyPlans``'.
private func permanentTable<Table>(_ table: Table) -> UnsafeMutablePointer<Table> {
    let pointer = UnsafeMutablePointer<Table>.allocate(capacity: 1)
    pointer.initialize(to: table)
    return pointer
}
