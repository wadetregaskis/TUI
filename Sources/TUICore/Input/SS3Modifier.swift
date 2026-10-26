//  🖥️ TUI — A Terminal UI framework for Swift
//  SS3Modifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// What the bytes between an SS3 key's `ESC O` and its own byte spell.
///
/// A terminal that puts a modifier there spells it `m` (`ESC O 2 P`, xterm's
/// older Shift-F1) or `1;m` (`ESC O 1;5 A`), `m` being xterm's modifier code:
/// `1 +` a bitfield, from 1 to 16, with no leading zero. Nothing else goes
/// there.
///
/// It matters because a meta-sending terminal spells Alt-Shift-O `ESC O` too,
/// so `ESC O` followed by typing must be held as an SS3 key in the making no
/// longer than a modifier could be. The input parser asks after every
/// parameter byte and gives the key up at the first one no modifier spells
/// (`Terminal.tryExtractSS3`); `KeyEvent.parse` reads the modifier through it.
package enum SS3Modifier: Equatable {
    /// No parameters: a key with no modifier.
    case none

    /// A whole modifier, its code from 1 to 16. `1` may yet become `1;m`, or
    /// a code from 10 to 16.
    case code(Int)

    /// `1;`: on its way to a modifier, not one yet.
    case partial

    /// Nothing more makes these a modifier: `17`, `05`, `2;`, `1;5;`, `?`.
    case invalid

    /// Reads `parameters`, the bytes after `ESC O` and before the key's own.
    package init(_ parameters: some Collection<UInt8>) {
        guard !parameters.isEmpty else {
            self = .none
            return
        }
        // Three pieces at most: a third, empty or not, already means a second `;`.
        let fields = parameters.split(separator: 0x3B, maxSplits: 2, omittingEmptySubsequences: false)
        switch fields.count {
        case 1:
            self = Self.modifierCode(spelledBy: fields[0]).map { .code($0) } ?? .invalid
        case 2 where fields[0].elementsEqual([0x31]):
            self = fields[1].isEmpty ? .partial : Self.modifierCode(spelledBy: fields[1]).map { .code($0) } ?? .invalid
        default:
            self = .invalid
        }
    }

    /// The code `digits` spell, if they spell one: 1 to 16, no leading zero.
    private static func modifierCode(spelledBy digits: some Collection<UInt8>) -> Int? {
        guard digits.first != 0x30, let code = ASCIIDecimal.value(of: digits), (1...16).contains(code) else {
            return nil
        }
        return code
    }
}
