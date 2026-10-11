//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedPropertyBinding.swift
//
//  The binding walk below a view's own fields: the `@State` and `@FocusState`
//  inside an app's `DynamicProperty`, a modifier, or an enum's case, each
//  keyed by where it is declared inside the view.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Where inside a view a property nested in another lies: the
/// ``StateStorage/StateKey/scope`` of its key.
///
/// A view's own properties are keyed by declaration order, in scope
/// ``view``. One the view holds inside something else is keyed by its
/// position there, in a scope derived, step by step, from the path down to
/// it: each container's position among its parent's stored values and its
/// type, and each enum's case. None of that depends on the values of the
/// view's other fields. One shared counter, which a property found inside a
/// `nil` optional, an existential of another type or another enum case did
/// not advance, moved every key after it, and two `@State`s of one type then
/// swapped values (session notes `DYNP/optional/notes.md` §5.5,
/// `DynamicPropertyStateKeyTests`).
///
/// A container's type is part of its step because an existential field can
/// hold another type from one value to the next: what a new type holds must
/// not take over what the old one stored. (SwiftUI never binds a property
/// in an existential field, measured — decisions-DYNP A-DYNP-1 — so there
/// is no behaviour of its to match; a type that comes back finds what it
/// left, as an optional that comes back does.) For any other field the type
/// is the same on every frame.
///
/// A scope is a 64-bit code, not the path itself, so that building one
/// allocates nothing. For a given parent, each step is injective in either
/// of its inputs while the other is fixed — ``mixHashWord(_:_:)`` and
/// ``finalizeHashWord64(_:)`` are bijections — so two fields of one type in
/// one container, or two types in one field, never share a scope. It is not
/// injective in both at once: two fields of one container differing in
/// position AND type, like two paths that differ higher up, share one only
/// by a 64-bit coincidence. Two cases of one enum may share one, since a
/// case's label is folded in as a hash; that is harmless, because a case
/// that replaces another starts from its defaults anyway
/// (``NestedPropertyWalk``).
enum NestedScope {
    /// The scope of a view's own properties.
    static var view: UInt64 { 0 }

    /// The scope of what a container holds: the container being the value
    /// at `position` among those stored in the scope `parent`, of dynamic
    /// type `type`.
    static func container(at position: Int, ofType type: Any.Type, in parent: UInt64) -> UInt64 {
        step(
            parent, UInt64(truncatingIfNeeded: position),
            UInt64(UInt(bitPattern: ObjectIdentifier(type))))
    }

    /// The scope of the payload of an enum's case `label`, the enum's own
    /// properties being keyed in `parent`.
    static func enumCase(_ label: String, in parent: UInt64) -> UInt64 {
        var labelHash = hashFoldSeed
        for byte in label.utf8 {
            labelHash = mixHashWord(labelHash, UInt64(byte))
        }
        // `UInt64.max` is never a position, which `container` folds in at
        // the same place.
        return step(parent, .max, labelHash)
    }

    /// The id path a property bound to its view's identity
    /// (``RenderIdentityBindable``) gets in `scope`: the view's own path for
    /// the view's own properties, and the path with the scope after it for
    /// a nested one, so the two never meet.
    static func identityPath(of identity: ViewIdentity, in scope: UInt64) -> String {
        scope == view ? identity.path : "\(identity.path)::\(String(scope, radix: 16))"
    }

    private static func step(_ parent: UInt64, _ first: UInt64, _ second: UInt64) -> UInt64 {
        let code = finalizeHashWord64(
            mixHashWord(mixHashWord(mixHashWord(hashFoldSeed, parent), first), second))
        // `0` is the view's own scope; a nested one must never be it.
        return code == view ? 1 : code
    }
}

/// The binding walk below a view's own fields
/// (``bindStateProperties(of:identity:storage:)``): what an app's
/// ``DynamicProperty``, a ``ViewModifier``, an optional of either, or an
/// enum's case holds, at any depth, each keyed in its ``NestedScope``.
///
/// **An enum's case.** A value that is an enum — a view that is one, or a
/// property or modifier — holds what its current case's payload holds.
/// When the case changes, the new case's `@State` starts at its defaults,
/// and so does the old case's when it comes back, as SwiftUI's does
/// (measured on macOS 15, session notes `SKEY/probe/skey.out`: an enum
/// view's and an enum property's cases, and two cases of one payload type).
/// The walk keeps which case it last saw, beside the state
/// (``StateStorage/recordEnumCase(_:at:)``), and binds a case that replaced
/// another to new storage. A case holding more than one value has each
/// value walked, by its position (``NestedProperties/isTuple(_:)``).
@MainActor
struct NestedPropertyWalk {
    /// The view's identity, which every nested key shares.
    let identity: ViewIdentity
    let storage: StateStorage

    /// Whether the walk met an app's property whose ``DynamicProperty/update()``
    /// the caller runs.
    var hasAppProperties = false

    /// Whether the walk bound anything, for the enum case records: an enum
    /// whose cases have held nothing to bind keeps none.
    private var boundAny = false

    init(identity: ViewIdentity, storage: StateStorage) {
        self.identity = identity
        self.storage = storage
    }

    /// Binds what `container` holds — found at `position` among the values
    /// stored in `scope`, under `label` in `parent` — in a scope of its own,
    /// noting whether it is an app property.
    mutating func bindContents(
        ofContainer container: Any, label: String?, in parent: Any, position: Int, scope: UInt64,
        fresh: Bool
    ) {
        let inner = NestedScope.container(at: position, ofType: type(of: container), in: scope)
        guard NestedProperties.isAppProperty(container) else {
            bindContents(of: container, scope: inner, fresh: fresh)
            return
        }
        if NestedProperties.isHeldWeakly(label, in: parent) {
            // The write-back passes over a property held `weak` (SwiftUI
            // does not update one either), so neither it nor what it holds
            // makes the view one to update. What it holds is still bound, as
            // an optional's is (decisions-DYNP A-DYNP-1).
            let counted = hasAppProperties
            bindContents(of: container, scope: inner, fresh: fresh)
            hasAppProperties = counted
            return
        }
        hasAppProperties = true
        bindContents(of: container, scope: inner, fresh: fresh)
    }

    /// Binds each value `value` stores, by its position, in `scope` — or,
    /// for an enum, what its case's payload holds.
    ///
    /// - Parameter fresh: Whether to bind each `@State` to new storage, in
    ///   place of what it had: the walk is inside an enum's case that has
    ///   just replaced another.
    mutating func bindContents(of value: Any, scope: UInt64, fresh: Bool) {
        let mirror = Mirror(reflecting: value)
        if NestedProperties.isEnum(value) {
            bindCase(of: mirror, scope: scope, fresh: fresh)
            return
        }
        var position = 0
        for child in mirror.children {
            bind(child.value, label: child.label, in: value, position: position, scope: scope, fresh: fresh)
            position += 1
        }
    }

    /// Binds what the enum `mirror` reflects holds: its case's payload, in a
    /// scope of that case's, and to new storage when the case has replaced
    /// the one last recorded at `scope`.
    mutating func bindCase(of mirror: Mirror, scope: UInt64, fresh: Bool) {
        let recordKey = StateStorage.StateKey(
            identity: identity, propertyIndex: StateStorage.StateKey.enumCaseIndex, scope: scope)
        let previous = storage.enumCase(at: recordKey)
        // An enum's `Mirror` has one child, labelled with the case's name and
        // holding its payload, or none for a case without one.
        guard let payload = mirror.children.first else {
            // Holds nothing; recorded only where a case before it held
            // something, so that case starts afresh when it returns.
            if let previous, !previous.isEmpty { storage.recordEnumCase("", at: recordKey) }
            return
        }
        let label = payload.label ?? ""
        let replaced = fresh || (previous != nil && previous != label)
        let caseScope = NestedScope.enumCase(label, in: scope)
        let boundBefore = boundAny
        boundAny = false
        if NestedProperties.isTuple(payload.value) {
            // A case holding more than one value. A label is asked of a
            // parent only for a `weak` field, which a tuple's element cannot
            // be, so none is passed.
            var position = 0
            for element in Mirror(reflecting: payload.value).children {
                bind(element.value, label: nil, in: payload.value, position: position, scope: caseScope, fresh: replaced)
                position += 1
            }
        } else {
            bind(payload.value, label: nil, in: payload.value, position: 0, scope: caseScope, fresh: replaced)
        }
        if previous != label && (boundAny || previous != nil) {
            storage.recordEnumCase(label, at: recordKey)
        }
        boundAny = boundAny || boundBefore
    }

    /// Binds one stored value: a `@State`, a property bound to the view's
    /// identity, or a container the walk descends into.
    private mutating func bind(
        _ value: Any, label: String?, in parent: Any, position: Int, scope: UInt64, fresh: Bool
    ) {
        if let bindable = value as? StateBindable {
            let key = StateStorage.StateKey(identity: identity, propertyIndex: position, scope: scope)
            if fresh {
                bindable.bindFreshState(to: storage, key: key)
            } else {
                bindable.bindState(to: storage, key: key)
            }
            boundAny = true
        } else if let idBindable = value as? RenderIdentityBindable {
            idBindable.bindRenderIdentity(
                path: NestedScope.identityPath(of: identity, in: scope), propertyIndex: position)
            boundAny = true
        } else if let container = NestedProperties.container(value) {
            bindContents(ofContainer: container, label: label, in: parent, position: position, scope: scope, fresh: fresh)
        }
    }
}

/// Which case an enum holding properties held when the property walk last
/// visited it (``StateStorage/recordEnumCase(_:at:)``).
final class EnumCaseRecord {
    var label: String

    init(label: String) {
        self.label = label
    }
}
