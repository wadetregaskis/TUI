//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+Replies.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Things the terminal says that nobody typed

/// Terminals volunteer output on the input stream: a graphics acknowledgement,
/// an OSC colour answer, a DCS capability report. It arrives on stdin exactly
/// as a keystroke does, and it is not one — the input parser used to spell
/// `ESC _ G i=7;OK ESC \` out as Alt+underscore followed by `G i = 7 ; O K`,
/// and `=` is a shortcut on more than one page.
///
/// That was latent for as long as TUIkit only ever ASKED questions and read
/// the answers itself. It went live when the framework started sending
/// graphics commands, which are acknowledged unless every one of them carries
/// `q=2` — and "every one of them" is the kind of claim that holds until it
/// does not.
///
/// Swallowing one is right for the keyboard, and not the end of it: an answer
/// about the terminal's COLOURS is the only thing in the process that will ever
/// say what the terminal paints, and the startup exchange closes half a second
/// after it asks. So a reply that says something about them is kept here for the
/// run loop (``noteVolunteeredColorReply(_:)``), and everything else is dropped
/// as before.
///
/// Separate from `Terminal.swift` because that file is at its length limit,
/// and this is a coherent thing to lift out: what the terminal says that nobody
/// typed — how far one such sequence reaches, and which of them is worth keeping.
extension Terminal {

    /// How many bytes the string-terminated sequence at the head of the input
    /// buffer occupies, or `nil` while its terminator has not arrived.
    ///
    /// OSC, DCS, APC, PM and SOS end at `BEL` or `ST` (`ESC \`) rather than at
    /// a final byte, which is why they cannot go through ``tryExtractCSI()``.
    ///
    /// A new `ESC` before the terminator means the sequence was truncated:
    /// only the malformed prefix is reported, so the sequence that interrupted
    /// it parses from its own `ESC`. That is the rule the CSI walk already
    /// applies, and for the same reason — anything else leaks the newcomer's
    /// bytes as keystrokes.
    ///
    /// `nil` too for a sequence with no terminator in its first
    /// ``maxStringSequenceBytes``; the caller tells that from one still
    /// arriving by the buffer's length, and skips its rest
    /// (``skipAbandonedSequence()``).
    ///
    /// Resumes where the last walk of the same sequence stopped
    /// (``sequenceWalkStart(_:)``).
    func stringSequenceLength() -> Int? {
        var index = sequenceWalkStart(2)
        let cap = min(input.count, Self.maxStringSequenceBytes)
        while index < cap {
            if input[index] == 0x07 { return index + 1 }  // BEL
            if input[index] == 0x1B {
                guard index + 1 < input.count else { break }  // ST's tail is still coming
                return input[index + 1] == 0x5C ? index + 2 : index
            }
            index += 1
        }
        noteSequenceWalk(stoppedAt: index)
        return nil
    }

    /// Where a walk of the escape sequence at the front of the input buffer
    /// starts: at `offset`, or further on, where the last walk of the same
    /// sequence stopped without finding its end.
    ///
    /// The same sequence while the buffer's front has not moved
    /// (``InputByteBuffer/frontGeneration``): the bytes that walk read are
    /// still there, unchanged, and none of them ended it. Until 2026-10-12
    /// each walk began at the sequence's start, so one arriving a byte a read
    /// was read once a byte: quadratic in its length, which the cap, then
    /// 4 KiB, held small.
    func sequenceWalkStart(_ offset: Int) -> Int {
        sequenceWalk.frontGeneration == input.frontGeneration ? max(offset, sequenceWalk.stoppedAt) : offset
    }

    /// Records that a walk of the sequence at the front read up to `offset`
    /// without finding its end, for ``sequenceWalkStart(_:)``.
    func noteSequenceWalk(stoppedAt offset: Int) {
        sequenceWalk = (input.frontGeneration, offset)
    }

    /// The longest CSI the parser holds whole, 16 KiB. Past it the sequence
    /// is skipped as it arrives, to its final byte (``skipAbandonedSequence()``):
    /// never typed, and never held, so a terminal that starts one and never
    /// ends it cannot pin the buffer.
    ///
    /// The longest CSI that legitimately arrives is a key: a kitty keyboard
    /// protocol report carrying the text its key typed (TUIkit pushes
    /// `reportAssociatedText`), at most eight bytes a character, a code point
    /// of up to seven digits and its `:`. So 16 KiB holds a report that typed
    /// some two thousand characters; one longer is lost, not typed. Every CSI
    /// reply TUIkit asks for is under forty bytes: xterm's device attributes,
    /// `ESC[?63;1;2;4;6;9;15;16;18;21;22;28;29c`, the longest seen at 37
    /// (`Documentation/Terminals/Terminal compatibility survey.md` has iTerm2's, at 33).
    ///
    /// A CSI is not only a key: DA, DSR and DECRPM answers arrive as CSIs, and
    /// the CSI walk's own 32-byte budget used to truncate a 37-byte
    /// device-attributes reply mid-sequence and leak its tail as typing. From
    /// then until 2026-10-12 every family's limit was 4 KiB
    /// (decisions-PASTE, B-PASTE-2).
    static let maxControlSequenceBytes = 16 << 10

    /// The longest OSC, DCS, APC, PM or SOS the parser holds whole, 64 KiB.
    /// Past it the sequence is skipped as it arrives, to its `BEL` or `ST`
    /// (``skipAbandonedSequence()``): never typed, and never held.
    ///
    /// Of these TUIkit asks for colour answers (OSC 4, 10 and 11, about
    /// twenty-five bytes each), the terminal's name and version (XTVERSION's
    /// DCS, tens of bytes) and graphics acknowledgements (an APC: `OK`, or an
    /// error in words, Warp's sixty characters and iTerm2's some eighty). The
    /// limit is several hundred times the longest. Only the colour answers are
    /// read; any other string sequence is swallowed, whole within the limit
    /// and skipped past it, which comes to the same for the app.
    ///
    /// An OSC 52 clipboard answer is the one reply unbounded by nature: the
    /// base64 of whatever the clipboard holds. TUIkit asks for none, as it
    /// reads the clipboard through the platform's tools (`SystemClipboard`)
    /// and a terminal's own paste arrives bracketed; so one arriving here
    /// answers another program's question and is skipped past the limit like
    /// any other. Were TUIkit to read the clipboard by OSC 52, that answer
    /// would have to be read as a paste is, whole, with no limit.
    static let maxStringSequenceBytes = 64 << 10

    // MARK: - Skipping what is left of an over-long one

    /// The two shapes of escape sequence the parser can give up on as
    /// over-long, which end differently.
    enum AbandonedSequence {
        /// A CSI: ends at its final byte.
        case controlSequence
        /// An OSC, DCS, APC, PM or SOS: ends at `BEL` or `ST` (`ESC \`).
        case string
    }

    /// Consumes what has arrived of the sequence ``abandonedSequence`` names,
    /// through its terminator, and returns whether it is over.
    ///
    /// A sequence that runs past its family's limit
    /// (``maxControlSequenceBytes``, ``maxStringSequenceBytes``) is no longer
    /// held, but its rest is still not typing. Until 2026-10-11 the walks dropped the first
    /// 4 KiB and left the rest to the key parser, so a long enough reply —
    /// a clipboard answer's base64, a CSI of many parameters — spelled itself
    /// out as keys. This reads on to where the sequence ends:
    ///
    /// - its terminator, consumed with it: a CSI's final byte, a string
    ///   sequence's `BEL` or `ST`;
    /// - or an `ESC` that begins anything else, which stays for the parser:
    ///   a new sequence cut this one short, the rule both walks apply to one
    ///   within the cap.
    ///
    /// An `ESC` at the very end of what has arrived, in a string sequence, may
    /// be the first byte of `ST`, so it stays in the buffer and the skip goes
    /// on: the Escape key pressed during such a skip arrives once the skip has
    /// ended, and then the wait for a lone `ESC` has run out. Running out of
    /// bytes leaves the skip on for the next call; the dead-sequence wait in
    /// ``resolveStuckPartial()`` ends it if the rest never comes.
    ///
    /// That wait starts again from each byte consumed here. An unfinished
    /// sequence's starts again only once it is longer than a read
    /// (`restartWaitOfLongSequence()`); shorter, it counts every quiet pass,
    /// however many bytes arrive between them. So a reply's rest that arrives in pieces,
    /// with pauses shorter than the wait between them, is not cut off part
    /// way and typed out however many pauses there are; the price is that
    /// typing during the skip — a key held to auto-repeat — keeps it going
    /// and is skipped with it until the typing stops (decisions-PASTE,
    /// B-PASTE-2).
    func skipAbandonedSequence() -> Bool {
        guard let family = abandonedSequence else { return true }
        var index = 0
        var end: Int?
        scan: while index < input.count {
            let byte = input[index]
            switch family {
            case .controlSequence:
                if byte == 0x1B {
                    end = index
                    break scan
                }
                if String.isCSIFinalByte(UInt32(byte)) {
                    end = index + 1
                    break scan
                }
            case .string:
                if byte == 0x07 {  // BEL
                    end = index + 1
                    break scan
                }
                if byte == 0x1B {
                    guard index + 1 < input.count else { break scan }  // maybe ST: wait for its `\`
                    end = input[index + 1] == 0x5C ? index + 2 : index
                    break scan
                }
            }
            index += 1
        }
        let skipped = end ?? index
        if skipped > 0 {
            consume(skipped)
            staleFrames = 0
        }
        if end != nil { abandonedSequence = nil }
        return end != nil
    }

    // MARK: - Keeping the answers that say what the terminal paints

    /// Keeps the complete escape sequence `bytes` when it answers a colour
    /// question, for the run loop to take.
    ///
    /// Told apart by ``TerminalColorQuery/isReply(_:)``, the rule the startup
    /// exchange keeps its own replies by: an OSC 10, 11 or 4 answer, well formed
    /// or not, and a `CSI ? 997 ; Ps n` appearance report. A graphics
    /// acknowledgement, a DA answer and everything else is not kept, and the
    /// parser drops it as it always has.
    ///
    /// The fence, `CSI 0 n`, is kept too, but apart — see ``takeStatusFence()``.
    /// It says nothing about a colour; it says a request has been answered as
    /// far as it is going to be, which is what `TerminalColorRequester` waits
    /// for before sending the next one.
    func noteVolunteeredColorReply(_ bytes: [UInt8]) {
        if TerminalQueryReplies.isStatusFence(bytes[...]) {
            sawVolunteeredStatusFence = true
            return
        }
        guard TerminalColorQuery.isReply(bytes[...]) else { return }
        // A reply nobody takes cannot pin memory: this is dropped rather than
        // buffered forever, the same bargain the sequence limits make.
        guard volunteeredColorReplies.count + bytes.count <= Self.maxVolunteeredReplyBytes else {
            return
        }
        volunteeredColorReplies.append(contentsOf: bytes)
    }

    /// The same, for the string-terminated sequence of `length` bytes at the head
    /// of the input buffer, before ``tryExtractRegularEvent()`` consumes it.
    ///
    /// Copied out only for an OSC, which is the only string-terminated family a
    /// colour answer comes in. A graphics acknowledgement is an APC and arrives
    /// for every image transmitted unless every one of them says `q=2`, so
    /// copying those out would pay an allocation a frame to learn nothing. Nor
    /// an OSC longer than everything kept may be, which would be dropped: an
    /// OSC 52 clipboard answer to another program, up to
    /// ``maxStringSequenceBytes`` long, is not copied to learn that.
    func noteVolunteeredColorReply(headOfInputLength length: Int) {
        guard length > 1, length <= Self.maxVolunteeredReplyBytes else { return }
        guard input.count >= length, input[1] == 0x5D else { return }  // ESC ]
        var sequence: [UInt8] = []
        sequence.reserveCapacity(length)
        for index in 0..<length { sequence.append(input[index]) }
        noteVolunteeredColorReply(sequence)
    }

    /// Everything kept since the last call, emptying the buffer.
    ///
    /// The run loop takes these once per drain, so a burst of eighteen replies is
    /// parsed, published and repainted once. Empty on almost every frame.
    func takeVolunteeredColorReplies() -> [UInt8] {
        guard !volunteeredColorReplies.isEmpty else { return [] }
        defer { volunteeredColorReplies = [] }
        return volunteeredColorReplies
    }

    /// Whether a request's fence arrived since the last call, clearing it.
    ///
    /// A flag of its own rather than a sequence in ``takeVolunteeredColorReplies()``,
    /// because `TerminalColorQuery.parse` stops at the first fence, as the
    /// startup exchange's hand-back does: a fence among a drain's bytes would
    /// hide every reply behind it. Every measured host answers its fence last,
    /// but only because it answers everything it is going to answer first — a
    /// terminal silent on OSC 4 sends the fence with replies to nothing behind
    /// it, and under tmux those two can be half a second apart.
    func takeStatusFence() -> Bool {
        defer { sawVolunteeredStatusFence = false }
        return sawVolunteeredStatusFence
    }

    /// Hard cap on what is held for the run loop, past which a reply is dropped
    /// rather than buffered.
    ///
    /// A reply is about twenty-five bytes and a whole table is eighteen of them,
    /// so this is room for several tables — and a bound on a `Terminal` nobody
    /// drains, which is every `Terminal` outside an app run.
    static let maxVolunteeredReplyBytes = 4096
}
