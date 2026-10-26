//  🖥️ TUI — A Terminal UI framework for Swift
//  HairlineMarker.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A line along the top of some cells, carried by the cells

/// The mark a `.hairline` list separator leaves on the cells it runs along:
/// a private SGR parameter that rides those cells' styling through every
/// stage that rewrites cells, and that the diff writer reads back off the
/// finished frame and takes out before anything reaches the terminal.
///
/// ## Why the cells carry it
///
/// The line is a Kitty classic placement, drawn outside the cell grid
/// (``KittyGraphics/classicPlacement(id:placement:sourceWidth:sourceHeight:z:)``),
/// so nothing that composes cells moves, clips or covers it. Carried as
/// styling ON the cells it runs along, it is moved, clipped and covered with
/// them instead: a scroll view's clip cuts the run, a sheet or a menu over the
/// list replaces the marked cells with its own (an overlay is inserted after a
/// reset — `FrameBuffer.insertOverlay`), and the writer draws the line only
/// where marked cells reached the screen. That is the argument of §11 of
/// `Documentation/Images and terminal graphics/Terminal graphics protocols.md`,
/// applied to a line.
///
/// ## Why this spelling
///
/// `ESC [ 7744 : r : g : b m`. A parameter no terminal assigns, so that
/// ``SGRState`` keeps it verbatim among its passthrough codes, which every
/// splitter and collapser restates with the rest of a cell's styling; the
/// line's colour as colon sub-parameters, so the mark says everything the
/// writer needs and no table has to travel beside the frame. NOT SGR 58,
/// the underline colour: that code is a real one, a link on a marked row
/// would draw its underline in the line's colour, and the reversed pair drops
/// it (`ANSIRenderer.droppingColours`).
///
/// A passthrough code ends only at a reset, so a marked run is closed with a
/// reset and the styling in force restated without the mark — the price is
/// paid on marked rows only. The mark is taken out in the writer on every
/// host, so a stray one never reaches a terminal; a host that is not drawing
/// lines never sees one made at all (``KittyGraphics/isHairlineSupported``).
package enum HairlineMarker {

    /// The private SGR parameter.
    package static let parameter = 7744

    /// What a run of marked cells says about the line along its top.
    package struct Run: Hashable, Sendable {
        /// The run's first cell, in the line's columns.
        package var column: Int
        /// How many cells it runs along.
        package var width: Int
        /// The line's colour.
        package var red: UInt8
        package var green: UInt8
        package var blue: UInt8

        package init(column: Int, width: Int, red: UInt8, green: UInt8, blue: UInt8) {
            self.column = column
            self.width = width
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The colour, packed: what a strip of that colour is filed under.
        package var ink: UInt32 { UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }
    }

    /// The escape that turns the mark on.
    package static func sequence(red: UInt8, green: UInt8, blue: UInt8) -> String {
        "\u{1B}[\(parameter):\(red):\(green):\(blue)m"
    }

    /// The bytes every mark's parameter starts with, `7744:`.
    private static let parameterBytes: [UInt8] = Array("\(parameter):".utf8)

    /// Whether `line` may carry a mark: a byte search, so a line without one
    /// — every line of every frame on a host not drawing lines, and all but a
    /// list's marked rows on one that is — pays one pass over its bytes and no
    /// decoding.
    package static func mayCarryMark(_ line: String) -> Bool {
        var line = line
        return line.withUTF8 { bytes in
            let needle = parameterBytes
            guard bytes.count >= needle.count + 3 else { return false }
            var index = 0
            let last = bytes.count - needle.count
            while index <= last {
                // Only after the `[` or `;` that starts a parameter: a `7744:`
                // in a cell's text is text, and a sanitised row's text holds no
                // ESC to make it anything else.
                if bytes[index] == needle[0], index > 0, bytes[index - 1] == 0x5B || bytes[index - 1] == 0x3B {
                    var matched = 1
                    while matched < needle.count, bytes[index + matched] == needle[matched] { matched += 1 }
                    if matched == needle.count { return true }
                }
                index += 1
            }
            return false
        }
    }

    // MARK: Marking

    /// `line` with the cells in `columns` marked for a line of the given
    /// colour.
    ///
    /// The mark goes on before the first cell that starts inside `columns`,
    /// and back on after every reset among them, as a persistent background
    /// is restated (`ANSIRenderer.restating(_:afterResetsIn:)`); after the
    /// last, a reset and the styling in force without it. A wide character
    /// that starts before `columns` is not marked; one that starts inside is,
    /// whole.
    ///
    /// Served from ``MarkedLines`` when the same line was marked the same way
    /// before: a list's rows come out of the render memo unchanged frame after
    /// frame, and marking walks every character of the row's first line.
    package static func marking(_ line: String, columns: Range<Int>, red: UInt8, green: UInt8, blue: UInt8) -> String {
        guard !columns.isEmpty, columns.lowerBound >= 0 else { return line }
        let key = MarkedLines.Key(line: line, columns: columns, ink: UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue))
        if let marked = MarkedLines.shared.withLock({ $0[key] }) { return marked }
        let marked = walkMarking(line, columns: columns, red: red, green: green, blue: blue)
        MarkedLines.shared.withLock { cache in
            if cache.count >= MarkedLines.capacity { cache.removeAll(keepingCapacity: true) }
            cache[key] = marked
        }
        return marked
    }

    /// ``marking(_:columns:red:green:blue:)``, worked out: one walk of `line`.
    private static func walkMarking(_ line: String, columns: Range<Int>, red: UInt8, green: UInt8, blue: UInt8)
        -> String
    {
        let mark = sequence(red: red, green: green, blue: blue)
        var result = ""
        result.reserveCapacity(line.utf8.count + 2 * mark.utf8.count + 16)
        var state = SGRState()
        var column = 0
        var inside = false
        var done = false
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let text, let isSGR):
                result += text
                if isSGR {
                    state.apply(text)
                    if inside, resets(text) { result += mark }
                }
            case .visible(let character):
                if !done, !inside, column >= columns.lowerBound, column < columns.upperBound {
                    result += mark
                    inside = true
                } else if inside, column >= columns.upperBound {
                    result += "\u{1B}[0m" + state.rendered
                    inside = false
                    done = true
                }
                result.append(character)
                column += character.terminalWidth
            }
            return true
        }
        if inside { result += "\u{1B}[0m" + state.rendered }
        return result
    }

    /// The lines ``marking(_:columns:red:green:blue:)`` has marked, by what
    /// the marking reads: the line, the columns and the colour.
    ///
    /// A static, and not a singleton in the sense of the project's "No
    /// Singletons" rule: a private, bounded memo of a pure function, so
    /// nothing outside it can tell a hit from a miss (CLAUDE.md, the exemption
    /// `ASCIIPalette+SearchIndex.swift` is the example of). Bounded by
    /// emptying it when full rather than by evicting the oldest: what fills it
    /// is a list scrolled through, whose rows on the screen are marked again
    /// once after it empties.
    private enum MarkedLines {
        /// Equal when the line's BYTES are, not when the strings are: `String`'s
        /// `==` and hash are canonical equivalence, which hashes a line with any
        /// non-ASCII character through its NFC form (9% of a frame of hairlined
        /// rows in `megalist`, whose bars are block glyphs) — and two spellings
        /// of one text are two markings, which a memo must not mix up.
        struct Key: Hashable, Sendable {
            var line: String
            var columns: Range<Int>
            var ink: UInt32

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.columns == rhs.columns && lhs.ink == rhs.ink && lhs.line.utf8.elementsEqual(rhs.line.utf8)
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(columns)
                hasher.combine(ink)
                var line = line  // `withUTF8` is mutating: it may make a bridged string contiguous
                line.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
            }
        }

        /// A few screens of rows.
        static let capacity = 512

        static let shared = Lock<[Key: String]>(initialState: [:])
    }

    /// Whether SGR `sequence` ends a passthrough code: a reset among its
    /// parameters (``isReset(_:at:)``).
    private static func resets(_ sequence: String) -> Bool {
        let parameters = sequence.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false)
        var index = 0
        while index < parameters.count {
            if isReset(parameters, at: index) { return true }
            index += span(parameters, at: index)
        }
        return false
    }

    /// Whether the parameter at `index` is SGR 0: empty (`ESC[m`, `ESC[;1m`)
    /// or all zeroes. Asked only at a parameter's own start, so the 0 of
    /// `38;5;0` — a colour's index — is never read as one.
    private static func isReset(_ parameters: [Substring], at index: Int) -> Bool {
        let parameter = parameters[index]
        return parameter.isEmpty || parameter.allSatisfy { $0 == "0" }
    }

    /// How many parameters the one at `index` takes up: a `38`, `48` or `58`
    /// in its semicolon form takes its colour's arguments with it (`5;n`,
    /// `2;r;g;b`), as ``SGRState`` reads it; everything else is one.
    private static func span(_ parameters: [Substring], at index: Int) -> Int {
        let parameter = parameters[index]
        guard parameter == "38" || parameter == "48" || parameter == "58", index + 1 < parameters.count else {
            return 1
        }
        switch parameters[index + 1] {
        case "5": return min(3, parameters.count - index)
        case "2": return min(5, parameters.count - index)
        default: return 1
        }
    }

    // MARK: Reading back

    /// `line` without its marks, and the runs they made.
    ///
    /// Every mark parameter is taken out of the escape it sits in; an escape
    /// left with no parameter at all goes with it — an emptied `ESC[m` would
    /// be a reset. Runs are in column order, each a stretch of contiguous
    /// cells of one colour; a cell under no mark ends one, as does a change of
    /// colour.
    package static func extracting(_ line: String) -> (line: String, runs: [Run]) {
        var result = ""
        result.reserveCapacity(line.utf8.count)
        var runs: [Run] = []
        var ink: (UInt8, UInt8, UInt8)?
        var column = 0
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let text, let isSGR):
                guard isSGR else {
                    result += text
                    return true
                }
                let parameters = text.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false)
                var kept: [Substring] = []
                var removed = false
                var index = 0
                while index < parameters.count {
                    let span = span(parameters, at: index)
                    if let colour = colour(of: parameters[index]) {
                        ink = colour
                        removed = true
                    } else {
                        if isReset(parameters, at: index) { ink = nil }
                        kept += parameters[index..<(index + span)]
                    }
                    index += span
                }
                if !removed {
                    result += text
                } else if !kept.isEmpty {
                    result += "\u{1B}[" + kept.joined(separator: ";") + "m"
                }
            case .visible(let character):
                let width = character.terminalWidth
                if let (red, green, blue) = ink, width > 0 {
                    if var last = runs.last, last.column + last.width == column,
                        last.red == red, last.green == green, last.blue == blue
                    {
                        last.width += width
                        runs[runs.count - 1] = last
                    } else {
                        runs.append(Run(column: column, width: width, red: red, green: green, blue: blue))
                    }
                }
                result.append(character)
                column += width
            }
            return true
        }
        return (result, runs)
    }

    /// `line` without its marks — ``extracting(_:)``'s line alone, for a
    /// writer that is not drawing them (a replay's frame, a one-off render).
    package static func stripping(_ line: String) -> String {
        mayCarryMark(line) ? extracting(line).line : line
    }

    /// The colour a mark parameter states, or `nil` for any other parameter.
    private static func colour(of parameter: Substring) -> (UInt8, UInt8, UInt8)? {
        let fields = parameter.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == "\(Self.parameter)",
            let red = UInt8(fields[1]), let green = UInt8(fields[2]), let blue = UInt8(fields[3])
        else { return nil }
        return (red, green, blue)
    }
}
