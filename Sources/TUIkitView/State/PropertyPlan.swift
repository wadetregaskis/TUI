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
        /// A class instance whose declared type is a plain class: one of its
        /// subclasses may be a property.
        case dynamicClass(DynamicClassPlan)
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
    /// but nothing in it updated (``FieldsPlan/Step/appliesModifier``). A
    /// modifier class is the exception (``storedCopySkipsUpdates``).
    let isModifier: Bool

    /// Whether a stored copy of the planned value — one not applied — has
    /// nothing in it updated: a modifier struct or enum, or an optional of
    /// one. Not a modifier CLASS: it is a property class wherever it is held,
    /// and updated before the body of every view holding it, as SwiftUI runs
    /// `update()` on a class that is both, held in a view's field (measured,
    /// `Tools/SwiftUIProbes/Dynamic property discovery/classmod.out`; decisions
    /// DYNVFIX, B-DYNVFIX-4).
    var storedCopySkipsUpdates: Bool {
        guard isModifier else { return false }
        switch action {
        case .object, .dynamicClass: return false
        case .optional(let optional): return optional.wrapped.storedCopySkipsUpdates
        default: return true
        }
    }

    /// For a view whose every field the walk acts on only if its value says
    /// so — an existential, a plain class however it is held, or an
    /// optional of either — what is read of each field before the view is
    /// copied: if none finds anything, `body` is evaluated on the view as it
    /// is (``preparedBody(of:plan:context:isMeasuring:)``).
    let probes: [RootProbe]?

    init(
        _ action: Action, ownEnvironment: (any ResolvesOwnEnvironment.Type)? = nil, isModifier: Bool = false,
        probes: [RootProbe]? = nil
    ) {
        self.action = action
        self.ownEnvironment = ownEnvironment
        self.isModifier = isModifier
        self.probes = probes
    }

    /// Whether the walk does nothing with a value of the planned type.
    var isNone: Bool {
        if case .none = action { return true }
        return false
    }

    /// Whether a value of the planned type may hold one of TUIkit's own
    /// properties outside any object it holds: an enum's case and an
    /// existential's value are known only from a value, so each may. What an
    /// object in it holds is that object's, not counted here.
    var mayInstall: Bool {
        switch action {
        case .leaf, .enumeration, .existential: true
        case .fields(let fields): fields.mayInstall
        case .optional(let optional): optional.wrapped.mayInstall
        case .none, .object, .dynamicClass: false
        }
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
    /// For `@Namespace` and `@FocusState`, how each is bound for the place its
    /// view is drawn at, in place of ``identity``.
    let placedIdentity: (any PlaceBoundIdentity.Type)?
    /// For `@FocusedValue` and `@FocusedBinding`, how each is resolved for the
    /// place its view is drawn at, in place of ``environment``.
    let placedReader: (any PlaceResolvedReader.Type)?

    /// The leaf for `type`, or `nil` if it is none of the three.
    static func of(_ type: Any.Type) -> Self? {
        let leaf = Self(
            state: type as? any StateBindable.Type,
            identity: type as? any RenderIdentityBindable.Type,
            environment: type as? any EnvironmentResolvable.Type,
            placeEnvironment: type as? any PlaceResolvedEnvironment.Type,
            placedIdentity: type as? any PlaceBoundIdentity.Type,
            placedReader: type as? any PlaceResolvedReader.Type)
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
        /// a strong reference, whose layout is not the field's.
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
    /// Whether a value of the type may hold one of TUIkit's own properties
    /// outside the objects it holds (``SlotPlan/mayInstall``): a class whose
    /// contents may not holds nothing a view's walk installs, and the walk of
    /// an object of it only runs the `update()`s in it.
    let mayInstall: Bool
    /// The first `@State` among the fields, or in a struct among them, at an
    /// offset fixed for the type — not behind an optional, an existential, an
    /// enum's case or another object: what tells, for a class's contents,
    /// whether an object was made in the pass that walks it before any of its
    /// ids is bound (``objectKind(at:in:)``).
    let firstState: (offset: Int, state: any StateBindable.Type)?

    init(type: Any.Type, steps: [Step], updater: (any DynamicProperty.Type)?) {
        self.type = type
        self.steps = steps
        self.updater = updater
        // A loop, not `contains(where:)`: a closure handed to the standard
        // library from here is checked, in a release build, to run on the
        // main actor. A field held `weak` or `unowned` holds an object.
        var mayInstall = false
        for step in steps where step.reference == nil && step.slot.mayInstall {
            mayInstall = true
            break
        }
        self.mayInstall = mayInstall
        var firstState: (offset: Int, state: any StateBindable.Type)?
        for step in steps where step.reference == nil {
            if case .leaf(let leaf) = step.slot.action, let state = leaf.state {
                firstState = (step.offset, state)
            } else if case .fields(let fields) = step.slot.action, let nested = fields.firstState {
                firstState = (step.offset + nested.offset, nested.state)
            }
            if firstState != nil { break }
        }
        self.firstState = firstState
    }

    /// What the object at `base`, of the class these are the contents of, is
    /// to the render pass `pass`, as ``firstState`` says: made in it, with a
    /// value of the view holding it; made before it; or `.unknown`, without a
    /// `@State` at a fixed offset to say.
    func objectKind(at base: UnsafeRawPointer, in pass: UInt32) -> ObjectKind {
        guard let firstState else { return .unknown }
        return firstState.state.objectKind(at: base + firstState.offset, in: pass)
    }
}

/// A field held `weak` or `unowned` whose declared type is a class, or a
/// class-bound existential: loaded where it lies, as Swift loads a reference
/// held that way (``HeldReferences``).
struct ReferenceField {
    /// How the field holds its object: never `.strong`.
    let ownership: FieldDescriptors.Ownership
    /// Whether it is held `weak` (or `unowned` as an optional): never
    /// updated, as SwiftUI updates none (measured, DYNP case 4).
    let isOptional: Bool
    /// The plan for the object it holds, when the declared class is a
    /// property or a modifier; `nil` for a plain class, whose object is
    /// planned by its own class (the step's ``SlotPlan/Action/dynamicClass(_:)``).
    let object: ObjectPlan?

    /// Whether the object's class is read where the field lies before it is
    /// loaded: an `unowned` reference to a native Swift object is its
    /// address, whose memory its unowned count keeps while the field holds
    /// it, alive or not (``DynamicTypes/unownedObject(at:)``). Only for a
    /// plain class or a class-bound existential: an object of a class that
    /// is not a property is then never loaded, which traps if it has gone
    /// (DYNV bug 9).
    var readsClassInPlace: Bool { object == nil && ownership == .unowned }

    /// The object the field at `address` holds, or `nil` for a `weak` one
    /// whose object has gone, or an optional one that holds none. One held
    /// `unowned` whose object has gone traps, as reading it in Swift does.
    func load(at address: UnsafeRawPointer) -> AnyObject? {
        HeldReferences.load(at: address, ownership, isOptional: isOptional)
    }
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
/// each body, where it lies (``DynamicTypes``), and planned as any field of
/// that type would be.
@MainActor
final class ExistentialPlan {
    /// The declared existential type, which the field's storage is laid out as.
    let type: Any.Type
    /// How the type's values are laid out.
    let layout: ExistentialLayout
    /// The dynamic types found in such a field holding nothing.
    let empty = EmptyTypes(everywhere: PropertyPlans.emptyTypes)

    init(type: Any.Type) {
        self.type = type
        layout = ExistentialLayout(type)
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

/// A field whose declared type is a class that is not a property: the object
/// in it may be of a subclass that is one, so its class is read each body,
/// where the reference lies (``DynamicTypes``) — or, for one held `weak`,
/// from the object loaded. The declared class, the usual case, and a class
/// noted as holding nothing, cost a compare.
@MainActor
final class DynamicClassPlan {
    /// The declared class.
    let type: Any.Type
    /// The subclasses found in such a field that are not properties.
    let empty = EmptyTypes(everywhere: PropertyPlans.emptyTypes)

    init(type: Any.Type) {
        self.type = type
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
