//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

// MARK: - Environment Key Protocol

/// A key for accessing values in the environment.
///
/// Conform to this protocol to define custom environment values.
///
/// # Example
///
/// ```swift
/// struct MyCustomKey: EnvironmentKey {
///     static var defaultValue: String = "default"
/// }
///
/// extension EnvironmentValues {
///     var myCustomValue: String {
///         get { self[MyCustomKey.self] }
///         set { self[MyCustomKey.self] = newValue }
///     }
/// }
/// ```
public protocol EnvironmentKey {
    /// The type of value stored by this key.
    associatedtype Value

    /// The default value for this key.
    static var defaultValue: Value { get }
}

// MARK: - Render comparison markers

/// An environment key whose value a render below it cannot draw differently
/// for: a per-walk channel (the dispatchers, the focus manager), a mailbox a
/// view posts into and never draws from (the volatile-read tracker), a
/// service mirrored onto the render context (the render cache). An
/// `EnvironmentStamp` skips it, so two environments that differ only in such
/// keys compare equal. Declared at the key, so nobody building a cache can
/// leave one out; `EnvironmentStampTests` lists every conformer with why.
package protocol _RenderNeutralEnvironmentKey {}

/// A framework environment value whose `==` is not what a render below it
/// depends on — partial on purpose, or a class whose drawn state changes in
/// place — and so says what a stamp compares instead: its projection, or
/// `nil` when nothing about it can be compared (Option C, C2b).
package protocol _EnvironmentRenderComparing {
    /// What a render below depends on, or `nil` when that cannot be compared.
    var renderProjection: (any Equatable)? { get }
}

// MARK: - Environment Values

/// A collection of environment values propagated through the view hierarchy.
///
/// Environment values flow down from parent views to child views.
/// Each view can read environment values and optionally override them
/// for its children.
public struct EnvironmentValues: @unchecked Sendable {
    /// Storage for environment values.
    ///
    /// `@usableFromInline` for the key subscript's getter, which is inlined
    /// into every accessor — see the note there.
    @usableFromInline var storage: [ObjectIdentifier: Any] = [:]

    /// Creates an empty environment values container.
    public init() {}

    /// Accesses the environment value for the given key.
    ///
    /// - Parameter key: The type of the environment key.
    /// - Returns: The value for the key, or its default value if not set.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        // Inlinable, so each accessor — `EnvironmentValues.lineLimit` and the
        // rest, all in other modules — gets a copy specialised to its key.
        // Unspecialised, the `as?` below makes a `K.Value?` whose metadata
        // the runtime looked up on EVERY read, hit or miss, at the getter's
        // entry: 16.6% of a frame of the `scrolleager` scenario, 9% of
        // `controls`/`tap`. A pattern cast instead still looked it up.
        @inlinable get {
            // Unwrap the STORAGE lookup before the cast. Doing it in one step
            // — `storage[…] as? K.Value` — reads correctly and is wrong for
            // every Optional-valued key: a miss gives `Optional<Any>.none`,
            // which casts *successfully* to `Optional<Wrapped>.none`, so the
            // `if let` binds a nil value and `defaultValue` is never reached.
            // Silently, because the only observable difference is a default
            // nobody could see was being ignored. Every Optional key in the
            // tree happens to default to nil, so nothing was wrong today —
            // but the next one to want a real default would have got nil and
            // no diagnostic.
            guard let boxed = storage[ObjectIdentifier(key)] else {
                return K.defaultValue
            }
            // A value that WAS stored, including one deliberately set to nil,
            // is what the caller asked for.
            if let value = boxed as? K.Value {
                return value
            }
            return K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    /// Accesses an observable object stored by its type.
    ///
    /// Objects stored via `.environment(model)` are keyed by
    /// `ObjectIdentifier(type(of: object))`, enabling type-based lookup
    /// via `@Environment(MyModel.self)`.
    ///
    /// - Parameter type: The observable object's type.
    /// - Returns: The stored object, or `nil` if not set.
    public subscript<T: Observable>(observable type: T.Type) -> T? {
        get { storage[ObjectIdentifier(type)] as? T }
        set { storage[ObjectIdentifier(type)] = newValue }
    }

    /// The object stored under `type`, looked up without knowing the type
    /// statically — the untyped twin of ``subscript(observable:)``.
    ///
    /// It exists so `@Environment(SomeModel.self)` can hold a **metatype** for
    /// its lookup instead of a closure that captures one. That is not a style
    /// preference: a closure is two words, which pushed the property wrapper to
    /// 32 bytes, past the three-word inline buffer of an existential — and the
    /// renderer projects every `@Environment` property through `Any` to resolve
    /// it, so every such property of every view was paying a heap box on every
    /// body. With a metatype the wrapper is 16 bytes and the box is inline.
    ///
    /// - Parameter type: The observable type to look up.
    /// - Returns: The stored object, or `nil` if none was injected.
    public func storedObject(ofType type: Any.Type) -> Any? {
        storage[ObjectIdentifier(type)]
    }

    /// Every value set in this environment, by its key's identity: what an
    /// `EnvironmentStamp` is built from. A copy of the storage, which is
    /// copy-on-write, so it costs a retain.
    package var storedValues: [ObjectIdentifier: Any] { storage }

    /// The storage's own word — a native `Dictionary` is one pointer to its
    /// buffer — which names this environment's storage for as long as some
    /// copy of it is alive. Two environments that share it are the same
    /// values; the converse does not hold. A per-pass memo keyed by it must
    /// keep the environment alive for the pass, or a freed buffer's address
    /// can come back for another. `EnvironmentStampTests` pins the size.
    /// A data buffer's address, never a function's, so deduplication cannot
    /// make two share it.
    package var storageWord: UInt { unsafeBitCast(storage, to: UInt.self) }  // swiftlint:disable:this function_address_identity

    /// Creates a copy of this environment with a modified value.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the value to modify.
    ///   - value: The new value.
    /// - Returns: A new EnvironmentValues with the modified value.
    public func setting<V>(_ keyPath: WritableKeyPath<Self, V>, to value: V) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}

extension EnvironmentValues: CustomStringConvertible {
    /// The values set in this environment, each described by itself.
    ///
    /// SwiftUI's lists every key by name. Here a key is stored by its type's
    /// identity alone, which has no printable name, so the values are listed,
    /// sorted so that two equal environments describe alike. A key at its
    /// default value is not listed: it was never set.
    public var description: String {
        "[" + storage.values.map { String(describing: $0) }.sorted().joined(separator: ", ") + "]"
    }
}
