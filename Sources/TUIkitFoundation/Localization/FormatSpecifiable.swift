//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormatSpecifiable.swift
//
//  The numbers a `LocalizedStringKey` interpolates as numbers: SwiftUI's
//  `_FormatSpecifiable` and its conformances, declared as SwiftUICore
//  declares them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A number that a localized string interpolates through a printf conversion —
/// mirrors SwiftUI's `_FormatSpecifiable`.
///
/// Public only because `LocalizedStringKey.StringInterpolation`'s
/// `appendInterpolation(_:)` and `appendInterpolation(_:specifier:)` are
/// generic over it, as SwiftUI's are; the underscore says what SwiftUI's says,
/// that it is not for conforming to. The standard library's integers and
/// floating-point numbers, and `CGFloat`, conform.
public protocol _FormatSpecifiable: Equatable {
    /// The value as it is passed to a printf conversion.
    associatedtype _Arg: CVarArg

    /// The value as it is passed to a printf conversion: an `Int` widened to
    /// `Int64`, an `Int8` to `Int32`, as C's variadic promotion widens them.
    var _arg: _Arg { get }

    /// The printf conversion that formats the value whole: `%lld` for an
    /// `Int`, `%lf` for a `Double`.
    var _specifier: String { get }
}

extension Int: _FormatSpecifiable {
    public var _arg: Int64 { Int64(self) }
    public var _specifier: String { "%lld" }
}

extension Int8: _FormatSpecifiable {
    public var _arg: Int32 { Int32(self) }
    public var _specifier: String { "%d" }
}

extension Int16: _FormatSpecifiable {
    public var _arg: Int32 { Int32(self) }
    public var _specifier: String { "%d" }
}

extension Int32: _FormatSpecifiable {
    public var _arg: Int32 { self }
    public var _specifier: String { "%d" }
}

extension Int64: _FormatSpecifiable {
    public var _arg: Int64 { self }
    public var _specifier: String { "%lld" }
}

extension UInt: _FormatSpecifiable {
    public var _arg: UInt64 { UInt64(self) }
    public var _specifier: String { "%llu" }
}

extension UInt8: _FormatSpecifiable {
    public var _arg: UInt32 { UInt32(self) }
    public var _specifier: String { "%u" }
}

extension UInt16: _FormatSpecifiable {
    public var _arg: UInt32 { UInt32(self) }
    public var _specifier: String { "%u" }
}

extension UInt32: _FormatSpecifiable {
    public var _arg: UInt32 { self }
    public var _specifier: String { "%u" }
}

extension UInt64: _FormatSpecifiable {
    public var _arg: UInt64 { self }
    public var _specifier: String { "%llu" }
}

extension Float: _FormatSpecifiable {
    public var _arg: Float { self }
    public var _specifier: String { "%f" }
}

extension Double: _FormatSpecifiable {
    public var _arg: Double { self }
    public var _specifier: String { "%lf" }
}

extension CGFloat: _FormatSpecifiable {
    public var _arg: CGFloat { self }
    public var _specifier: String { "%lf" }
}
