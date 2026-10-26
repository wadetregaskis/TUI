//  🖥️ TUI — A Terminal UI framework for Swift
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

extension InterpolatedNumber {
    /// `value` as a key keeps it, to be written in the locale the key is read
    /// in: a signed integer widened to `Int64`, an unsigned one to `UInt64`,
    /// a `Float` or a `CGFloat` to `Double` (whose six fraction digits at most
    /// write a `Float`'s `0.1` as `0.1`).
    ///
    /// By casts, not a requirement of ``_FormatSpecifiable``, whose
    /// requirements are SwiftUI's: an `Int` and a `Double` first, the
    /// commonest, and then by the type of ``_FormatSpecifiable/_arg``, which
    /// C's promotion has already narrowed to six. A cast of a value whose type
    /// is known at run time is a type comparison, nanoseconds.
    init<T: _FormatSpecifiable>(_ value: T) {
        if let integer = value as? Int {
            self = .signed(Int64(integer))
            return
        }
        if let double = value as? Double {
            self.init(double)
            return
        }
        switch value._arg {
        case let integer as Int64: self = .signed(integer)
        case let integer as Int32: self = .signed(Int64(integer))
        case let integer as UInt64: self = .unsigned(integer)
        case let integer as UInt32: self = .unsigned(UInt64(integer))
        case let float as Float: self.init(Double(float))
        case let float as CGFloat: self.init(Double(float))
        default: self = .verbatim(String(describing: value))
        }
    }
}

extension InterpolatedNumber {
    /// `value` as `\(value, specifier:)` keeps it: the printf conversion the
    /// interpolation named and the value at the width C's variadic promotion
    /// gives it (``_FormatSpecifiable/_arg``), to be written in the locale
    /// the key is read in.
    ///
    /// A value whose ``_FormatSpecifiable/_arg`` is none of the standard
    /// library's (only a conformance of an app's own makes one) is written at
    /// once in the process's locale, as every specifier was before they
    /// followed `\.locale`.
    init<T: _FormatSpecifiable>(_ value: T, specifier: String) {
        switch value._arg {
        case let integer as Int64: self = .specified(specifier, .int64(integer))
        case let integer as Int32: self = .specified(specifier, .int32(integer))
        case let integer as UInt64: self = .specified(specifier, .uint64(integer))
        case let integer as UInt32: self = .specified(specifier, .uint32(integer))
        case let double as Double: self = .specified(specifier, .double(bitPattern: double.bitPattern))
        case let float as Float: self = .specified(specifier, .double(bitPattern: Double(float).bitPattern))
        case let float as CGFloat: self = .specified(specifier, .double(bitPattern: Double(float).bitPattern))
        default: self = .verbatim(String(format: specifier, locale: .current, value._arg))
        }
    }
}
