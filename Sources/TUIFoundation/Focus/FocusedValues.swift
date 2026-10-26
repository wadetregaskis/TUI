//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusedValues.swift
//
//  The table views publish into with `.focusedValue(_:_:)` and
//  `.focusedSceneValue(_:_:)`, and `@FocusedValue` reads back for wherever the
//  focus is. The publishing and the reading live in `FocusedValueRegistry`;
//  this file is the vocabulary.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - FocusedValueKey

/// A key for accessing values in the ``FocusedValues`` table. Mirrors
/// SwiftUI's `FocusedValueKey`.
///
/// Declare a key and a property on `FocusedValues` that reads and writes
/// through it, then publish with `focusedValue(_:_:)` and
/// read with ``FocusedValue``:
///
/// ```swift
/// struct SelectedNoteKey: FocusedValueKey {
///     typealias Value = Binding<Note>
/// }
///
/// extension FocusedValues {
///     var selectedNote: Binding<Note>? {
///         get { self[SelectedNoteKey.self] }
///         set { self[SelectedNoteKey.self] = newValue }
///     }
/// }
/// ```
///
/// - Note: `@Entry var selectedNote: Binding<Note>?` inside the extension
///   writes the key and the property in one line, as in SwiftUI. The macro is
///   in the opt-in `TUIMacros` product (`import TUIMacros`); without it
///   the two are written out as above, which is what the macro expands to.
public protocol FocusedValueKey {
    /// The type of the value the key names.
    associatedtype Value
}

// MARK: - FocusedValues

/// A collection of state exported by the focused view and its ancestors.
/// Mirrors SwiftUI's `FocusedValues`.
///
/// You do not make one: extend it with a property per ``FocusedValueKey``,
/// publish values with `focusedValue(_:_:)` or
/// `focusedSceneValue(_:_:)`, and read them with ``FocusedValue``
/// or ``FocusedBinding``.
///
/// Two tables are equal when they hold the same keys and each pair of values
/// is equal: by `==` for an `Equatable` value, by identity for an object, and
/// otherwise — a closure, a `Binding` — when the same view published both,
/// which is as far as an opaque value can be compared.
public struct FocusedValues: Equatable {
    /// One value in the table, with the view that published it.
    struct Entry {
        let value: Any
        /// Where the publishing modifier rendered; `nil` until the registry
        /// files the table under its publisher.
        var publisher: ViewIdentity?
    }

    /// The values, by key type.
    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    /// An empty table. Only the framework makes one.
    init() {}

    /// Reads or writes the value for `key`.
    public subscript<Key: FocusedValueKey>(key: Key.Type) -> Key.Value? {
        get { entries[ObjectIdentifier(key)]?.value as? Key.Value }
        set {
            entries[ObjectIdentifier(key)] = newValue.map { Entry(value: $0, publisher: nil) }
        }
    }

    /// Whether the table holds nothing.
    var isEmpty: Bool { entries.isEmpty }

    /// This table with every entry stamped with the view that published it.
    func published(by publisher: ViewIdentity) -> Self {
        var copy = self
        for key in copy.entries.keys {
            copy.entries[key]?.publisher = publisher
        }
        return copy
    }

    /// Copies every entry of `other` over this table's entries for the same
    /// keys.
    mutating func overlay(_ other: Self) {
        entries.merge(other.entries) { _, new in new }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        for (key, left) in lhs.entries {
            guard let right = rhs.entries[key], Self.sameValue(left, right) else { return false }
        }
        return true
    }

    /// Whether two entries hold the same value, as far as can be told.
    private static func sameValue(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if let equal = equalIfEquatable(lhs.value, rhs.value) { return equal }
        if type(of: lhs.value) is AnyClass, type(of: rhs.value) is AnyClass {
            return (lhs.value as AnyObject) === (rhs.value as AnyObject)
        }
        return lhs.publisher != nil && lhs.publisher == rhs.publisher
    }
}

/// `==` on two values of unknown type, if the first is `Equatable`; `nil`
/// when it is not, and `false` when the second is of another type.
private func equalIfEquatable(_ lhs: Any, _ rhs: Any) -> Bool? {
    guard let equatable = lhs as? any Equatable else { return nil }
    return equatable.isEqual(toAny: rhs)
}

extension Equatable {
    /// Whether `other` is a `Self` equal to this value.
    fileprivate func isEqual(toAny other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

// MARK: - Observable objects

/// The key an `@Observable` object is published and read under, by its type —
/// what `.focusedValue(_ object:)` and `@FocusedValue(Model.self)` use.
enum FocusedObjectKey<Object: AnyObject>: FocusedValueKey {
    typealias Value = Object
}
