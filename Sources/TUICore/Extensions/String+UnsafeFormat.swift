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
    /// On Darwin it formats as Foundation's own `String(format:)` does, through
    /// `withVaList` and `NSString(format:arguments:)`, rather than calling it:
    /// whether `String(format:)` is unsafe is the SDK's to say, not the
    /// compiler's or the platform's. The macOS 26 SDK's Foundation marks it,
    /// and the macOS 15 SDK's doesn't, which is the one a swift.org toolchain
    /// builds against with only the Command Line Tools installed; there an
    /// `unsafe` on the call was "no unsafe operations occur within 'unsafe'
    /// expression", twice, for every app that depends on TUI. A
    /// `CVaListPointer` is unsafe in every standard library since 6.2, so the
    /// `unsafe` on its use is needed whichever SDK it builds against.
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
            self = unsafe withVaList(arguments) { unsafe NSString(format: format, arguments: $0) as String }
        #else
            self = String(format: format, arguments: arguments)
        #endif
    }

    /// `String(format:locale:_:)`, declared `@unsafe` on every platform: see
    /// ``init(unsafeFormat:_:)``.
    @unsafe package init(unsafeFormat format: String, locale: Locale?, _ arguments: any CVarArg...) {
        #if canImport(Darwin)
            self = unsafe withVaList(arguments) {
                unsafe NSString(format: format, locale: locale as NSLocale?, arguments: $0) as String
            }
        #else
            self = String(format: format, locale: locale, arguments: arguments)
        #endif
    }
}
