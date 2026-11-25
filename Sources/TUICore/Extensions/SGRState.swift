//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRState.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The styling a run of SGR escapes leaves a terminal in, and the shortest
/// sequence that reproduces it.
///
/// ## Why this exists
///
/// "Restore the styling in force at column N" was answered by CONCATENATING
/// every SGR escape before that column and letting the terminal net them. That
/// is correct — an open and its reset cancel — and it is catastrophic when the
/// answer is itself written back into the line.
///
/// `FrameBuffer.insertOverlay` does exactly that: it rebuilds a row as
/// `prefix + overlay + <style at the suffix> + suffix`. Composite a second
/// child into the same row and the style it replays now includes the first
/// child's replay; a third includes the second's, which included the first's.
/// The row DOUBLES per child. Measured on the Example's Layout page, whose
/// custom `Flow` packs ~19 chips onto one line: **1,015,906 bytes for 129
/// visible cells** — 3,942 bytes per cell, against 3.8 for the same chips one
/// per row. A megabyte of escapes for one row is why that page could be watched
/// painting cell by cell.
///
/// Netting the escapes into a state and emitting it once bounds the replay to a
/// handful of codes no matter how many children a row carries.
///
/// ## What is preserved
///
/// The contract is terminal-state equivalence, not byte equality: feeding a
/// terminal the original run and feeding it ``rendered`` must leave the same
/// styling. Everything SGR can express and TUI emits is modelled — the
/// on/off attributes, the 16 foreground and background colours in both
/// brightness ranges, the 256-colour and 24-bit forms of each, and an
/// underline's shape (`4:n`) and colour (SGR 58).
///
/// A code outside that set is passed through verbatim, in order, ahead of the
/// netted state: unknown means "not safe to reason about", and dropping a code
/// is worse than emitting one too many. A colour in ITU T.416's colon form
/// (`38:5:n`, `38:2::r:g:b`, and the same for 48) is not such a code: it is
/// read into the colour it names and spelled again in the semicolon form, which
/// every terminal reads. Passed through, it was a code only a reset ended, and
/// the `39` or `49` after it changed nothing this model held, so it was netted
/// away and the colour ran on.
///
/// ## Representation
///
/// A bitmask, two small colour values and a (nearly always empty) array — no
/// `Set`, no `[String]` per colour. This state is parsed and compared once per
/// CELL by the cell diff, the overlay split, the SGR collapse and the opacity
/// blend, on every frame; with a `Set<Int>` of attributes and parameter lists
/// of strings, every copy retained three heap objects and every `apply` split
/// the sequence into strings and parsed each. Numerals are spelled
/// canonically on the way out (`07` in reads back as `7`), which a terminal
/// cannot tell apart; every test model compares the state, not the spelling.
package struct SGRState: Sendable, Equatable {

    /// A colour as SGR spells it: a named code as given (`31`, `97`, `44`,
    /// `107`), a 256-colour index, or 24-bit components. Which slot it is in
    /// says whether the extended forms render as 38 or 48.
    ///
    /// `package`, not `private`, so a caller already holding a colour in a
    /// richer form can reduce it to these three shapes ONCE and state the
    /// result. `Color` lives in a sibling module this one cannot see (they are
    /// declared as siblings with no dependency either way), so the reduction
    /// cannot happen in here — it happens above both, and this is the shape it
    /// hands down. The CASES are the whole of the package surface; every method
    /// below stays internal to this module.
    package enum Colour: Sendable, Equatable {
        case named(Int)
        case indexed(Int)
        case rgb(Int, Int, Int)

        /// The parameters as `apply` would have been given them.
        func codes(introducer: Int) -> [String] {
            switch self {
            case .named(let code): return [String(code)]
            case .indexed(let index): return [String(introducer), "5", String(index)]
            case .rgb(let red, let green, let blue):
                return [String(introducer), "2", String(red), String(green), String(blue)]
            }
        }

        /// Appends the parameters to a sequence under construction.
        func append(to parameters: inout String, introducer: Int) {
            switch self {
            case .named(let code):
                parameters += String(code)
            case .indexed(let index):
                parameters += String(introducer)
                parameters += ";5;"
                parameters += String(index)
            case .rgb(let red, let green, let blue):
                parameters += String(introducer)
                parameters += ";2;"
                parameters += String(red)
                parameters += ";"
                parameters += String(green)
                parameters += ";"
                parameters += String(blue)
            }
        }

        /// Appends the parameter as SGR 58 spells an underline colour: ONE
        /// parameter, its arguments after colons — `58:5:n`, `58:2::r:g:b`.
        ///
        /// Never the semicolon form `58;5;n`, though most terminals that colour
        /// underlines read both. A terminal that does not know 58 reads that
        /// form's arguments as codes of their own: Apple Terminal blinked text
        /// under `4;58;5;196`, and Warp changed the background under
        /// `4:4;58;5;46` (read by the owner, 2026-10-18) — the 5 read as blink,
        /// the 46 as a colour — where the colon form is one parameter they
        /// ignore. There is no named form; a named colour is spelled by its
        /// index, which is what it is.
        package func appendUnderlineColour(to parameters: inout String) {
            switch self {
            case .named(let code):
                parameters += "58:5:"
                parameters += String(code % 10 + (code >= 90 ? 8 : 0))
            case .indexed(let index):
                parameters += "58:5:"
                parameters += String(index)
            case .rgb(let red, let green, let blue):
                parameters += "58:2::"
                parameters += String(red)
                parameters += ":"
                parameters += String(green)
                parameters += ":"
                parameters += String(blue)
            }
        }

        /// `ESC[49m` held as a field of its own — the terminal's, stated — where a
        /// caller tracks one beside the state it nets: `SGRState` itself keeps a
        /// stated 49 and a reset alike, as no background, which is exact for bytes
        /// that go to the terminal as they are and not for a row the writer has yet
        /// to finish, which puts its page back after every reset.
        package static let statedTerminalField = Self.named(49)

        /// `ESC[39m` held as an ink of its own — the terminal's, stated — where a
        /// caller keeps what a painter stated beside what it nets:
        /// ``statedTerminalField``'s twin in the other slot. A reversal of the
        /// terminal's own pair states `39`, and a pass that rewrites colours reads it
        /// as the palette's ink, where an unsaid ink is the terminal's and left alone
        /// (`AnimatedCellRun.groundStyle`).
        package static let statedTerminalInk = Self.named(39)

        /// The terminal's own FOREGROUND held as a field — what a cell reversed on the
        /// terminal's own ink (`ESC[7;39…m`) shows under it — where a caller tracks the
        /// field a cell shows. No background code spells it: only a 7 draws it, over
        /// 39 in the foreground slot, so a field of this kind is painted by reversing
        /// the cell drawn on it (``String/paintedOver(fieldsReversing:)``). 39 is a
        /// foreground code and names no background, so as a field it is unambiguous.
        package static let terminalForegroundField = Self.named(39)

        /// This colour, held as an INK, as the background slot spells it: what a
        /// reversed cell shows as its field. `nil` where it has no such spelling —
        /// a named code outside the sixteen inks.
        package var asFieldFromInk: Self? {
            switch self {
            case .named(let code) where (30...37).contains(code) || (90...97).contains(code):
                return .named(code + 10)
            case .named:
                return nil
            case .indexed, .rgb:
                return self
            }
        }

        /// A colour from a complete parameter list — one named code, or the
        /// three- or five-element extended forms — or `nil` for anything else.
        init?(parameters: [String]) {
            switch parameters.count {
            case 1:
                guard let code = Int(parameters[0]) else { return nil }
                self = .named(code)
            case 3:
                guard parameters[1] == "5", let index = Int(parameters[2]) else { return nil }
                self = .indexed(index)
            case 5:
                guard parameters[1] == "2", let red = Int(parameters[2]), let green = Int(parameters[3]),
                    let blue = Int(parameters[4])
                else { return nil }
                self = .rgb(red, green, blue)
            default:
                return nil
            }
        }
    }

    /// The on/off attributes: bit `n` is set when attribute `n` (1...9) is on.
    /// Rendered in ascending order, which is bit order.
    private var attributes: UInt16 = 0

    /// The foreground, or `nil` for the terminal's default.
    private var foreground: Colour?

    /// The background, or `nil` for the terminal's default.
    private var background: Colour?

    /// How an underline in force is drawn, as SGR `4:n` numbers it: 2 double,
    /// 3 curly, 4 dotted, 5 dashed — and 0 for the plain single line of SGR 4.
    /// Always 0 while no underline is in force, so equal states compare equal.
    private var underlineShape: UInt8 = 0

    /// The underline's colour (SGR 58), or `nil` for the text's own (SGR 59).
    /// It outlives the underline, as a terminal's does: SGR 24 ends the line,
    /// not its colour.
    package var underlineColour: Colour?

    /// Codes this model does not understand, kept verbatim and in order.
    private var passthrough: [String] = []

    /// Whether the state is the terminal's default — nothing to emit.
    public var isDefault: Bool {
        attributes == 0 && foreground == nil && background == nil && underlineColour == nil && passthrough.isEmpty
    }

    public init() {}

    /// The bits each off-code clears.
    ///
    /// 21 is included alongside 22 for bold: ECMA-48 assigns 21 to
    /// double-underline and many terminals treat it as bold-off, so honouring
    /// both is the conservative reading — this is netting, and treating an
    /// off-code as a no-op would leave styling ON that the original cleared.
    private static func attributesOff(by code: Int) -> UInt16 {
        switch code {
        case 21: return bit(1)
        case 22: return bit(1) | bit(2)  // normal intensity: clears bold and dim
        case 23: return bit(3)
        case 24: return bit(4)
        case 25: return bit(5) | bit(6)
        case 27: return bit(7)
        case 28: return bit(8)
        case 29: return bit(9)
        default: return 0
        }
    }

    private static func bit(_ attribute: Int) -> UInt16 { 1 << UInt16(attribute) }

    /// The attributes that put ink on a cell holding nothing but a space:
    /// underline, blink (both), reverse, strike.
    private static let visibleOnBlankCell: UInt16 = bit(4) | bit(5) | bit(6) | bit(7) | bit(9)

    /// Sets the foreground to a colour's SGR parameters — `["31"]`,
    /// `["38", "5", "n"]`, `["38", "2", "r", "g", "b"]` — or to the terminal's
    /// default for `nil` (what SGR 39 does).
    ///
    /// The same state ``apply(_:)`` reaches for `ESC[<parameters>m`. The parse
    /// is the way to learn a colour from text; this is the way to state one
    /// you already hold — `apply` rebuilt and re-split the sequence per cell
    /// of a translucent overlay, 17% of that page's frame. A list that is not
    /// a complete colour is applied as the sequence it spells.
    ///
    /// - Parameter parameters: A well-formed colour parameter list, or `nil`.
    public mutating func setForeground(parameters: [String]?) {
        guard let parameters else {
            foreground = nil
            return
        }
        // An EMPTY list says nothing, and must therefore do nothing. It is not
        // a colour, so it falls to the `apply` below — where it spells
        // `ESC[m`, a bare SGR 0, which resets the WHOLE state. `Color
        // .foregroundCodes()` returns `[]` at `ColorDepth.noColor`, so at the
        // one depth whose entire contract is "emit no colour", asking for a
        // colour stripped the bold, underline and inverse off the cell —
        // `.opacity()` composites through these setters, so a faded heading
        // came back unemphasised. `backgroundEscape(depth:)` already guards the
        // same emptiness on its own path.
        guard !parameters.isEmpty else { return }
        if let colour = Colour(parameters: parameters) {
            foreground = colour
        } else {
            let joined: String = parameters.joined(separator: ";")
            apply("\u{1B}[" + joined + "m")
        }
    }

    /// The background twin of ``setForeground(parameters:)`` (SGR 49 for `nil`).
    public mutating func setBackground(parameters: [String]?) {
        guard let parameters else {
            background = nil
            return
        }
        // See ``setForeground(parameters:)``: an empty list is not a sequence.
        guard !parameters.isEmpty else { return }
        if let colour = Colour(parameters: parameters) {
            background = colour
        } else {
            let joined: String = parameters.joined(separator: ";")
            apply("\u{1B}[" + joined + "m")
        }
    }

    /// Sets the foreground to a colour already reduced to the form this state
    /// keeps, or to the terminal's default (SGR 39) for `nil`.
    ///
    /// The third and last way in, and the cheapest: ``apply(_:)`` is for a
    /// colour that arrives as SGR TEXT, ``setForeground(parameters:)`` for one
    /// that arrives as a parameter LIST, and this for one the caller already
    /// holds as the numbers. Reaching the same state through the list costs an
    /// array and a `String` per code on the way out and an `Int` parse per code
    /// on the way back in — for values that were in hand. The opacity blend
    /// pays that once or twice per CELL of every translucent overlay, which is
    /// what this exists for.
    ///
    /// There is deliberately no depth and no "draw no colour" case here: at
    /// `ColorDepth.noColor` the answer is *change nothing*, which no colour
    /// value can say, so the caller decides before calling. `Color
    /// .foregroundCodes()` says the same thing by returning `[]`, which is why
    /// ``setForeground(parameters:)`` guards emptiness rather than applying it.
    ///
    /// - Parameter colour: The colour, or `nil` for the terminal's default.
    package mutating func setForeground(_ colour: Colour?) {
        foreground = colour
    }

    /// The background twin of ``setForeground(_:)`` (SGR 49 for `nil`).
    ///
    /// - Parameter colour: The colour, or `nil` for the terminal's default.
    package mutating func setBackground(_ colour: Colour?) {
        background = colour
    }

    /// Sets the underline colour (SGR 58, or SGR 59 for `nil`).
    ///
    /// - Parameter colour: The colour, or `nil` for the text's own colour.
    package mutating func setUnderlineColour(_ colour: Colour?) {
        underlineColour = colour
    }

    /// Folds one complete escape sequence into the state.
    ///
    /// Non-SGR sequences (anything not ending in `m`) are ignored: they move the
    /// cursor or clear the screen, and neither is "styling in force".
    ///
    /// Walks the bytes and folds each parameter into the state as it is read:
    /// no list of parameters, no `String` per code. A parameter that is not a
    /// number, and not a colon form this model reads, is passed through as the
    /// text it was.
    ///
    /// - Parameter sequence: A full escape, `ESC [ … m`.
    public mutating func apply(_ sequence: String) {
        applyReportingBackground(sequence)
    }

    /// What an SGR sequence said about the background.
    package enum BackgroundStatement: Sendable, Equatable {
        /// SGR 0 (or an empty parameter): the background back to the terminal's
        /// default, along with everything else.
        case reset
        /// SGR 49: the terminal's own field, stated as a field.
        case terminalDefault
        /// A colour: a named, 256-colour or 24-bit background.
        case colour
    }

    /// Folds `sequence` into the state exactly as ``apply(_:)`` does, and says
    /// what it said about the background — its LAST statement about it, since a
    /// later parameter overrides an earlier one — or `nil` if it said nothing.
    ///
    /// For a caller that tracks one more background than this state holds — the
    /// one its own output has in force — and would otherwise parse every sequence
    /// twice to keep the two in step: after a sequence that said something the
    /// output has exactly this state's background, and after one that said
    /// nothing it has whatever it had.
    ///
    /// - Parameter sequence: A full escape, `ESC [ … m`.
    /// - Returns: What the sequence last said about the background.
    @discardableResult
    package mutating func applyReportingBackground(_ sequence: String) -> BackgroundStatement? {
        // Read in place. Until 2026-11-24 every sequence was first parsed into
        // an array of parameters — one allocation per escape, in the collapse,
        // the cell diff, the overlay split and the painters, 2,565 of them in a
        // 120×40 frame — and a colon-form parameter into a `String` and a split
        // (CORE1-10, WRITER-10).
        if let statement = sequence.utf8.withContiguousStorageIfAvailable({ unsafe fold($0) }) {
            return statement
        }
        return Array(sequence.utf8).withUnsafeBufferPointer { unsafe fold($0) }
    }

    /// A `38`, `48` or `58` in the `;` form, whose arguments are the
    /// parameters after it: a selector (`5` or `2`), then one index or three
    /// channels. Held while they are read, so a parameter can be folded the
    /// moment it is parsed.
    private struct ExtendedColour {
        /// The introducer, or 0 when no colour is being read.
        var introducer = 0
        /// `5` or `2` once read; 0 while the selector is awaited.
        var selector = 0
        /// The arguments read after the selector, and how many it takes.
        var count = 0
        var needed = 0
        /// False once an argument is not a number: the group is consumed and
        /// ignored, as a malformed colour is.
        var valid = true
        var first = 0
        var second = 0
        var third = 0
    }

    /// One parameter, as the walk reads it: a number (an empty one is 0), or
    /// the bytes of one that is not.
    private enum Parameter {
        case number(Int)
        case text(Range<Int>)
    }

    /// Folds the parameters of `bytes`, a whole `ESC [ … m`, and returns what
    /// they last said about the background.
    private mutating func fold(
        _ bytes: UnsafeBufferPointer<UInt8>
    ) -> BackgroundStatement? {
        let count = bytes.count
        guard count > 0, unsafe bytes[count - 1] == 0x6D else { return nil }  // 'm'
        // The parameters run from after '[' to before 'm'; a sequence with no
        // '[' has no parameters, which is the same as an empty list.
        var cursor = 0
        while cursor < count, unsafe bytes[cursor] != 0x5B { cursor += 1 }  // '['
        if cursor < count { cursor += 1 }
        let end = count - 1
        var statement: BackgroundStatement?
        var group = ExtendedColour()
        while true {
            let start = cursor
            var value = 0
            var numeric = true
            while cursor < end, unsafe bytes[cursor] != 0x3B {  // ';'
                let byte = unsafe bytes[cursor]
                if numeric, byte >= 0x30, byte <= 0x39, value < 100_000_000 {
                    value = value * 10 + Int(byte - 0x30)
                } else {
                    numeric = false
                }
                cursor += 1
            }
            // An empty parameter — a bare ESC[m, an empty slot — is 0.
            let parameter: Parameter = cursor == start || numeric ? .number(value) : .text(start..<cursor)
            unsafe fold(parameter, of: bytes, group: &group, statement: &statement)
            guard cursor < end else { break }
            cursor += 1
            if cursor == end {  // a trailing ';'
                unsafe fold(.number(0), of: bytes, group: &group, statement: &statement)
                break
            }
        }
        // A colour still awaiting arguments is incomplete, and ignored.
        return statement
    }

    /// Folds one parameter, in the context of the `;`-form colour, if any, it
    /// belongs to.
    private mutating func fold(
        _ parameter: Parameter, of bytes: UnsafeBufferPointer<UInt8>, group: inout ExtendedColour,
        statement: inout BackgroundStatement?
    ) {
        if group.introducer != 0 {
            if group.selector == 0 {
                // The selector, or not a colour: an introducer followed by
                // anything else is consumed alone, and what follows it is a
                // parameter of its own.
                if case .number(let selector) = parameter, selector == 5 || selector == 2 {
                    group.selector = selector
                    group.needed = selector == 5 ? 1 : 3
                    return
                }
                group = ExtendedColour()
            } else {
                // An argument, whatever it holds: the colour's span is its
                // selector's, so a malformed argument is consumed with it.
                if case .number(let value) = parameter {
                    switch group.count {
                    case 0: group.first = value
                    case 1: group.second = value
                    default: group.third = value
                    }
                } else {
                    group.valid = false
                }
                group.count += 1
                guard group.count == group.needed else { return }
                if group.valid {
                    let colour: Colour =
                        group.selector == 5 ? .indexed(group.first) : .rgb(group.first, group.second, group.third)
                    setExtendedColour(colour, introducer: group.introducer, statement: &statement)
                }
                group = ExtendedColour()
                return
            }
        }
        switch parameter {
        case .text(let range):
            guard unsafe !applySubparameters(bytes, range, statement: &statement) else { return }
            // swiftlint:disable:next optional_data_string_conversion
            passthrough.append(unsafe String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self))
        case .number(let value):
            apply(value, group: &group, statement: &statement)
        }
    }

    /// Folds one numeric parameter.
    private mutating func apply(
        _ value: Int, group: inout ExtendedColour, statement: inout BackgroundStatement?
    ) {
        switch value {
        case 0:
            self = Self()
            statement = .reset
        case 1...9, 21, 22, 23, 24, 25, 27, 28, 29, 59:
            applyAttribute(value)
        case 30...37, 90...97:
            foreground = .named(value)
        case 39:
            foreground = nil
        case 40...47, 100...107:
            background = .named(value)
            statement = .colour
        case 49:
            background = nil
            statement = .terminalDefault
        case 38, 48, 58:
            group = ExtendedColour()
            group.introducer = value
        default:
            passthrough.append(String(value))
        }
    }

    /// Puts a colour read from a 38, 48 or 58 in its slot.
    private mutating func setExtendedColour(
        _ colour: Colour, introducer: Int, statement: inout BackgroundStatement?
    ) {
        switch introducer {
        case 38:
            foreground = colour
        case 48:
            background = colour
            statement = .colour
        default:
            underlineColour = colour
        }
    }

    /// Folds an attribute's on or off code, or 59, which clears the
    /// underline's colour. A plain 4 is a single line, whatever shape one
    /// before it had, and 24 ends the line in every shape.
    private mutating func applyAttribute(_ code: Int) {
        switch code {
        case 1...9:
            attributes |= Self.bit(code)
            if code == 4 { underlineShape = 0 }
        case 59:
            underlineColour = nil
        default:
            attributes &= ~Self.attributesOff(by: code)
            if code == 24 { underlineShape = 0 }
        }
    }

    /// Folds one parameter with colon-separated arguments that this model
    /// reads — an underline's shape, `4:n`, or a colour: the underline's,
    /// `58:5:n`, `58:2::r:g:b` (or `58:2:r:g:b`, without the colour-space
    /// slot), and the foreground's and background's in the same forms, `38:…`
    /// and `48:…` — and says whether it was one. Any other is left for the
    /// passthrough.
    ///
    /// Read in place, as the `;` parameters are. An argument is a number when
    /// it is digits and nothing else: a sign is not an SGR parameter byte, so
    /// `4:+3` is a code this model does not read, where `UInt8("+3")` once
    /// read it as 3.
    ///
    /// - Parameter statement: Set as ``apply(_:)``'s `;` form sets it, when the
    ///   parameter states a background.
    private mutating func applySubparameters(
        _ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, statement: inout BackgroundStatement?
    ) -> Bool {
        // The leading field names the attribute, spelled exactly: `04:3` is not
        // an underline's shape.
        let (lead, leadEnd) = unsafe Self.colonField(bytes, from: range.lowerBound, to: range.upperBound)
        guard let lead, leadEnd < range.upperBound,
            leadEnd - range.lowerBound == (lead == 4 ? 1 : 2),
            lead == 4 || lead == 38 || lead == 48 || lead == 58
        else { return false }
        guard let arguments = unsafe ColonArguments(bytes, from: leadEnd, to: range.upperBound) else { return false }
        if lead == 4 { return applyUnderlineShape(arguments) }
        guard let colour = arguments.colour else { return false }
        setExtendedColour(colour, introducer: lead, statement: &statement)
        return true
    }

    /// Folds `4:n`, an underline's shape, and says whether it was one: a single
    /// argument, 0 (none) to 5.
    private mutating func applyUnderlineShape(_ arguments: ColonArguments) -> Bool {
        guard arguments.count == 1, let shape = arguments.values.0, shape <= 5 else { return false }
        if shape == 0 {
            attributes &= ~Self.bit(4)
            underlineShape = 0
        } else {
            attributes |= Self.bit(4)
            underlineShape = shape == 1 ? 0 : UInt8(shape)
        }
        return true
    }

    /// The arguments after a colon-form parameter's leading field, read in
    /// place: at most five (`2::r:g:b`), each a number or `nil`.
    private struct ColonArguments {
        var values: (Int?, Int?, Int?, Int?, Int?) = (nil, nil, nil, nil, nil)
        var count = 0

        /// The arguments from `start`, the `:` after the leading field, to
        /// `end`, or `nil` when there are more than five.
        init?(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) {
            var cursor = start
            while cursor < end {
                guard count < 5 else { return nil }
                let (value, fieldEnd) = unsafe SGRState.colonField(bytes, from: cursor + 1, to: end)
                switch count {
                case 0: values.0 = value
                case 1: values.1 = value
                case 2: values.2 = value
                case 3: values.3 = value
                default: values.4 = value
                }
                count += 1
                cursor = fieldEnd
            }
        }

        /// The colour they name after a 38, 48 or 58 — `5:i`, `2::r:g:b` or
        /// `2:r:g:b` — or `nil` for one this model does not read.
        var colour: Colour? {
            switch (values.0, count) {
            case (5, 2):
                guard let index = values.1 else { return nil }
                return .indexed(index)
            case (2, 4):
                guard let red = values.1, let green = values.2, let blue = values.3 else { return nil }
                return .rgb(red, green, blue)
            case (2, 5):
                guard let red = values.2, let green = values.3, let blue = values.4 else { return nil }
                return .rgb(red, green, blue)
            default:
                return nil
            }
        }
    }

    /// The colon-separated field starting at `start`: its value, or `nil` when
    /// it is empty or not all digits, and the offset of the `:` that ends it
    /// (or `end`).
    private static func colonField(
        _ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int
    ) -> (value: Int?, end: Int) {
        var cursor = start
        var value = 0
        var numeric = true
        while cursor < end, unsafe bytes[cursor] != 0x3A {  // ':'
            let byte = unsafe bytes[cursor]
            if numeric, byte >= 0x30, byte <= 0x39, value < 100_000_000 {
                value = value * 10 + Int(byte - 0x30)
            } else {
                numeric = false
            }
            cursor += 1
        }
        return (numeric && cursor > start ? value : nil, cursor)
    }

    /// The shortest sequence that puts a default terminal into this state, or
    /// the empty string for the default state.
    public var rendered: String {
        guard !isDefault else { return "" }
        return "\u{1B}[" + parameters + "m"
    }

    /// The netted parameters, `;`-separated: passthrough first, then the
    /// attributes, then the colours.
    ///
    /// Ascending attribute order, so the same state always renders identically
    /// — an unstable rendering would make buffers that ARE equal compare
    /// unequal and defeat the render memo.
    public var parameters: String {
        var result = passthrough.joined(separator: ";")
        var attribute = 1
        while attribute <= 9 {
            if attributes & Self.bit(attribute) != 0 {
                if !result.isEmpty { result += ";" }
                appendAttribute(attribute, to: &result)
            }
            attribute += 1
        }
        if let foreground {
            if !result.isEmpty { result += ";" }
            foreground.append(to: &result, introducer: 38)
        }
        if let background {
            if !result.isEmpty { result += ";" }
            background.append(to: &result, introducer: 48)
        }
        if let underlineColour {
            if !result.isEmpty { result += ";" }
            underlineColour.appendUnderlineColour(to: &result)
        }
        return result
    }

    /// Appends the code that turns `attribute` on: its number, and for an
    /// underline drawn other than single, `4:n`.
    private func appendAttribute(_ attribute: Int, to parameters: inout String) {
        if attribute == 4, underlineShape != 0 {
            parameters += "4:"
            parameters += String(underlineShape)
        } else {
            parameters += String(attribute)
        }
    }

    /// The shortest sequence that takes a terminal from `previous` to this
    /// state, or the empty string when they are the same.
    ///
    /// A delta — only the components that changed — where one can be spelled:
    /// an attribute that went OFF has no single off-code that is safe on every
    /// terminal, so that case falls back to a reset-prefixed absolute.
    public func rendered(changingFrom previous: Self) -> String {
        guard self != previous else { return "" }
        // Spelled only where it is the answer or a delta might be longer: it is
        // the whole state's parameters built again, a string per colour, and a
        // row whose colour changes at every cell asked for it at every cell
        // (2026-10-26: `SGRState.parameters` was 4.5% of a frame of
        // `translucent --variant material`, nearly all of it from here).
        var absolute: String { isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + parameters + "m" }
        guard previous.attributes & ~attributes == 0,
            previous.passthrough == passthrough
        else { return absolute }

        var codes = ""
        var turnedOn = attributes & ~previous.attributes
        // An underline that stays on in another shape is stated again.
        if underlineShape != previous.underlineShape { turnedOn |= attributes & Self.bit(4) }
        var attribute = 1
        while attribute <= 9 {
            if turnedOn & Self.bit(attribute) != 0 {
                if !codes.isEmpty { codes += ";" }
                appendAttribute(attribute, to: &codes)
            }
            attribute += 1
        }
        let clearsAColour = appendColourChanges(from: previous, to: &codes)
        // Unreachable — equal attributes, shape and colours with equal
        // passthrough IS equality — but a delta that says nothing would silently
        // leave the previous styling in force, so spend the bytes rather than
        // trust the reasoning.
        guard !codes.isEmpty else { return absolute }
        let delta = "\u{1B}[" + codes + "m"
        // A delta that only turns things on names a subset of what the absolute
        // names, spelled the same, without the absolute's `0;`: it is shorter,
        // and the absolute need not be built to find that out.
        guard clearsAColour else { return delta }
        // Otherwise it is usually shorter, but not always: going back to the
        // default spells out `ESC[39;49m` where `ESC[0m` says the same in four
        // bytes. Both are correct, so take whichever is smaller.
        let reset = absolute
        return delta.utf8.count <= reset.utf8.count ? delta : reset
    }

    /// Appends the codes for each colour that differs from `previous`'s: the
    /// colour, or its slot's default code (39, 49, 59) where it went.
    ///
    /// - Returns: Whether any of them went — a code the absolute does not name.
    private func appendColourChanges(from previous: Self, to codes: inout String) -> Bool {
        var clears = false
        if foreground != previous.foreground {
            if !codes.isEmpty { codes += ";" }
            if let foreground { foreground.append(to: &codes, introducer: 38) } else { codes += "39"; clears = true }
        }
        if background != previous.background {
            if !codes.isEmpty { codes += ";" }
            if let background { background.append(to: &codes, introducer: 48) } else { codes += "49"; clears = true }
        }
        if underlineColour != previous.underlineColour {
            if !codes.isEmpty { codes += ";" }
            if let underlineColour {
                underlineColour.appendUnderlineColour(to: &codes)
            } else {
                codes += "59"
                clears = true
            }
        }
        return clears
    }

    /// ``rendered(changingFrom:)`` for bytes a row has yet to be finished with —
    /// where a field is put back after every reset, as the row builder puts the
    /// page back (`FrameDiffWriter.buildLine`) and a painter's persistent fill its
    /// colour.
    ///
    /// There a reset and `ESC[49m` are two fields: the one around the row, and the
    /// terminal's own — on a page with an RGB, two colours. A state with no
    /// background after one that named some is a cell on the field around the row,
    /// so the change is spelled from a reset, never as the delta's `49`, which is
    /// shorter wherever only the field moves and puts the terminal's own there.
    /// Every other change is the shortest, as ``rendered(changingFrom:)`` spells it.
    ///
    /// A cell that states the terminal's own field keeps it as a background of its
    /// own (`.named(49)`, the opacity blend's spelling of a stated 49), so the cell
    /// after it that names none is a change from a field too.
    ///
    /// - Parameters:
    ///   - previous: The state the row is in.
    ///   - resetRestoresAField: Whether a reset here will have a field put back
    ///     after it; without, exactly ``rendered(changingFrom:)``.
    /// - Returns: The escape that takes the row to this state.
    package func rendered(changingFrom previous: Self, resetRestoresAField: Bool) -> String {
        guard resetRestoresAField, background == nil, previous.background != nil else {
            return rendered(changingFrom: previous)
        }
        return isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + parameters + "m"
    }

    /// Whether a cell holding nothing but a space looks the same under this
    /// state as under `other`: the background, the attributes that put ink on
    /// a blank cell, and — only when one of those is on — the foreground they
    /// draw in. A passthrough code is unknown and might draw, so it counts.
    public func paintsBlankCellsIdentically(to other: Self) -> Bool {
        guard background == other.background,
            passthrough.isEmpty, other.passthrough.isEmpty
        else { return false }
        let mine = attributes & Self.visibleOnBlankCell
        guard mine == other.attributes & Self.visibleOnBlankCell else { return false }
        // An underline on a blank cell is drawn in its shape and its colour.
        if mine & Self.bit(4) != 0,
            underlineShape != other.underlineShape || underlineColour != other.underlineColour
        {
            return false
        }
        // Those attributes draw in the foreground colour (or, for reverse, AS
        // the background), so with any of them in force the foreground is as
        // visible as the background is.
        return mine == 0 || foreground == other.foreground
    }

    /// Whether reverse video (SGR 7) is in force.
    package var reversesVideo: Bool { attributes & Self.bit(7) != 0 }

    /// Whether bold (SGR 1) is in force.
    package var isBold: Bool { attributes & Self.bit(1) != 0 }

    /// Whether faint (SGR 2) is in force.
    package var isFaint: Bool { attributes & Self.bit(2) != 0 }

    /// Whether italic (SGR 3) is in force.
    package var isItalic: Bool { attributes & Self.bit(3) != 0 }

    /// Whether strikethrough (SGR 9) is in force.
    package var isStruckThrough: Bool { attributes & Self.bit(9) != 0 }

    /// The underline in force, as SGR `4:n` numbers its shape (1 single, 2
    /// double, 3 curly, 4 dotted, 5 dashed), or `nil` for none.
    package var underline: Int? {
        guard attributes & Self.bit(4) != 0 else { return nil }
        return underlineShape == 0 ? 1 : Int(underlineShape)
    }

    /// Whether an attribute in force draws in the foreground colour on a blank
    /// cell — underline, blink, strike — so the foreground is visible there.
    package var paintsInkOnBlankCell: Bool {
        attributes & (Self.bit(4) | Self.bit(5) | Self.bit(6) | Self.bit(9)) != 0
    }

    /// Whether a background colour is in force (as opposed to the default).
    public var namesBackground: Bool { background != nil }

    /// The background in force, or `nil` for the terminal's default — the value
    /// ``renderedBackground`` spells, for a caller that compares backgrounds
    /// cell by cell and would otherwise build a `String` per cell to do it.
    package var backgroundColour: Colour? { background }

    /// The foreground in force, or `nil` for the terminal's default — the ink
    /// twin of ``backgroundColour``, for the same kind of caller.
    package var foregroundColour: Colour? { foreground }

    /// The underline colour in force, where it is a palette index, which is how
    /// a Kitty placeholder cell names a placement.
    package var underlineColourIndex: Int? {
        if case .indexed(let index)? = underlineColour { return index }
        return nil
    }

    /// `colour` as the escape that puts it in force as the background: what
    /// ``renderedBackground`` spells for a state holding it, and `ESC[49m` for
    /// `nil`, which the rendered form spells as nothing because it starts from
    /// the default and this may not.
    static func backgroundEscape(_ colour: Colour?) -> String {
        guard let colour else { return "\u{1B}[49m" }
        var escape = "\u{1B}["
        colour.append(to: &escape, introducer: 48)
        return escape + "m"
    }

    /// Just the background, as a sequence — what a padded run needs restored
    /// under it — or the empty string when the default is in force.
    public var renderedBackground: String {
        guard let background else { return "" }
        var parameters = ""
        background.append(to: &parameters, introducer: 48)
        return "\u{1B}[" + parameters + "m"
    }
}

// MARK: - Reading the state

extension SGRState {
    /// Whether the attribute SGR `code` turns on is in force: 1 bold, 2 dim,
    /// 3 italic, 4 underline, 5 and 6 blink, 7 reverse, 8 hidden, 9 strike.
    package func isOn(_ code: Int) -> Bool {
        (1...9).contains(code) && attributes & Self.bit(code) != 0
    }
}
