//  🖥️ TUI — A Terminal UI framework for Swift
//  PushedNavigationValue.swift
//
//  A value on a navigation path, with the type it was pushed as where that is
//  not its own.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Erasing a pushed value

/// How a value goes onto a navigation path, and how the stack reads it back.
///
/// SwiftUI finds a pushed value's destination by the type the value was pushed
/// AS, not the type it is: a `Circle` subclass of a `Hashable` class `Shape`,
/// pushed as a `Shape` (`path.append(circle as Shape)`, a `[Shape]` path,
/// `NavigationLink(value: circle as Shape)`), shows
/// `navigationDestination(for: Shape.self)`, and one appended as a `Circle`
/// shows none (measured,
/// `Tools/SwiftUIProbes/Navigation identities (H-69)/navident.out`, case 2).
/// `AnyHashable` keeps only the dynamic type, so the stack looked the value up
/// as a `Circle` and showed an empty screen.
///
/// So where the two differ, which takes a class pushed as one of its
/// superclasses, the value is wrapped in a ``StaticallyTyped`` that names the
/// type it was pushed as. Every other value, which is nearly all of them, goes
/// on the path as a plain `AnyHashable` exactly as before: no box, no cost.
enum PushedNavigationValue {

    /// `value`, erased for a navigation path, remembering `V` when it is not
    /// `value`'s own type.
    static func erase<V: Hashable>(_ value: V) -> AnyHashable {
        // Not `value is V`, which is always true: whether the dynamic type IS
        // the static one. Equal for every struct and enum, and for a class
        // instance of exactly the class named.
        if type(of: value) == V.self { return AnyHashable(value) }
        return AnyHashable(StaticallyTyped(value: value))
    }

    /// The app's own value, unwrapped from a ``StaticallyTyped`` if it is one.
    static func value(of element: AnyHashable) -> AnyHashable {
        (element.base as? any StaticallyTypedValue)?.erasedValue ?? element
    }

    /// The type a destination is looked up by: the type `element` was pushed
    /// as. A plain value's own type, where it was pushed as that or arrived
    /// with no static type to go by (a ``NavigationPath`` decoded from its
    /// ``NavigationPath/codable``, whose types are the values' own).
    static func lookupType(of element: AnyHashable) -> ObjectIdentifier {
        (element.base as? any StaticallyTypedValue)?.pushedType ?? ObjectIdentifier(type(of: element.base))
    }

    /// A value pushed as `Value`, a type other than its own.
    ///
    /// Equal only to another pushed as the same type: `circle as Shape` and
    /// `circle` are two different elements of a path, as they show two
    /// different destinations.
    struct StaticallyTyped<Value: Hashable>: Hashable, StaticallyTypedValue {
        let value: Value

        var pushedType: ObjectIdentifier { ObjectIdentifier(Value.self) }
        var erasedValue: AnyHashable { AnyHashable(value) }
    }
}

/// What the stack reads of a ``PushedNavigationValue/StaticallyTyped`` whose
/// `Value` it does not know.
protocol StaticallyTypedValue {
    /// The type the value was pushed as.
    var pushedType: ObjectIdentifier { get }
    /// The value, erased as its own type.
    var erasedValue: AnyHashable { get }
}
