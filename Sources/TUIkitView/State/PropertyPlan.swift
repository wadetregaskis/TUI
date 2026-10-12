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
