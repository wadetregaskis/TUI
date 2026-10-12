//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyPlan.swift
//
//  What the property walk does with a value of each type, worked out once per
//  type from the runtime's field metadata (`RuntimeFields`): where its
//  `@State`, `@Environment` and app properties lie, at which offsets, and
//  which of its fields only the value can say more about — an optional, an
//  existential, an enum's case, an object.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What the property walk (``PropertyWalk``) does with one stored value of a
/// type, planned once per type from its declaration.
///
/// Every field is planned by its DECLARED type, as SwiftUI's
/// `DynamicPropertyCache` plans them: a field whose type cannot hold a
/// property is never loaded, so a dead `unowned` reference a view never reads
/// is never read (it traps when loaded), and a view's custom `Mirror` changes
/// nothing (the field metadata is not the mirror). Where the declared type is
/// open — an optional, an existential, an enum, an object — the plan says
/// where a property may be, and each body the value says whether one is
/// there: a `nil` check, the existential's dynamic type, the enum's case, the
/// object.
@MainActor
package final class SlotPlan {
    /// What is done with a value of the planned type.
    enum Action {
        /// Nothing: no walk acts on a value of this type, and none is loaded.
        case none
        /// One of TUIkit's own properties: a `@State` to bind, an id to bind,
        /// an environment to hand in.
        case leaf(Leaf)
        /// A struct whose fields the walk visits: an app's property, a
        /// modifier, one of TUIkit's property containers, or the view itself.
        case fields(FieldsPlan)
        /// An enum whose current case says what it holds.
        case enumeration(EnumPlan)
        /// An optional of something the walk acts on: its payload, if any.
        case optional(OptionalPlan)
        /// An existential: what it holds, planned by its dynamic type.
        case existential(ExistentialPlan)
        /// A class instance whose declared type is a property or modifier.
        case object(ObjectPlan)
    }

    let action: Action

    /// For a framework view that resolves its own `@Environment` properties
    /// (``ResolvesOwnEnvironment``), at the root of its body: the type, whose
    /// own environment-only fields the plan then leaves out.
    let ownEnvironment: (any ResolvesOwnEnvironment.Type)?

    /// Whether the planned value is a ``ViewModifier`` (or an optional of
    /// one). A modifier's properties are updated only where it is APPLIED —
    /// as the `modifier` of the ``ModifiedContent`` being drawn — and once
    /// there; one stored anywhere else has its properties bound and resolved,
    /// but nothing in it updated (``FieldsPlan/Step/appliesModifier``).
    let isModifier: Bool

    init(
        _ action: Action, ownEnvironment: (any ResolvesOwnEnvironment.Type)? = nil, isModifier: Bool = false
    ) {
        self.action = action
        self.ownEnvironment = ownEnvironment
        self.isModifier = isModifier
    }

    /// Whether the walk does nothing with a value of the planned type.
    var isNone: Bool {
        if case .none = action { return true }
        return false
    }
}

/// One of TUIkit's own dynamic properties, as the walk handles it: each part
/// the type has, in the order the walk applies them.
struct Leaf {
    /// A `@State`: bound to the storage kept for its key.
    let state: (any StateBindable.Type)?
    /// A property bound to an id from its view's identity (`@FocusState`,
    /// `@Namespace`).
    let identity: (any RenderIdentityBindable.Type)?
    /// A property handed its view's environment (`@Environment`,
    /// `@FocusedValue`, `@FocusState`'s manager).
    let environment: (any EnvironmentResolvable.Type)?
    /// For an `@Environment`, how it is handed one for the place its view is
    /// drawn at, in place of ``environment``.
    let placeEnvironment: (any PlaceResolvedEnvironment.Type)?

    /// The leaf for `type`, or `nil` if it is none of the three.
    static func of(_ type: Any.Type) -> Self? {
        let leaf = Self(
            state: type as? any StateBindable.Type,
            identity: type as? any RenderIdentityBindable.Type,
            environment: type as? any EnvironmentResolvable.Type,
            placeEnvironment: type as? any PlaceResolvedEnvironment.Type)
        return leaf.state == nil && leaf.identity == nil && leaf.environment == nil ? nil : leaf
    }

    /// Whether the leaf takes the next of its view's own declaration-order
    /// indices, when it is one of the view's own fields.
    var isIndexed: Bool { state != nil || identity != nil }
}

/// The fields of a struct the walk visits, each with what it does there.
@MainActor
final class FieldsPlan {
    /// One field the walk acts on.
    struct Step {
        /// Its byte offset in the value.
        let offset: Int
        /// Its position among the type's stored fields: the key of what it
        /// holds, in a nested scope (``NestedScope``).
        let position: Int
        /// What is done with it.
        let slot: SlotPlan
        /// For a field held `weak` or `unowned`, how it is loaded: never as
        /// its declared type, whose layout is not the field's.
        let reference: ReferenceField?
        /// Whether the field is the modifier a ``ModifiedContent`` that is
        /// being drawn applies: the one place a modifier's properties are
        /// updated (``SlotPlan/isModifier``).
        var appliesModifier = false

        /// Whether all the step does is hand an environment in: what a
        /// ``ResolvesOwnEnvironment`` view does itself.
        @MainActor var isEnvironmentOnly: Bool {
            guard case .leaf(let leaf) = slot.action else { return false }
            return leaf.environment != nil && !leaf.isIndexed
        }
    }

    /// The planned type.
    let type: Any.Type
    /// The fields acted on, in declaration order.
    let steps: [Step]
    /// The type's own `update()`, run after its fields', if it is an app's
    /// property (not one of TUIkit's, whose `update()` does nothing).
    let updater: (any DynamicProperty.Type)?

    init(type: Any.Type, steps: [Step], updater: (any DynamicProperty.Type)?) {
        self.type = type
        self.steps = steps
        self.updater = updater
    }
}

/// A field held `weak` or `unowned` whose declared type is a property class:
/// loaded through the runtime's own reflection entry point, which knows how
/// each ownership is stored (``PropertyPlans/loadReference(of:index:in:)``).
struct ReferenceField {
    /// The struct, or class, that declares the field, and its index among
    /// that type's own fields.
    let owner: Any.Type
    let index: Int
    /// Whether it is held `weak` (or `unowned` as an optional): never
    /// updated, as SwiftUI updates none (measured, DYNP case 4).
    let isOptional: Bool
    /// The plan for the object it holds.
    let object: ObjectPlan
}

/// An optional of something the walk acts on.
@MainActor
final class OptionalPlan {
    /// The optional type, for the `nil` check.
    let type: any OptionalPropertyHolder.Type
    /// What is done with the payload, when there is one.
    let wrapped: SlotPlan

    init(type: any OptionalPropertyHolder.Type, wrapped: SlotPlan) {
        self.type = type
        self.wrapped = wrapped
    }
}

/// An existential field: any value may be in it, so its dynamic type is read
/// each body and planned as any field of that type would be.
@MainActor
final class ExistentialPlan {
    /// The declared existential type, which the field's storage is laid out as.
    let type: Any.Type

    init(type: Any.Type) {
        self.type = type
    }
}

/// An enum that is a property, or a view: the walk acts on its current case's
/// payload.
@MainActor
final class EnumPlan {
    /// The enum.
    let type: Any.Type
    /// Its own `update()`, run after its payload's, if it is an app property.
    let updater: (any DynamicProperty.Type)?
    /// Its cases, and how its case is read and its payload reached.
    let cases: EnumCasesPlan

    init(type: Any.Type, updater: (any DynamicProperty.Type)?) {
        self.type = type
        self.updater = updater
        cases = EnumCasesPlan(type)
    }
}

/// A class instance in a field whose declared type is a property or a
/// modifier: its contents are planned by its dynamic class when it is reached
/// (``PropertyPlans/contents(ofClass:)``).
@MainActor
final class ObjectPlan {
    /// The declared class.
    let type: Any.Type
    /// The class's `update()`, if it is an app property.
    let updater: (any DynamicProperty.Type)?

    init(type: Any.Type, updater: (any DynamicProperty.Type)?) {
        self.type = type
        self.updater = updater
    }
}

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
            } else {
                plan = SlotPlan(fields.steps.isEmpty ? .none : .fields(fields))
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
            guard isContainerType(type) else { return .none }
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
    /// declared type is a property class; any other is never read, which
    /// matters for one whose object has gone.
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
        guard RuntimeFields.Kind(of: declared).isClass, isContainerType(declared) else { return nil }
        let object = ObjectPlan(type: declared, updater: isOptional ? nil : appPropertyType(declared))
        return FieldsPlan.Step(
            offset: field.offset, position: position, slot: SlotPlan(.object(object)),
            reference: ReferenceField(owner: owner, index: ownIndex, isOptional: isOptional, object: object))
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

    /// The object held in the field `reference` names, in the struct at
    /// `base`: loaded by the runtime, which reads each ownership as it is
    /// stored, or `nil` for a `weak` one whose object has gone.
    static func loadReference(_ reference: ReferenceField, at base: UnsafeMutableRawPointer) -> AnyObject? {
        loadReference(reference, at: base, in: reference.owner)
    }

    private static func loadReference<Owner>(
        _ reference: ReferenceField, at base: UnsafeMutableRawPointer, in _: Owner.Type
    ) -> AnyObject? {
        let value = RuntimeChildren.child(
            of: base.assumingMemoryBound(to: Owner.self).pointee, as: Owner.self, at: reference.index
        ).value
        return object(value, as: reference.object.type)
    }

    /// The object held in the field `reference` names, in `object`.
    static func loadReference(_ reference: ReferenceField, in object: AnyObject) -> AnyObject? {
        let value = RuntimeChildren.child(of: object, as: reference.owner, at: reference.index).value
        return self.object(value, as: reference.object.type)
    }

    /// `value`, a field's contents the runtime copied out, as an instance of
    /// `type`, its declared class — looking through the optional a `weak`
    /// field is read as — or `nil`.
    private static func object<Declared>(_ value: Any, as _: Declared.Type) -> AnyObject? {
        guard let object = value as? Declared else { return nil }
        return object as AnyObject
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

// MARK: - Optional

/// An `Optional` opened to its wrapped type.
protocol OptionalPropertyHolder {
    /// The type the optional wraps.
    static var wrappedType: Any.Type { get }

    /// Whether the optional at `address` holds a value.
    static func hasValue(at address: UnsafeRawPointer) -> Bool
}

extension Optional: OptionalPropertyHolder {
    static var wrappedType: Any.Type { Wrapped.self }

    static func hasValue(at address: UnsafeRawPointer) -> Bool {
        address.assumingMemoryBound(to: Self.self).pointee != nil
    }
}
