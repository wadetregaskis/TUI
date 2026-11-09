//  🖥️ TUI — A Terminal UI framework for Swift
//  IdentityKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Element identity keys

/// The stable string key for a data element's `id`.
///
/// `ForEach` keys each row's identity by its element's id rather than its
/// position, so a row's `@State`, focus and lifecycle follow the element across
/// reorders and insertions. Scroll targeting (`ScrollViewReader.scrollTo(_:)`,
/// `ScrollPosition`, `ScrollAnchor`) addresses the same rows by the same key.
/// **Every one of those sites must derive the key the same way**, or a scroll
/// request silently fails to match the row it names — which is the first reason
/// this is one function rather than a conversion at each call site.
///
/// **Distinct ids get distinct keys, as SwiftUI tells ids apart by their
/// `Hashable` value.** The key used to be `String(describing:)` alone, and a
/// description is not an identity: two `Date`s within one second print alike,
/// so the second row read the first's `@State`. A type whose description is
/// one-to-one with its values (`String`, the integers, `UUID`, `Bool`,
/// `Character`) is keyed by it alone; any other id by its description followed
/// by `#` and its hash value. Two distinct ids would have to agree on both to
/// share a key. The hash is seeded per process, which is fine: a key lives no
/// longer than the process (nothing persists one).
///
/// The second reason for one function is cost. `String(describing:)` cannot
/// print anything until it has probed the value for `TextOutputStreamable`,
/// `CustomStringConvertible` and `CustomDebugStringConvertible` — three runtime
/// conformance lookups, then an existential box, then the formatting itself.
/// It runs once per row per layout pass. In a Time Profiler trace of the
/// `fanout` stress scenario it was **5.1% of all CPU**, effectively all of it
/// inside `swift_dynamicCast`. So the common id types are matched by a metatype
/// comparison — a pointer compare, no conformance lookup — and printed
/// directly.
///
/// - Important: The metatype comparison is not redundant with the cast that
///   follows it. A dynamic cast looks *through* `Optional` and `AnyHashable`,
///   so `id as? Int` alone would succeed for an `Int?` id and yield `"5"` where
///   an `Int?` is keyed as `"Optional(5)#…"` — silently re-keying every row
///   that uses an optional id. Requiring `ID.self == Int.self` first pins the
///   fast path to ids that genuinely are that type.
///
/// - Note: An id that arrives ERASED — scroll targeting passes an
///   `AnyHashable`'s `base`, typed `Any` — is keyed by its dynamic type, so it
///   gets the key its row got from the id's own type. An `AnyHashable` is
///   keyed as the value it wraps.
///
/// - Parameter id: The element's identifier.
/// - Returns: The key: `String(describing: id)`, followed by `#` and the id's
///   hash value unless its type describes each value differently.
package func identityKey<ID>(_ id: ID) -> String {
    if ID.self == String.self, let value = id as? String { return value }
    if ID.self == Int.self, let value = id as? Int { return String(value) }
    if ID.self == UUID.self, let value = id as? UUID { return value.uuidString }
    return erasedIdentityKey(id)
}

/// ``identityKey(_:)`` past its static fast paths: the id's dynamic type
/// decides, so `5`, `5 as Any` and `AnyHashable(5)` key alike.
private func erasedIdentityKey(_ id: Any) -> String {
    let type = Swift.type(of: id)
    if type == AnyHashable.self, let erased = id as? AnyHashable { return erasedIdentityKey(erased.base) }
    if type == String.self, let value = id as? String { return value }
    if type == Int.self, let value = id as? Int { return String(value) }
    if type == UUID.self, let value = id as? UUID { return value.uuidString }
    let description = String(describing: id)
    if describesEachValueDifferently(type) { return description }
    guard let hashable = id as? AnyHashable else { return description }
    return description + "#" + String(hashable.hashValue, radix: 36)
}

/// Whether `type`'s description is one-to-one with its values, so the
/// description alone is a key.
private func describesEachValueDifferently(_ type: Any.Type) -> Bool {
    type == Int8.self || type == Int16.self || type == Int32.self || type == Int64.self
        || type == UInt.self || type == UInt8.self || type == UInt16.self || type == UInt32.self
        || type == UInt64.self || type == Bool.self || type == Character.self || type == Substring.self
}
