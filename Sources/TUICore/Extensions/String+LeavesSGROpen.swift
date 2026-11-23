//  🖥️ TUI — A Terminal UI framework for Swift
//  String+LeavesSGROpen.swift
//
//  Whether a line leaves SGR styling on at its end: the question a cut asks
//  before it closes what it cut, and a truncation before it ends its ellipsis.
//  Split out of String+TerminalWidth.swift, which measures cells.
//
//  Created by LAYERED.work
//  License: MIT

extension String {

    /// Whether SGR styling is still in force at the end of this string — i.e.
    /// whether text appended to it would inherit colour or attributes.
    ///
    /// The terminal applies SGR parameters in order, so only the LAST sequence
    /// decides: a pure reset (`ESC[0m`, a bare `ESC[m`, an all-zero parameter
    /// list) closes everything, and anything else leaves something on.
    ///
    /// Erring toward `true` costs a redundant four-byte reset; erring toward
    /// `false` bleeds the attribute over whatever the caller appends. So a
    /// sequence this cannot prove is a reset counts as open.
    ///
    /// A walk over the bytes that steps from one `ESC` to the end of its
    /// sequence (`escapeSequenceEnd(startingAt:in:)`, the segment
    /// walker's rule on bytes) and decodes nothing: the text between escapes is
    /// never segmented, and a line with no escape at all is one pass over its
    /// bytes.
    public var leavesSGROpen: Bool {
        func scan(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
            var open = false
            var index = 0
            while index < bytes.count {
                guard unsafe bytes[index] == 0x1B else {
                    index += 1
                    continue
                }
                let (end, isSGR) = unsafe Self.escapeSequenceEnd(startingAt: index, in: bytes)
                if isSGR { open = unsafe !Self.isSGRReset(UnsafeBufferPointer(rebasing: bytes[index..<end])) }
                index = end
            }
            return open
        }
        if let contiguous = utf8.withContiguousStorageIfAvailable({ unsafe scan($0) }) { return contiguous }
        return Array(utf8).withUnsafeBufferPointer { unsafe scan($0) }
    }

    /// Whether an SGR sequence turns everything off.
    ///
    /// Byte-wise, because this runs once per SGR sequence of every clipped
    /// line: the `split(separator:)` it replaces built an array of `Substring`
    /// — and `Int(_:)` per element — for every sequence, which made asking a
    /// 100-cell styled line whether it left anything open cost 16.6 µs, more
    /// than twice what segmenting the line cost in the first place.
    static func isSGRReset(_ sequence: String) -> Bool {
        // `ESC [ <params> m`: skip the two-byte introducer and the terminator.
        // Every parameter has to be zero, and a parameter is zero exactly when
        // every digit of it is `0` — so the whole test is "nothing but `0` and
        // `;`". An empty parameter is ECMA-48's default of 0, and an empty body
        // (a bare `ESC[m`) is a reset, which both fall out of the loop running
        // no iterations that fail.
        //
        // Stricter than the `Int(_:)` parse it replaces in exactly one place:
        // that read `ESC[-0m` as a reset, because `Int("-0")` is 0. `-` is a
        // legal CSI parameter byte and not a legal SGR one, so it is a sequence
        // this cannot prove is a reset — which the doc comment above says
        // counts as open.
        //
        // `dropFirst(2).dropLast()` walked a `Slice` of the view through its
        // Collection witness; the bytes are read directly instead, for the
        // reason ``asciiStrippedLength(bounded:limit:)`` gives.
        if let contiguous = sequence.utf8.withContiguousStorageIfAvailable({ unsafe isSGRReset($0) }) {
            return contiguous
        }
        return Array(sequence.utf8).withUnsafeBufferPointer { unsafe isSGRReset($0) }
    }

    /// `isSGRReset(_:)` on a sequence's bytes, `ESC [` and the final
    /// `m` included, for a walk that already has them.
    static func isSGRReset(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes.count > 3 else { return true }  // `ESC [ m` or shorter
        for index in 2..<(bytes.count - 1) where unsafe bytes[index] != 0x30 && bytes[index] != 0x3B {
            return false
        }
        return true
    }
}
