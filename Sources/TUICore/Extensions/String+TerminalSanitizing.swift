//  🖥️ TUI — A Terminal UI framework for Swift
//  String+TerminalSanitizing.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Escape-sequence sanitising for untrusted content

extension String {
    /// Returns a copy with **every** ANSI escape sequence and bare control
    /// character removed, suitable for rendering content this program did not
    /// author.
    ///
    /// Every view already does this to the words it draws (``Text``, a label, a
    /// title, a table cell), unless `.textKeepsEscapeSequences()` is in force
    /// above it: the owner's ruling of 2026-11-10. Use it yourself for text that
    /// reaches the terminal some other way, or to store or log what was shown:
    ///
    /// ```swift
    /// log.append(fileName.sanitizedForTerminal)
    /// ```
    ///
    /// ## What it removes
    ///
    /// Every escape family ECMA-48 defines, in both their 7-bit (`ESC`-prefixed)
    /// and 8-bit (C1 control) spellings:
    ///
    /// | Family | 7-bit | 8-bit | Terminated by |
    /// |---|---|---|---|
    /// | CSI — cursor, colour, mode | `ESC [` | `U+009B` | a final byte `0x40…0x7E` |
    /// | OSC — window title, **clipboard writes** | `ESC ]` | `U+009D` | `BEL` or `ST` |
    /// | DCS — device control | `ESC P` | `U+0090` | `ST` |
    /// | APC / PM / SOS | `ESC _` / `ESC ^` / `ESC X` | `U+009F` / `U+009E` / `U+0098` | `ST` |
    /// | Two-byte escapes — `ESC c` (full reset), `ESC 7` / `ESC 8` | `ESC` + one byte | — | — |
    ///
    /// Every other C1 control is dropped too: they are never legitimate text.
    /// So is every C0 control but the three below, and `DEL`: a `BEL` rings, a
    /// backspace moves the cursor back over what was drawn, and none of them is
    /// a character anyone reads.
    ///
    /// An unterminated sequence is consumed to the end of the string. Content
    /// after a truncated introducer is *inside* the sequence as far as the
    /// terminal is concerned, so leaving it visible would be the same leak by
    /// another route.
    ///
    /// ## What it deliberately leaves alone
    ///
    /// **Tab, line feed and carriage return.** A line break (`\n`, `\r\n`,
    /// `\r`) is legitimate content — the text views break lines on it — and a
    /// tab is drawn as a space, so removing either here would corrupt ordinary
    /// input. Each is neutralised instead at the write boundary, by
    /// ``String/sanitizedForTerminalRow()``, which no view can bypass, where the
    /// views leave one in a row.
    ///
    /// ## Why this is not ``String/stripped``
    ///
    /// ``String/stripped`` answers a different question — "what does this
    /// paint?" — for width arithmetic, on output *this framework generated*.
    /// The two now share one rule for where a 7-bit sequence ends
    /// (`String.escapeBodyScan(_:on:)`), because they must: OSC 8
    /// hyperlinks put a string-terminated sequence into that output, and a
    /// measure that took the URI for text would budget columns nothing paints.
    ///
    /// Two things this still reaches that a measure does not, and the asymmetry
    /// is the point. The **8-bit C1 spellings** and the **two-byte escapes**
    /// (`ESC c`, `ESC 7`) cannot occur in output this framework generated, so
    /// recognising them would cost every measure — and every measure runs on
    /// the hot path of every layout pass — to catch a sequence that is not
    /// there. They can certainly occur in what a user pastes, which is what
    /// this is for: it runs once, at the app boundary, and has to assume
    /// hostility.
    ///
    /// - Returns: The string with all escape sequences removed; `self`
    ///   unchanged, without allocating, when there are none — the common case.
    public var sanitizedForTerminal: String {
        guard mayHoldTerminalControls else { return self }

        // The scanner mirrors the shape of `forEachVisibleANSIRun` — a single
        // forward pass over the scalar view, appending visible content as
        // borrowed slices — but recognises every introducer rather than CSI
        // alone. Scalar level, not `Character` level, for the same reason given
        // there: a terminator byte must never fuse with a following `Extend`
        // scalar into one `Character`, or the modifier is swallowed with the
        // escape.
        let scalars = unicodeScalars
        var result = ""
        result.reserveCapacity(utf8.count)

        var index = scalars.startIndex
        var runStart = index
        var hasRun = false
        var state = EscapeScanState.normal

        while index < scalars.endIndex {
            let value = scalars[index].value
            switch state {
            case .normal:
                if value == 0x1B {
                    if hasRun {
                        result += self[runStart..<index]
                        hasRun = false
                    }
                    state = .sawESC
                } else if Self.isDroppedC0(value) {
                    if hasRun {
                        result += self[runStart..<index]
                        hasRun = false
                    }
                } else if let opened = Self.escapeState(openedByC1: value) {
                    if hasRun {
                        result += self[runStart..<index]
                        hasRun = false
                    }
                    state = opened
                } else if !hasRun {
                    runStart = index
                    hasRun = true
                }

            case .sawESC:
                switch value {
                case 0x5B:  // '[' — CSI
                    state = .csi
                case 0x5D, 0x50, 0x5F, 0x5E, 0x58:  // ']' 'P' '_' '^' 'X'
                    state = .string
                case 0x1B:  // ESC ESC — the first is dropped, re-dispatch
                    state = .sawESC
                case 0x20...0x2F:
                    // An nF escape's intermediate byte — `ESC ( B` (designate
                    // character set), `ESC % G` (select UTF-8). More may
                    // follow before the final byte.
                    state = .escIntermediate
                default:
                    // A two-byte escape: `ESC c` (RIS), `ESC 7` / `ESC 8`
                    // (save / restore cursor), and the rest of the Fp/Fs/Fe
                    // forms. The single following byte belongs to the escape,
                    // so it is consumed here and the next scalar starts fresh.
                    // An `ESC` at the very end of the string simply vanishes,
                    // having never left this state.
                    state = .normal
                }

            case .csi:
                if Self.isCSIBodyByte(value) {
                    break
                }
                if Self.isCSIFinalByte(value) {
                    state = .normal
                } else if value == 0x1B {  // ESC interrupts a malformed CSI
                    state = .sawESC
                } else if Self.isDroppedC0(value) || (0x80...0x9F).contains(value) {
                    // A control ends the malformed CSI and is dropped itself,
                    // as it would be anywhere else.
                    state = Self.escapeState(openedByC1: value) ?? .normal
                } else {
                    // Not a CSI byte where a terminator was expected: the
                    // sequence is malformed, and this scalar is visible again.
                    runStart = index
                    hasRun = true
                    state = .normal
                }

            case .escIntermediate, .string, .stringSawESC:
                // An introducer opened inside an unterminated string is still
                // inside it as far as the terminal is concerned, so there is
                // nothing to dispatch on here — the shared body rule
                // (`String.escapeBodyScan(_:on:)`) says when the
                // sequence ends, and it is the same rule the width scanners
                // use. That is the point of sharing it: a sanitizer that
                // stopped in a different place from the measurer would leave
                // exactly the bytes the measurer had already discounted.
                state = Self.escapeBodyScan(state, on: value)
            }
            index = scalars.index(after: index)
        }
        // An unterminated sequence ends with the string and is dropped; only a
        // visible run still in progress survives.
        if hasRun {
            result += self[runStart..<index]
        }
        return result
    }

    /// Whether this may hold anything ``sanitizedForTerminal`` removes: an
    /// `ESC`, a C1 control, `DEL`, or a C0 control other than tab, line feed
    /// and carriage return.
    ///
    /// A *reject*, not a decision: every C1 scalar encodes to UTF-8 as `0xC2`
    /// followed by its low byte, and `0xC2` also leads U+00A0…U+00BF (a
    /// no-break space, `©`), so one contiguous byte scan clears a clean
    /// string without walking scalars at all. What every view's words go
    /// through on every measure and render, so a view can skip the walk, and
    /// any copy, for the string that virtually every string is.
    ///
    /// Eight bytes at a time (SWAR: "has a byte below 0x20", "has a byte equal
    /// to 0x7F / 0xC2"), and byte by byte only in a word that flags, so a word
    /// of plain text costs a few arithmetic operations rather than eight
    /// closure calls, which an unoptimised build makes: every `Text`'s words
    /// pass here at its measure and again at its render.
    package var mayHoldTerminalControls: Bool {
        utf8.withContiguousStorageIfAvailable { buffer -> Bool in
            let bytes = UnsafeRawBufferPointer(buffer)
            let count = bytes.count
            var offset = 0
            while offset + 8 <= count {
                let word = unsafe bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                // A flagged word (a tab or a line break flags one, harmlessly)
                // is walked byte by byte. `while`, not a `for unsafe … where`
                // loop: that loop in this closure crashes the type checker of
                // Swift 6.2 and 6.3 (report "for unsafe in a
                // withContiguousStorageIfAvailable closure crashes the type
                // checker", 2026-11-02).
                if Self.wordMayHoldControl(word) {
                    var index = offset
                    while index < offset + 8 {
                        if Self.isDroppedByte(unsafe bytes[index]) { return true }
                        index += 1
                    }
                }
                offset += 8
            }
            while offset < count {
                if Self.isDroppedByte(unsafe bytes[offset]) { return true }
                offset += 1
            }
            return false
        }
            ?? unicodeScalars.contains { $0.value == 0x1B || Self.isDroppedC0($0.value) || (0x80...0x9F).contains($0.value) }
    }

    /// Whether `word` has a byte below `0x20`, or equal to `0x7F` or `0xC2`:
    /// the classic "has a zero byte" test, `(v - 0x01…) & ~v & 0x80…`, which is
    /// exact about whether one exists (not which), applied to `word` for "below
    /// 0x20" and to `word` XOR each byte broadcast for the two equalities.
    private static func wordMayHoldControl(_ word: UInt64) -> Bool {
        let ones: UInt64 = 0x0101_0101_0101_0101
        let highs: UInt64 = 0x8080_8080_8080_8080
        let below: UInt64 = (word &- ones &* 0x20) & ~word & highs
        let del: UInt64 = word ^ (ones &* 0x7F)
        let c1: UInt64 = word ^ (ones &* 0xC2)
        let hasDEL: UInt64 = (del &- ones) & ~del & highs
        let hasC1Lead: UInt64 = (c1 &- ones) & ~c1 & highs
        return below | hasDEL | hasC1Lead != 0
    }

    /// Whether `byte` is one ``mayHoldTerminalControls`` stops at: a C0 control
    /// other than tab, line feed and carriage return (`ESC` among them), `DEL`,
    /// or `0xC2`, the lead byte of every C1 control.
    private static func isDroppedByte(_ byte: UInt8) -> Bool {
        (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) || byte == 0x7F || byte == 0xC2
    }

    /// Whether `value` is a C0 control the sanitiser drops — every one but tab,
    /// line feed and carriage return, `ESC` among them (which opens a sequence
    /// rather than standing alone) — or `DEL`.
    fileprivate static func isDroppedC0(_ value: UInt32) -> Bool {
        (value < 0x20 && value != 0x09 && value != 0x0A && value != 0x0D && value != 0x1B) || value == 0x7F
    }

    /// The scanner state an 8-bit C1 introducer opens, or `nil` when `value` is
    /// not a C1 control at all.
    ///
    /// C1 controls carry no 7-bit `ESC` prefix; a terminal in 8-bit mode acts on
    /// them directly. They are never legitimate text, so a C1 scalar that
    /// introduces nothing — a stray `U+009C` (ST), say — still returns a state
    /// (`.normal`), which drops it rather than emitting it.
    fileprivate static func escapeState(openedByC1 value: UInt32) -> EscapeScanState? {
        switch value {
        case 0x9B: return .csi  // CSI
        case 0x9D, 0x90, 0x9F, 0x9E, 0x98: return .string  // OSC DCS APC PM SOS
        case 0x80...0x9F: return .normal  // any other C1: dropped, opens nothing
        default: return nil
        }
    }
}
