//  🖥️ TUI — A Terminal UI framework for Swift
//  String+UnsafeFormat.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Formatting with C varargs, unsafe on every platform

extension String {
    /// `String(format:_:)`, declared `@unsafe` on every platform.
    ///
    /// A printf format reads its arguments by the conversions it names, so a
    /// format that names more than it is given, or the wrong kind, reads memory
    /// it shouldn't: unsafe, which strict memory safety (SE-0458) asks every
    /// call to say with `unsafe`. Apple's Foundation declares `String(format:)`
    /// unsafe and swift-corelibs-foundation doesn't, so the same `unsafe` that
    /// Swift 6.4 on macOS needs is an "unnecessary `unsafe`" warning on Linux and
    /// WebAssembly: 515 of them, the first time the package marked its calls.
    /// Calling through this, which is unsafe everywhere, makes one spelling
    /// right on every platform. It is not a way around the check: the
    /// declaration says unsafe, so every caller still marks it.
    ///
    /// The last resort, not the way to write a number: a fixed number of
    /// digits is a `FormatStyle` (`.number.precision(.fractionLength(2))`
    /// for a person, `.fixed(_:)` for a program), a width or a
    /// radix `digits(width:radix:uppercase:padding:)`, and a
    /// translation's `%@` `LocalizedStringKey.substituting(_:into:)`. What is
    /// left needs printf itself: a format chosen at run time (`Text`'s
    /// `specifier:`, which SwiftUI documents as a printf format) and C's `%g`
    /// (`Path`'s description), whose switch to an exponent by magnitude no
    /// `FormatStyle` writes.
    ///
    /// The package's own; not public API.
    @unsafe package init(unsafeFormat format: String, _ arguments: any CVarArg...) {
        #if canImport(Darwin)
            self = unsafe String(format: format, arguments: arguments)
        #else
            self = String(format: format, arguments: arguments)
        #endif
    }

    /// `String(format:locale:_:)`, declared `@unsafe` on every platform: see
    /// ``init(unsafeFormat:_:)``.
    @unsafe package init(unsafeFormat format: String, locale: Locale?, _ arguments: any CVarArg...) {
        #if canImport(Darwin)
            self = unsafe String(format: format, locale: locale, arguments: arguments)
        #else
            self = String(format: format, locale: locale, arguments: arguments)
        #endif
    }
}
