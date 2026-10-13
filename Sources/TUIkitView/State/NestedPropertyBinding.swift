//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedPropertyBinding.swift
//
//  How the property walk keys what a view holds below its own fields: the
//  `@State` and `@FocusState` inside an app's `DynamicProperty`, a modifier,
//  or an enum's case, each keyed by where it is declared inside the view.
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
/// swapped values (`Tools/SwiftUIProbes/Dynamic property discovery/notes.md` §5.5,
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
/// one container, or two types in one field, share a scope only by one
/// coincidence: a step whose code comes out `0`, the view's own scope, is
/// given `1`, which another step's code may be (one chance in 2^64). It is
/// not injective in both at once: two fields of one container differing in
/// position AND type, like two paths that differ higher up, share one only
/// by a 64-bit coincidence. Two cases of one enum may share one, since a
/// case's label is folded in as a hash; that is harmless, because a case
/// that replaces another starts from its defaults anyway
/// (``PropertyWalk``).
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

/// Which case an enum holding state held when the property walk last
/// visited it, and the keys of the state the walk created while it held
/// that case (``PropertyWalk``): what is dropped
/// when another case replaces it. For an enum inside the case, the key is
/// that enum's record, which lists what is created in its own case and is
/// dropped with it; so a case of the inner enum changing, however often,
/// while this one holds, adds nothing here.
final class EnumCaseRecord {
    var label: String
    var keys: [StateStorage.StateKey]

    init(label: String, keys: [StateStorage.StateKey]) {
        self.label = label
        self.keys = keys
    }
}
