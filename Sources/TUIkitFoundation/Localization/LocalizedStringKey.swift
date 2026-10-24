//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKey.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - LocalizedStringKey

/// The key for a localized string. Matches SwiftUI's type of the same name.
///
/// ```swift
/// Text("button.save")            // looked up; falls back to "button.save"
/// Text("Hello, \(name)!")        // key "Hello, %@!", then substituted
/// Text(someString)               // NOT looked up — see below
/// ```
///
/// ## Why a string literal is a key and a `String` is not
///
/// This is SwiftUI's rule, and it falls out of overload resolution rather than
/// from anything magic: ``Text`` has one initializer taking a
/// `LocalizedStringKey` and another generic over `StringProtocol`, and Swift
/// prefers the concrete one for a literal. So a literal is a key; a `String`
/// you computed is content. ``Text/init(verbatim:)`` opts a literal
/// out.
///
/// Lookup goes through ``LocalizationService``, which falls back to English and
/// then to the key itself — so an app that never registers a translation sees
/// exactly the literal it wrote, which is what makes adopting this
/// behaviour-preserving. TUIkit's own keys are dot-separated
/// (`button.save`), so ordinary prose cannot collide with one by accident.
///
/// ## Interpolation
///
/// An interpolated literal becomes a key with `%@` where each value went, so
/// one entry in the table serves every value — and a translation can reorder
/// them with the positional form:
///
/// ```swift
/// Text("Moved \(count) rows to \(destination)")
/// // key: "Moved %@ rows to %@"
/// // de:  "%2$@ um %1$@ Zeilen erweitert"
/// ```
///
/// Values are converted to text **eagerly**, at the point of interpolation, the
/// same way `Text(_:format:)` formats eagerly — so
/// `\(value, format: .percent)` works and the result is a plain, `Sendable`
/// key.
///
/// > Note: A key with **no** interpolations is never scanned for placeholders,
///   so `Text("100% done")` says exactly that. Scanning only happens when there
///   is something to substitute, and an unrecognised `%` sequence is passed
///   through either way.
///
/// A key is looked up as the app's own, language by language: in the strings
/// the app registered, then the main bundle's `Localizable.strings`, as
/// SwiftUI looks it up, then TUIkit's own strings;
/// ``Text/init(_:tableName:bundle:comment:)`` names another table or bundle,
/// read first. See ``LocalizationService/string(for:)-(String)``.
public struct LocalizedStringKey: Equatable, Hashable, Sendable {
    /// The lookup key: the literal, with `%@` where each interpolation was.
    package let key: String

    /// The key as SwiftUI spells it, where that differs from ``key``: each
    /// interpolated number as the printf conversion SwiftUI writes for its type
    /// (`%lld` for an `Int`, `%lf` for a `Double`, `%d` for an `Int32`, …) and a
    /// `specifier:` as it was written, where ``key`` has `%@` for every value
    /// (`Tools/SwiftUIProbes/Localization keys/keys.out`). A String Catalog
    /// extracted from SwiftUI code is keyed this way, so it is looked up first;
    /// `nil` when every value is `%@` in SwiftUI's key too.
    package let swiftUIKey: String?

    /// The interpolated values, already converted to text.
    package let arguments: [String]

    /// The arguments that read the clock, by their index in ``arguments`` —
    /// `\(date, style: .relative)` and the other live interpolations — whose
    /// entry there is their reading when the key was built. Empty for almost
    /// every key; see `LocalizedStringKey+Live.swift`.
    let liveArguments: [Int: LiveTextBox]

    /// The interpolated `Text`s that bring styling of their own, by their
    /// index in ``arguments``, whose entry there is their plain words. A `Text`
    /// made from the key splices their runs in where their placeholders stand
    /// (``Text/markdownRuns(in:key:)``); everything else that takes the key —
    /// a button's title — reads the words. Empty for almost every key.
    let styledArguments: [Int: StyledArgument]

    /// Creates a key from a string.
    ///
    /// - Parameter value: The key to look up.
    public init(_ value: String) {
        self.key = value
        self.swiftUIKey = nil
        self.arguments = []
        self.liveArguments = [:]
        self.styledArguments = [:]
    }

    init(
        key: String, swiftUIKey: String? = nil, arguments: [String], liveArguments: [Int: LiveTextBox] = [:],
        styledArguments: [Int: StyledArgument] = [:]
    ) {
        self.key = key
        self.swiftUIKey = swiftUIKey
        self.arguments = arguments
        self.liveArguments = liveArguments
        self.styledArguments = styledArguments
    }

    /// The localized text: the key resolved against `service`, with any
    /// interpolated values substituted into it.
    ///
    /// - Parameter service: Where to look the key up.
    /// - Returns: The text to display.
    package func resolved(with service: LocalizationService) -> String {
        let template = service.string(for: key, swiftUIKey: swiftUIKey, tableName: nil, bundle: nil)
        guard !arguments.isEmpty else { return template }
        return Self.substituting(arguments, into: template)
    }

    /// The localized text, resolved through the shared service.
    ///
    /// Every control that takes a title resolves **eagerly**, at construction,
    /// exactly as ``Text/init(_:tableName:bundle:comment:)`` does — which is what
    /// lets a control keep storing a plain `String` and changes nothing about
    /// how it measures or renders. Nothing is lost by resolving early: the view
    /// tree is rebuilt every frame, so a language switched at runtime is picked
    /// up on the next one.
    ///
    /// It is public so your own controls can take a `LocalizedStringKey` and
    /// follow the same rule:
    ///
    /// ```swift
    /// struct FieldRow: View {
    ///     let label: String
    ///
    ///     init(_ labelKey: LocalizedStringKey) { self.init(labelKey.localized) }
    ///
    ///     @_disfavoredOverload
    ///     init<S: StringProtocol>(_ label: S) { self.label = String(label) }
    ///
    ///     var body: some View { Text(label.padded(to: 20)) }
    /// }
    /// ```
    ///
    /// > Important: Write the disfavoured twin **generic over `StringProtocol`**,
    ///   as SwiftUI does, not as a concrete `String`. `@_disfavoredOverload`
    ///   alone is not enough: Swift 6.3 ranks a concrete `String` parameter
    ///   above `LocalizedStringKey` for a literal anyway once the initializer
    ///   takes another required argument, so the literal stops being a key with
    ///   no diagnostic. Swift 6.2 did not, which is how the concrete spelling
    ///   shipped working and later broke — see `SwiftUI compatibility guide.md` §4a.
    ///   The generic spelling is correct on both.
    ///
    /// SwiftUI has no equivalent — its `LocalizedStringKey` is opaque, and a
    /// component is expected to hand it straight to a `Text`. A terminal UI
    /// needs the `String`: text is laid out in cells, so padding, truncating
    /// and column alignment all happen on the resolved text.
    public var localized: String {
        resolved(with: LocalizationService.shared)
    }

    /// Whether `character` is a C length modifier (`%ld`, `%zu`, …), which a
    /// translation may carry over and which carries no meaning here.
    ///
    /// - Note: A `switch` rather than `"hlLqzjt".contains(character)`. That
    ///   spelling **scans a `String`** — a fresh one per call, compared
    ///   grapheme by grapheme — and this runs per conversion of every
    ///   interpolated `Text`, on every frame.
    private static func isLengthModifier(_ character: Character) -> Bool {
        switch character {
        case "h", "l", "L", "q", "z", "j", "t": return true
        default: return false
        }
    }

    /// Whether `character` terminates a conversion — `%@` and the numeric
    /// forms a translator might reasonably write. A `switch` for the same
    /// reason as ``isLengthModifier(_:)``.
    private static func isConversion(_ character: Character) -> Bool {
        switch character {
        case "@", "d", "i", "u", "f", "g", "G", "e", "E", "x", "X", "o", "s": return true
        default: return false
        }
    }

    /// printf's `-` flag and the digits after it, read from `cursor` and
    /// leaving it past them. The digits are a position if a `$` follows and a
    /// width otherwise; that is the caller's call, which is why they come
    /// back as text.
    private static func scanFlagAndDigits(
        _ template: String, from cursor: inout String.Index
    ) -> (leftAligned: Bool, digits: String) {
        var leftAligned = false
        if cursor < template.endIndex, template[cursor] == "-" {
            leftAligned = true
            cursor = template.index(after: cursor)
        }
        var digits = ""
        while cursor < template.endIndex, template[cursor].isNumber {
            digits.append(template[cursor])
            cursor = template.index(after: cursor)
        }
        return (leftAligned, digits)
    }

    /// One conversion in a template — `%@`, `%2$@`, `%3d` — and how to fill
    /// it: which argument, and the width a printf width pads it to.
    struct Placeholder: Hashable, Sendable {
        /// The argument it takes, counting from zero.
        let argument: Int
        /// The cells a width pads the value to, or `nil` for none.
        let width: Int?
        /// Whether the padding goes after the value (printf's `-`).
        let leftAligned: Bool

        /// `value` padded to the width, if there is one.
        ///
        /// A width is a COLUMN count — every other padding site here measures
        /// cells — so a CJK or emoji argument is padded by what it occupies,
        /// not by its grapheme count.
        func filled(with value: String) -> String {
            guard let width else { return value }
            let cells = value.strippedLength
            guard cells < width else { return value }
            let pad = String.spaces(width - cells)
            return leftAligned ? value + pad : pad + value
        }
    }

    /// Replaces `%@` / `%N$@` (and the numeric conversions a translator might
    /// reasonably write) in `template` with `arguments`.
    ///
    /// Anything unrecognised is emitted verbatim, so a stray `%` in a
    /// translation degrades to itself rather than eating the character after
    /// it. `package` for the menu bar's items (TUIkitCommands), whose titles
    /// name the app.
    package static func substituting(_ arguments: [String], into template: String) -> String {
        if let plain = substitutingBarePlaceholders(arguments, into: template) { return plain }
        return substitutingByWalk(arguments, into: template)
    }

    /// ``substituting(_:into:)`` by ``walk(_:text:placeholder:)``: every
    /// template, every conversion it reads.
    static func substitutingByWalk(_ arguments: [String], into template: String) -> String {
        var result = ""
        walk(
            template, text: { result.append($0) },
            placeholder: { placeholder in
                if arguments.indices.contains(placeholder.argument) {
                    result += placeholder.filled(with: arguments[placeholder.argument])
                }
            })
        return result
    }

    /// ``substituting(_:into:)`` for the commonest template — all ASCII,
    /// every `%` a bare `%@`, which is every interpolated key an app builds
    /// with no translation registered — or `nil` for any other.
    ///
    /// For such a template the walk's answer is fixed: its text segments
    /// as they are, with `arguments[n]` for the n-th `%@` (nothing when there
    /// is no such argument), since a bare `%@` has no width to pad to. This
    /// answers that from the bytes in one pass, where the walk compares and
    /// appends Character by Character — a grapheme break per character, ~40
    /// µs/frame on a dashboard of interpolated labels. It is NOT a second
    /// reading of the template: on the first byte that is not ASCII, or a
    /// `%` not followed by `@` (`%%`, `%2$@`, `%d`, a trailing `%`), it
    /// gives up and the walk reads the whole template, as it always did.
    /// In ASCII every byte is a Character boundary either side of a `%@`
    /// (only CR LF joins two bytes into one), so the segments cut here are
    /// the walk's Characters, byte for byte.
    static func substitutingBarePlaceholders(_ arguments: [String], into template: String) -> String? {
        let utf8 = template.utf8
        var result = ""
        var next = 0
        var segmentStart = utf8.startIndex
        var index = segmentStart
        while index != utf8.endIndex {
            let byte = utf8[index]
            guard byte < 0x80 else { return nil }
            guard byte == UInt8(ascii: "%") else {
                index = utf8.index(after: index)
                continue
            }
            let conversion = utf8.index(after: index)
            guard conversion != utf8.endIndex, utf8[conversion] == UInt8(ascii: "@") else { return nil }
            result += template[segmentStart..<index]
            if arguments.indices.contains(next) { result += arguments[next] }
            next += 1
            index = utf8.index(after: conversion)
            segmentStart = index
        }
        result += template[segmentStart...]
        return result
    }

    /// Walks `template`, handing each character of text to `text` and each
    /// conversion to `placeholder`, in order.
    ///
    /// The one reading of a template's conversions, so the plain substitution
    /// and a `Text`'s Markdown parse cannot disagree about which argument goes
    /// where. `%%` is text (one `%`); anything that is not a conversion is text
    /// too, character by character.
    static func walk(
        _ template: String, text: (Character) -> Void, placeholder: (Placeholder) -> Void
    ) {
        var next = 0
        var index = template.startIndex

        while index < template.endIndex {
            guard template[index] == "%" else {
                text(template[index])
                index = template.index(after: index)
                continue
            }
            var cursor = template.index(after: index)
            guard cursor < template.endIndex else {
                text("%")
                break
            }
            // `%%` is an escaped percent.
            if template[cursor] == "%" {
                text("%")
                index = template.index(after: cursor)
                continue
            }
            // An explicit position: `%2$@` takes the second argument, which is
            // how a translation reorders them.
            var position: Int?
            // A `-` before the digits is printf's left-align flag; with a
            // width it changes which side the padding lands on.
            let scanned = Self.scanFlagAndDigits(template, from: &cursor)
            var leftAligned = scanned.leftAligned
            let digits = scanned.digits
            var width: Int?
            if !digits.isEmpty, cursor < template.endIndex, template[cursor] == "$",
                !leftAligned
            {
                position = Int(digits)
                cursor = template.index(after: cursor)
                // printf permits the flags and width AFTER a position too —
                // `%2$3d`, `%1$-6@` — and a scan that stopped at the `$`
                // rejected the `3` as the conversion, emitted the `%` verbatim
                // and dropped the argument. The same scan, once more; the
                // digits here can only be a width.
                let after = Self.scanFlagAndDigits(template, from: &cursor)
                leftAligned = after.leftAligned
                width = Int(after.digits)
            } else if !digits.isEmpty {
                // Digits that were not a position are a WIDTH — `%3d`. The
                // cursor already sits past them; remember the width rather
                // than rewinding onto digits the conversion scan cannot cross
                // — which emitted `%3d` verbatim AND left the implicit
                // argument cursor unadvanced, shifting every later argument
                // into the wrong placeholder.
                width = Int(digits)
            }
            // A precision (`%.2f`): parsed past so the conversion is still
            // recognised; the argument arrives pre-formatted, so it is not
            // applied.
            if cursor < template.endIndex, template[cursor] == "." {
                cursor = template.index(after: cursor)
                while cursor < template.endIndex, template[cursor].isNumber {
                    cursor = template.index(after: cursor)
                }
            }
            // Length modifiers a translator may carry over from a C format.
            while cursor < template.endIndex, Self.isLengthModifier(template[cursor]) {
                cursor = template.index(after: cursor)
            }
            guard cursor < template.endIndex, Self.isConversion(template[cursor]) else {
                // Not a conversion at all: emit the `%` and carry on from the
                // character after it, so nothing is swallowed.
                text("%")
                index = template.index(after: index)
                continue
            }
            let argumentIndex = position.map { $0 - 1 } ?? next
            if argumentIndex >= 0 {
                placeholder(Placeholder(argument: argumentIndex, width: width, leftAligned: leftAligned))
            }
            // A positional reference does not advance the implicit cursor —
            // that is what lets a translation use %1$@ twice.
            if position == nil { next += 1 }
            index = template.index(after: cursor)
        }
    }
}

// MARK: - Literals and interpolation

extension LocalizedStringKey: ExpressibleByStringInterpolation {
    // The literal types, named as SwiftUI names them: every kind of literal
    // arrives as a `String`.
    public typealias StringLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias UnicodeScalarLiteralType = String

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(
            key: stringInterpolation.key, swiftUIKey: stringInterpolation.swiftUIKey,
            arguments: stringInterpolation.arguments,
            liveArguments: stringInterpolation.liveArguments,
            styledArguments: stringInterpolation.styledArguments)
    }

    /// Builds the key and its arguments as the literal is written.
    public struct StringInterpolation: StringInterpolationProtocol {
        /// The type of the literal segments between interpolations.
        public typealias StringLiteralType = String

        var key = ""
        /// ``LocalizedStringKey/swiftUIKey`` as it is built: `nil` until a
        /// value whose conversion in SwiftUI's key is not `%@` arrives, then
        /// ``key`` so far with that conversion, and kept in step from there.
        var swiftUIKey: String?
        var arguments: [String] = []
        var liveArguments: [Int: LiveTextBox] = [:]
        var styledArguments: [Int: StyledArgument] = [:]

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            // A literal `%` has to be escaped, because the key it lands in is
            // printf-shaped: the interpolations around it are `%@`, and
            // `substituting(_:into:)` reads `%%` as one percent. Written
            // through unescaped, `"Save \(n)%\(unit)"` built the key
            // `%@%%@` — whose `%%` is an escaped percent and whose trailing
            // `@` is a stray literal — so the SECOND argument was silently
            // dropped and an `@` appeared in its place. The neighbouring
            // `"\(n)% done"` was fine, which is what kept this hidden: only a
            // percent immediately before an interpolation collides.
            //
            // The test is a BYTE scan first. `literal.contains("%")` binds to
            // Foundation's generic substring search — a grapheme-wise
            // `_range(of:)`, about 85 ns for a literal of a few bytes — and it
            // runs for every literal segment of every interpolated key built,
            // every frame. A literal can only contain the `%` Character if it
            // holds the 0x25 byte (U+0025 has no canonical equivalent), so the
            // byte scan only skips searches that would answer no; whenever
            // the byte is there, Foundation still decides, as before.
            if literal.utf8.contains(UInt8(ascii: "%")), literal.contains("%") {
                let escaped = literal.replacingOccurrences(of: "%", with: "%%")
                key += escaped
                swiftUIKey? += escaped
            } else {
                key += literal
                swiftUIKey? += literal
            }
        }

        /// Appends the placeholder of one interpolated value: `%@` to ``key``,
        /// and `conversion` — what SwiftUI's key holds for it — to
        /// ``swiftUIKey``, which starts as a copy of ``key`` the first time the
        /// two differ.
        mutating func appendPlaceholder(_ conversion: String) {
            if swiftUIKey == nil, conversion != "%@" { swiftUIKey = key }
            key += "%@"
            swiftUIKey? += conversion
        }

        /// Interpolates any other value, as `String(describing:)` renders it —
        /// mirrors SwiftUI's catch-all, deprecated as SwiftUI's is, with its
        /// message.
        ///
        /// SwiftUI added this overload to the macOS 26 SDK already deprecated:
        /// it compiles, so that `Text("\(value)")` keeps building, and warns
        /// that what it draws is the value's debug description, which no
        /// translation can reach. A type SwiftUI interpolates has an overload
        /// of its own (`LocalizedStringKey+Interpolation.swift`), which wins
        /// because this one is disfavoured; anything else lands here — an
        /// `Optional`, an enum, a value typed `Any` whatever it holds — with
        /// `%@` in both keys, as in SwiftUI. To say what is meant, interpolate
        /// a `String` (`\(String(describing: value))`, `\(value.name)`), a
        /// format style, or a `Text`.
        ///
        /// (Owner ruling DEPR-CATCHALL (b), 2026-10-23: typed overloads, then
        /// the catch-all deprecated as SwiftUI's is.)
        @available(
            *, deprecated,
            message: """
                Localized string interpolation produces an unlocalized, debug description for this type of value. \
                Use a type supported by LocalizedStringKey.StringInterpolation or initialize a \
                LocalizedStringResource instead with an interpolated value that conforms to \
                CustomLocalizedStringResourceConvertible.
                """
        )
        @_disfavoredOverload
        public mutating func appendInterpolation<T>(_ object: T) {
            appendInterpolation(String(describing: object))
        }
    }
}
