//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRState+Resets.swift
//
//  Where an SGR sequence resets, read as `SGRState` reads it: one rule for
//  every walk that has to find a reset without folding the whole state.
//
//  Created by Wade Tregaskis
//  License: MIT

extension SGRState {

    /// Where the parameters that follow the LAST SGR 0 in an SGR sequence begin,
    /// or `nil` when it holds no reset.
    ///
    /// `parameters` is what lies between `ESC[` and the final `m`. A parameter is
    /// SGR 0 exactly where ``apply(_:)`` reads one: empty (`ESC[m`, the first slot
    /// of `ESC[;1m`, a trailing `;`) or every digit a zero (`0`, `00`), and only
    /// at a parameter's own start, so the `0` of `38;5;0` — a colour's index, in
    /// the semicolon form whose arguments are parameters of their own — is never
    /// read as one. The span of such a colour is ``apply(_:)``'s too: `5` takes
    /// one argument, `2` three, and anything else none.
    ///
    /// The terminal applies the parameters in order, so everything before the
    /// last reset is undone by it: the sequence is a reset, then the parameters
    /// from the returned offset. Before this, the walks that put a fill back
    /// after a reset matched the literal `ESC[0m` (and the collapsed `ESC[0;`),
    /// and git's and grep's `ESC[m` went by unseen.
    ///
    /// - Parameter parameters: The bytes between `ESC[` and `m`.
    /// - Returns: The offset just past the last reset parameter and the `;`
    ///   after it (`parameters.count` when nothing follows it), or `nil` for a
    ///   sequence with no reset in it.
    package static func endOfLastReset(inParameters parameters: UnsafeBufferPointer<UInt8>) -> Int? {
        let count = parameters.count
        var found: Int?
        var start = 0
        var arguments = 0  // a `;`-form colour's arguments still to pass over
        while true {
            let (value, end) = unsafe parameter(in: parameters, from: start)
            if arguments > 0 {
                arguments -= 1
            } else if value == 0 {
                found = end == count ? count : end + 1
            } else if value == 38 || value == 48 || value == 58, end < count {
                let (selector, _) = unsafe parameter(in: parameters, from: end + 1)
                arguments = selector == 5 ? 2 : selector == 2 ? 4 : 0
            }
            guard end < count else { return found }
            start = end + 1
        }
    }

    /// The parameters an SGR sequence states after its last reset — empty when
    /// nothing follows it — or `nil` when `sequence` is not an SGR sequence
    /// holding a reset. `endOfLastReset(inParameters:)` for a whole sequence,
    /// for the walks that fold sequences into states rather than copy bytes.
    ///
    /// - Parameter sequence: An escape, `ESC [ … m`.
    package static func parametersAfterReset(in sequence: String) -> String? {
        func read(_ bytes: UnsafeBufferPointer<UInt8>) -> String? {
            guard bytes.count >= 3, unsafe bytes[0] == 0x1B, unsafe bytes[1] == 0x5B,
                unsafe bytes[bytes.count - 1] == 0x6D
            else { return nil }
            let parameters = unsafe UnsafeBufferPointer(rebasing: bytes[2..<(bytes.count - 1)])
            guard let after = unsafe endOfLastReset(inParameters: parameters) else { return nil }
            guard after < parameters.count else { return "" }
            // swiftlint:disable:next optional_data_string_conversion
            return unsafe String(decoding: UnsafeBufferPointer(rebasing: parameters[after...]), as: UTF8.self)
        }
        if let contiguous = sequence.utf8.withContiguousStorageIfAvailable({ unsafe read($0) }) { return contiguous }
        return Array(sequence.utf8).withUnsafeBufferPointer { unsafe read($0) }
    }

    /// The parameter starting at `start`: its value as ``apply(_:)`` reads it —
    /// `0` for an empty one, `nil` for one that is not a number — and the offset
    /// of the `;` that ends it (or the end of the bytes).
    private static func parameter(
        in bytes: UnsafeBufferPointer<UInt8>, from start: Int
    ) -> (value: Int?, end: Int) {
        var cursor = start
        var value = 0
        var numeric = true
        while cursor < bytes.count, unsafe bytes[cursor] != 0x3B {  // ';'
            let byte = unsafe bytes[cursor]
            // The same bound as `applyReportingBackground(_:)`'s, past which a
            // run of digits is text rather than a number.
            if numeric, byte >= 0x30, byte <= 0x39, value < 100_000_000 {
                value = value * 10 + Int(byte - 0x30)
            } else {
                numeric = false
            }
            cursor += 1
        }
        return (numeric ? value : nil, cursor)
    }
}
