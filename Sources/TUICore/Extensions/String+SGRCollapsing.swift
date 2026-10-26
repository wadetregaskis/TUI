//  🖥️ TUI — A Terminal UI framework for Swift
//  String+SGRCollapsing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension String {
    /// Merges every run of back-to-back SGR escapes into one.
    ///
    /// ## Why
    ///
    /// A rendered row is assembled from styled fragments, and each fragment
    /// ends by resetting. `FrameDiffWriter` then re-establishes the row's
    /// background after every reset, because a row must keep its own background
    /// across one. The result is a row whose bytes are mostly punctuation:
    /// measured on one frame of a `NavigationSplitView` divider drag at 120×40
    /// — a full repaint, which is what a column resize is — **32,394 bytes, of
    /// which 19,974 were SGR escapes**. 2,565 escapes for 4,800 cells: a colour
    /// change every 1.9 cells, 984 of them a bare `ESC[0m` immediately followed
    /// by the background it had just cleared.
    ///
    /// That is why dragging a divider looked like one or two frames a second.
    /// The app was not slow — writes to the terminal block, so it renders
    /// exactly as fast as the terminal can absorb, and it was handing the
    /// terminal three times the bytes the frame needed.
    ///
    /// ## What it does, and why it is exact
    ///
    /// SGR is a pure state update, so a run of them with **no character printed
    /// in between** is indistinguishable from a single escape carrying the same
    /// parameters in the same order. Nothing observed the intermediate states.
    /// Two cases, both exact:
    ///
    /// - **A run containing a reset.** Everything before the last `0` is
    ///   discarded by that reset, and everything after it is netted by
    ///   ``SGRState`` — whose whole contract is "the shortest sequence that puts
    ///   a freshly-reset terminal into this state", which is precisely the
    ///   situation after a reset. The line's FIRST reset is emitted as `ESC[0m`
    ///   plus that, because the state it resets from is the unknown baseline.
    ///   Every state after it is emitted as a DELTA from the state this function
    ///   last put the terminal in — see ``SGRState/rendered(changingFrom:)``. An
    ///   absolute would be correct too; it would also spend twelve bytes saying
    ///   "black background" to a terminal whose background is already black.
    /// - **A run without one.** The prior state is unknown, so nothing may be
    ///   netted; the parameters are concatenated into one escape instead. Fewer
    ///   bytes of framing, identical meaning.
    ///
    /// A non-SGR escape (a cursor move, an erase) ends a run, because reordering
    /// styling across one would change what it applies to. An unparseable code
    /// is carried through verbatim by ``SGRState``, which is the same call that
    /// type already makes: unknown means "not safe to reason about".
    ///
    /// ## Seeing across blank cells
    ///
    /// A run of SGR with nothing printed between is not the only thing a row
    /// wastes bytes on. The commoner shape is styling that changes for cells
    /// that cannot show the change: a label in colour, three spaces, another
    /// label in the same colour spends `ESC[39m` to stop being green over
    /// cells that are not green either way, then twelve bytes becoming green
    /// again. Measured over a divider drag at 140×42, `ESC[39m` was the single
    /// most common escape in the whole stream — **4,187 of 17,367, 20,935
    /// bytes** — and `ESC[38;5;22m`, the colour going straight back on, was the
    /// second at 2,646.
    ///
    /// So a state change whose only visible difference is on a glyph is HELD
    /// while the row prints spaces, and emitted at the first cell that can show
    /// it — by which time the row has often changed its mind and nothing needs
    /// emitting at all. What "can show it" means is
    /// ``SGRState/paintsBlankCellsIdentically(to:)``: the background, and the
    /// attributes that put ink on an empty cell.
    ///
    /// This is exact for the same reason the rest is: nothing observed the
    /// intermediate state. It is deliberately done HERE, at the row builder,
    /// rather than in the diff downstream — a row written whole never reaches
    /// the diff, and a full repaint is all such rows.
    ///
    /// ## A row that is not finished yet
    ///
    /// All of the above is exact for bytes that go to the terminal as they are,
    /// where a reset and `ESC[49m` put the same field under a cell: the
    /// terminal's own. A row that has not reached the writer yet is different.
    /// The writer puts the page back after every reset in it
    /// (`FrameDiffWriter.buildLine`), and so does a painter's persistent fill, so
    /// in such a row a reset means "the field around me" and a stated 49 means
    /// "the terminal's own" — two fields, and on a page with an RGB two colours.
    /// Netted as one state, a 49 stated after a reset was dropped (the cell took
    /// the page), and a return to "no field" could be spelled `ESC[49m` where it
    /// had been a reset (the cell took the terminal's own).
    ///
    /// `resetRestoresAField` is for such a row — the opacity resolution's, which
    /// collapses a faded span into a row a painter or the writer has yet to
    /// finish. A background that is the terminal's own is then tracked as either
    /// of the two, and each is spelled so it survives: a stated 49 with its 49,
    /// and the other with a reset.
    ///
    /// - Parameter resetRestoresAField: Whether a reset in this row will have a
    ///   field put back after it before the row reaches the terminal.
    public func collapsingAdjacentSGR(resetRestoresAField: Bool = false) -> String {
        var absolutesSpelled = 0
        return collapsingAdjacentSGR(resetRestoresAField: resetRestoresAField, absolutesSpelled: &absolutesSpelled)
    }

    /// ``collapsingAdjacentSGR(resetRestoresAField:)``, counting the
    /// reset-prefixed absolutes it spells itself — not the one
    /// ``SGRState/rendered(changingFrom:)`` spells to compare a delta against.
    ///
    /// The count is the price of a state change in a row: a state spelled
    /// absolutely is its whole ``SGRState/parameters`` built again, a string per
    /// colour. It is paid for the first state after the line's first reset,
    /// where nothing emitted is known, and where a row with
    /// `resetRestoresAField` puts the field around it back — and nowhere else.
    ///
    /// - Parameters:
    ///   - resetRestoresAField: As ``collapsingAdjacentSGR(resetRestoresAField:)``.
    ///   - absolutesSpelled: Incremented once per absolute spelled.
    package func collapsingAdjacentSGR(resetRestoresAField: Bool, absolutesSpelled: inout Int) -> String {
        guard containsAnySGR else { return self }
        // Walked in UTF-8 bytes, not Characters: every byte the netting reads —
        // ESC, the CSI framing, `m`, a space — is ASCII, and asking each cell
        // for its grapheme cluster was most of the cost (2026-10-26: the walk
        // was 14.6% of a frame of `translucent --variant material`, whose rows
        // change colour at every cell). A cluster still matters in two places,
        // a space and an escape's terminator, where a following scalar can fuse
        // with them; those ask the Character, and only when the next byte is
        // not ASCII, which no ASCII byte can fuse with.
        var source = self
        return source.withUTF8 { bytes in
            collapsingAdjacentSGR(
                bytes, resetRestoresAField: resetRestoresAField, absolutesSpelled: &absolutesSpelled)
        }
    }

    /// The walk behind ``collapsingAdjacentSGR(resetRestoresAField:absolutesSpelled:)``,
    /// over `bytes` — this string's UTF-8.
    private func collapsingAdjacentSGR(
        _ bytes: UnsafeBufferPointer<UInt8>, resetRestoresAField: Bool, absolutesSpelled: inout Int
    ) -> String {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        // Before the line's first reset the incoming state is UNKNOWN, so
        // nothing may be netted and nothing may be skipped — an added reset
        // would clear styling the original deliberately inherited, and a
        // skipped escape would fail to apply to it. Runs are merged by plain
        // concatenation there, which is exact whatever the baseline was.
        //
        // After a reset the state is absolute, which is what makes the rest
        // possible: `SGRState.parameters` is by contract what a freshly-reset
        // terminal needs, and two identical absolute states are
        // indistinguishable, so the second need not be sent.
        var sawReset = false
        var desired = SGRState()
        var emitted: SGRState?
        var unresetRun: [String] = []
        var pending = false
        // Whether a background of `nil` — which `SGRState` keeps for a reset and
        // for a 49 alike — is a STATED 49, in what the row wants and in what this
        // has put in it. Only asked with `resetRestoresAField`.
        var desiredStates49 = false
        var emittedStates49 = false

        func flushUnresetRun() {
            defer { unresetRun.removeAll(keepingCapacity: true) }
            guard !unresetRun.isEmpty else { return }
            result.append(contentsOf: "\u{1B}[".utf8)
            result.append(contentsOf: unresetRun.joined(separator: ";").utf8)
            result.append(0x6D)  // 'm'
        }

        func reconcile() {
            flushUnresetRun()
            guard pending else { return }
            pending = false
            // With something already emitted, the terminal's state is not merely
            // knowable but KNOWN — we put it there — so say only what changed.
            // Without, it is unknown (nothing has been netted yet, only the
            // line's inherited baseline), and only a reset-prefixed absolute is
            // safe. See ``SGRState/rendered(changingFrom:)``.
            //
            // The absolute is spelled only where it is the answer. Spelled up
            // front for every change, it built the state's parameters a second
            // time on each of them — the delta spells its own absolute to
            // compare against — and the writer, whose rows never pass
            // `resetRestoresAField`, threw it away every time: 868 allocations a
            // frame on the `processes` session (2026-09-27).
            var change: String
            if let emitted {
                change = desired.rendered(changingFrom: emitted)
            } else {
                change = Self.absolute(desired, counting: &absolutesSpelled)
            }
            if resetRestoresAField, desired.backgroundColour == nil {
                change = Self.spellingWhichNoField(
                    change, of: desired, statesDefault: desiredStates49,
                    after: emitted.map { ($0.backgroundColour != nil, emittedStates49) },
                    absolutesSpelled: &absolutesSpelled)
            }
            result.append(contentsOf: change.utf8)
            emitted = desired
            emittedStates49 = desiredStates49
        }

        /// Whether the styling still owed may be held over a blank cell.
        ///
        /// Only once the state is knowable at all (`sawReset`) and something has
        /// been emitted to compare against — before that the line's baseline is
        /// inherited and unknown, and an unknown state cannot be shown to be
        /// invisible.
        var canDeferAcross: Bool {
            guard sawReset, unresetRun.isEmpty, let emitted else { return false }
            // A blank cell shows its field, and a reset and a stated 49 are two.
            if resetRestoresAField, desiredStates49 != emittedStates49 { return false }
            return desired.paintsBlankCellsIdentically(to: emitted)
        }

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x1B, let end = escapeEnd(from: index, in: bytes) {
                // The escape's final byte can FUSE with following zero-width
                // scalars (a combining mark, a variation selector) into one
                // Character. They are CONTENT, binding to the previous glyph
                // wherever they sit relative to styling, and are peeled off
                // the sequence so it reaches the model whole.
                let fusedEnd = clusterEnd(ofByteBefore: end, in: bytes)
                // swiftlint:disable:next optional_data_string_conversion - no `Data`; whole scalars of valid UTF-8
                let sequence = String(decoding: UnsafeBufferPointer(rebasing: bytes[index..<end]), as: UTF8.self)
                if bytes[end - 1] == 0x6D {  // 'm'
                    if sawReset {
                        switch desired.applyReportingBackground(sequence) {
                        case .terminalDefault: desiredStates49 = true
                        case .colour, .reset: desiredStates49 = false
                        case nil: break
                        }
                        pending = true
                    } else if sequence.isSGRReset {
                        // From here on the state is knowable.
                        flushUnresetRun()
                        sawReset = true
                        desired = SGRState()
                        desiredStates49 = false
                        emitted = nil
                        pending = true
                    } else {
                        unresetRun.append(sequence.sgrParameters ?? "")
                    }
                } else {
                    // An erase paints with the background in force, and a
                    // cursor move must not be crossed by styling: both are
                    // barriers, so settle before letting one past.
                    reconcile()
                    result.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[index..<end]))
                }
                if fusedEnd > end {
                    let fused = UnsafeBufferPointer(rebasing: bytes[end..<fusedEnd])
                    // A fused scalar that OCCUPIES cells — a lone Fitzpatrick
                    // modifier is a 2-cell swatch — is content, and must pass
                    // the same gate as any printable character, or it is
                    // painted in whatever state the previous fragment left and
                    // the escape it followed lands after it. A zero-width mark
                    // binds to the glyph before it whatever sits between, and
                    // stays where it was.
                    // swiftlint:disable:next optional_data_string_conversion - no `Data`; whole scalars of valid UTF-8
                    if String(decoding: fused, as: UTF8.self).strippedLength > 0 { reconcile() }
                    result.append(contentsOf: fused)
                }
                index = fusedEnd
                continue
            }
            // A space shows its background and whatever draws ink on an empty
            // cell, and nothing else — so a change confined to the rest of the
            // state waits for a cell that can show it. A continuation byte is
            // inside a scalar already passed, and is never a place to emit.
            if byte & 0xC0 != 0x80, !isBlankCell(at: index, in: bytes) || !canDeferAcross {
                reconcile()
            }
            result.append(byte)
            index += 1
        }
        // The trailing reset is load-bearing — it is what stops a row's styling
        // leaking into whatever is drawn next — so the line always ends
        // reconciled, printable characters or not.
        reconcile()
        // swiftlint:disable:next optional_data_string_conversion - no `Data`; whole scalars of valid UTF-8
        return String(decoding: result, as: UTF8.self)
    }

    /// Whether the cell beginning at byte `index` is a space and nothing else:
    /// a space whose Character is not widened by a scalar fused onto it.
    private func isBlankCell(at index: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes[index] == 0x20 else { return false }
        guard index + 1 < bytes.count, bytes[index + 1] >= 0x80 else { return true }
        return self[utf8.index(utf8.startIndex, offsetBy: index)] == " "
    }

    /// The byte offset just past the Character holding the ASCII byte before
    /// `end` — `end` itself unless a scalar from `end` on fuses with it.
    ///
    /// Only a non-ASCII byte at `end` can fuse (LF after CR aside, which no
    /// caller asks about), so only that asks the Character. A byte before `end`
    /// that is not ASCII is the end of the 8-bit `ST`, U+009C, a control that
    /// nothing after it fuses with.
    private func clusterEnd(ofByteBefore end: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        guard end < bytes.count, bytes[end] >= 0x80, bytes[end - 1] < 0x80 else { return end }
        let start = utf8.index(utf8.startIndex, offsetBy: end - 1)
        return utf8.distance(from: utf8.startIndex, to: self.index(after: start))
    }

    /// `change` — the escape that takes the row from what was emitted to a state
    /// with no background — spelled so the row shows the right one of the two
    /// fields that state can be, in a row whose resets have a field put back
    /// after them: the terminal's own where `statesDefault`, and the field around
    /// the row otherwise.
    ///
    /// What the row shows after `change`: the field put back, if `change` resets
    /// (or nothing was emitted, so it is the line's first absolute); the
    /// terminal's own, if it changes the background from a colour, because a
    /// delta spells that as 49; and otherwise whatever was there.
    ///
    /// - Parameters:
    ///   - change: The escape as the netting spells it.
    ///   - desired: The state `change` takes the row to.
    ///   - statesDefault: Whether the row wants a stated 49.
    ///   - emitted: What was emitted before, if anything: whether it had a
    ///     background colour, and whether its lack of one was a stated 49.
    ///   - absolutesSpelled: Incremented when `desired` is spelled from a reset.
    /// - Returns: `change`, with a 49 added, or replaced by `desired` spelled
    ///   from a reset.
    private static func spellingWhichNoField(
        _ change: String, of desired: SGRState, statesDefault: Bool,
        after emitted: (hadColour: Bool, states49: Bool)?, absolutesSpelled: inout Int
    ) -> String {
        let resets = change.hasPrefix("\u{1B}[0m") || change.hasPrefix("\u{1B}[0;")
        let shows49: Bool
        if let emitted, !resets {
            shows49 = emitted.hadColour || emitted.states49
        } else {
            shows49 = false
        }
        if statesDefault == shows49 { return change }
        // A return to the field around the row is a reset, whatever it costs.
        guard statesDefault else { return absolute(desired, counting: &absolutesSpelled) }
        // And a stated 49 is 49, said after whatever else changes.
        guard change.hasSuffix("m"), change.count > 3 else { return change + "\u{1B}[49m" }
        return String(change.dropLast()) + ";49m"
    }

    /// `state` spelled from a reset: `ESC[0;` and the whole of its parameters,
    /// or a bare `ESC[0m` for the default.
    ///
    /// - Parameters:
    ///   - state: The state to spell.
    ///   - spelled: Incremented, for
    ///     ``collapsingAdjacentSGR(resetRestoresAField:absolutesSpelled:)``'s count.
    /// - Returns: The escape.
    private static func absolute(_ state: SGRState, counting spelled: inout Int) -> String {
        spelled += 1
        return state.isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + state.parameters + "m"
    }

    /// Whether the string carries any SGR at all — a plain line has nothing to
    /// reconcile, and bailing costs one scan and saves an allocation.
    private var containsAnySGR: Bool { utf8.contains(0x1B) }

    /// Whether this escape is a reset — `ESC[0m`, `ESC[m`, or any parameter
    /// list whose codes are all zero.
    fileprivate var isSGRReset: Bool {
        guard let parameters = sgrParameters else { return false }
        if parameters.isEmpty { return true }
        return parameters.split(separator: ";", omittingEmptySubsequences: false)
            .allSatisfy { $0.isEmpty || Int($0) == 0 }
    }

    /// This SGR escape's parameter list, without the `ESC[` and the `m`.
    fileprivate var sgrParameters: String? {
        guard hasPrefix("\u{1B}["), hasSuffix("m") else { return nil }
        return String(dropFirst(2).dropLast())
    }

    /// The byte offset just past the escape sequence whose `ESC` is at
    /// `start`, or `nil` when it is neither a complete CSI nor a
    /// string-terminated sequence.
    ///
    /// Not `String.escapeSequenceEnd(startingAt:in:)`, which is otherwise the
    /// walker for exactly this: that one stops a CSI at its first byte outside
    /// the parameter and intermediate ranges, and reads `ESC ( B` as a
    /// sequence, while this one has always run a CSI on to its final byte and
    /// left every other escape to be printed — a difference that changes which
    /// escapes are netted, so it is kept rather than merged here. An
    /// introducer, and the `\` of an `ST`, count only as a Character of their
    /// own: one with a scalar fused onto it is not the ASCII byte it starts
    /// with.
    private func escapeEnd(from start: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int? {
        var index = start + 1
        guard index < bytes.count else { return nil }
        let introducer = bytes[index]
        let introducerIsAlone = clusterEnd(ofByteBefore: index + 1, in: bytes) == index + 1
        // A string-terminated sequence — the OSC 8 hyperlink among them — runs
        // to its `BEL` or `ST`, with an arbitrary payload in between. Left
        // unrecognised it is not merely copied wrong: the payload's characters
        // reach the reconciler one at a time, so a pending `ESC[…m` gets
        // emitted INSIDE the URI, and both the styling and the link are lost.
        if introducerIsAlone, Self.isStringFamilyIntroducer(UInt32(introducer)) {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 0x07 { return index }  // BEL
                if byte == 0xC2, index < bytes.count, bytes[index] == 0x9C { return index + 1 }  // 8-bit ST
                if byte == 0x1B, index < bytes.count, bytes[index] == 0x5C,  // ESC \ — ST
                    clusterEnd(ofByteBefore: index + 1, in: bytes) == index + 1
                {
                    return index + 1
                }
            }
            return index  // unterminated: the payload runs to the end
        }
        guard introducer == 0x5B, introducerIsAlone else { return nil }  // '['
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            // The ECMA-48 final-byte test (0x40…0x7E), NOT "is a letter":
            // `ESC[1@` (ICH) ends at `@`, and a walker that runs on past it to
            // the next letter swallows the following escape — which, when that
            // one ends in `m`, turns `ESC[1@ ESC[0m` into one "SGR" and merges
            // it into a corrupt parameter list. A terminator with a scalar
            // fused onto it still ends the sequence; the caller peels the
            // scalar back off as content.
            if Self.isCSIFinalByte(UInt32(byte)) { return index }
        }
        return nil
    }
}
