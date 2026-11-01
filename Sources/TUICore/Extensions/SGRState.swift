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
/// is worse than emitting one too many.
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
        func appendUnderlineColour(to parameters: inout String) {
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
    private var underlineColour: Colour?

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

    /// Folds one complete escape sequence into the state.
    ///
    /// Non-SGR sequences (anything not ending in `m`) are ignored: they move the
    /// cursor or clear the screen, and neither is "styling in force".
    ///
    /// Walks the bytes and parses each parameter in place: no split, no
    /// `String` per code. A parameter that is not a number is passed through
    /// as the text it was.
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
        let utf8 = sequence.utf8
        guard utf8.last == 0x6D else { return nil }  // 'm'
        // NOT the `reserveCapacity` that measured SLOWER on `Table.alignText`:
        // that one is about String's inline small-string storage, which an
        // Array does not have, so here it is strictly fewer allocations. The
        // list grows 1→2→4→8, so `ESC[38;2;r;g;bm` reallocates four times
        // for five parameters and throws three buffers away.
        //
        // Eight is the common ceiling, not a bound. A collapsed run carrying a
        // truecolour foreground AND background is spelled
        // `ESC[0;38;2;r;g;b;48;2;r;g;bm` — eleven parameters — which is what
        // `collapsingAdjacentSGR()` emits and what the cell diff re-parses; it
        // grows past this reservation exactly as it grew before.
        //
        // Below the guard, not above it: the opacity blend hands this every
        // cursor move and erase in a row as well as every colour, and those
        // must go on allocating nothing.
        var codes: [Parameter] = []
        codes.reserveCapacity(8)
        // The parameters run from after '[' to before 'm'; a sequence with no
        // '[' has no parameters, which is the same as an empty list.
        var index = utf8.startIndex
        while index < utf8.endIndex, utf8[index] != 0x5B { index = utf8.index(after: index) }  // '['
        if index < utf8.endIndex { index = utf8.index(after: index) }
        let end = utf8.index(before: utf8.endIndex)
        var start = index
        while true {
            var cursor = start
            var value = 0
            var numeric = true
            var empty = true
            while cursor < end, utf8[cursor] != 0x3B {  // ';'
                let byte = utf8[cursor]
                if numeric, byte >= 0x30, byte <= 0x39, value < 100_000_000 {
                    value = value * 10 + Int(byte - 0x30)
                } else {
                    numeric = false
                }
                empty = false
                cursor = utf8.index(after: cursor)
            }
            if empty {
                codes.append(.number(0))  // a bare ESC[m, or an empty slot, is 0
            } else if numeric {
                codes.append(.number(value))
            } else {
                codes.append(.text(String(sequence[start..<cursor])))
            }
            guard cursor < end else { break }
            start = utf8.index(after: cursor)
            if start == end { codes.append(.number(0)); break }  // a trailing ';'
        }
        return apply(codes)
    }

    /// One parsed parameter: a number, or text this model cannot read.
    private enum Parameter {
        case number(Int)
        case text(String)

        var text: String {
            switch self {
            case .number(let value): return String(value)
            case .text(let text): return text
            }
        }
    }

    /// Folds `codes` in, and returns what they last said about the background.
    private mutating func apply(_ codes: [Parameter]) -> BackgroundStatement? {
        var statement: BackgroundStatement?
        var index = 0
        while index < codes.count {
            guard case .number(let value) = codes[index] else {
                if case .text(let text) = codes[index], applySubparameters(text) {
                    index += 1
                    continue
                }
                passthrough.append(codes[index].text)
                index += 1
                continue
            }
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
                let (consumed, applied) = applyExtendedColour(value, codes, from: index)
                if applied, value == 48 { statement = .colour }
                index += consumed
                continue
            default:
                passthrough.append(String(value))
            }
            index += 1
        }
        return statement
    }

    /// Folds a `38;…`, `48;…` or `58;…` parameter group, and reports how many
    /// parameters it consumed and whether it was read as a colour. An incomplete
    /// group is consumed and ignored: it cannot be read as a colour, and its
    /// digits are not attributes.
    private mutating func applyExtendedColour(
        _ introducer: Int, _ codes: [Parameter], from index: Int
    ) -> (consumed: Int, applied: Bool) {
        let span = Self.extendedColourSpan(codes, from: index)
        let parameters = codes[index..<min(codes.count, index + span)]
        let colour: Colour?
        switch (parameters.count, parameters.dropFirst().first) {
        case (3, .number(5)):
            if case .number(let value) = parameters[index + 2] { colour = .indexed(value) } else { colour = nil }
        case (5, .number(2)):
            if case .number(let red) = parameters[index + 2], case .number(let green) = parameters[index + 3],
                case .number(let blue) = parameters[index + 4]
            {
                colour = .rgb(red, green, blue)
            } else {
                colour = nil
            }
        default:
            colour = nil
        }
        guard let colour else { return (span, false) }
        switch introducer {
        case 38: foreground = colour
        case 48: background = colour
        default: underlineColour = colour
        }
        return (span, true)
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
    /// reads — an underline's shape, `4:n`, or its colour, `58:5:n`,
    /// `58:2::r:g:b` (or `58:2:r:g:b`, without the colour-space slot) — and
    /// says whether it was one. Any other is left for the passthrough.
    private mutating func applySubparameters(_ text: String) -> Bool {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        switch fields.first {
        case "4":
            guard fields.count == 2, let shape = UInt8(fields[1]), shape <= 5 else { return false }
            if shape == 0 {
                attributes &= ~Self.bit(4)
                underlineShape = 0
            } else {
                attributes |= Self.bit(4)
                underlineShape = shape == 1 ? 0 : shape
            }
            return true
        case "58":
            let arguments = fields.dropFirst().map { Int($0) }
            switch (arguments.first, arguments.count) {
            case (5, 2):
                guard let index = arguments[1] else { return false }
                underlineColour = .indexed(index)
            case (2, 4), (2, 5):
                let channels = arguments.suffix(3)
                guard let red = channels[channels.startIndex], let green = channels[channels.startIndex + 1],
                    let blue = channels[channels.startIndex + 2]
                else { return false }
                underlineColour = .rgb(red, green, blue)
            default:
                return false
            }
            return true
        default:
            return false
        }
    }

    private static func extendedColourSpan(_ codes: [Parameter], from index: Int) -> Int {
        guard index + 1 < codes.count else { return 1 }
        switch codes[index + 1] {
        case .number(5): return min(3, codes.count - index)
        case .number(2): return min(5, codes.count - index)
        default: return 1
        }
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

    /// Whether strikethrough (SGR 9) is in force.
    package var isStruckThrough: Bool { attributes & Self.bit(9) != 0 }

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
