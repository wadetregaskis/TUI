//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppleTerminalSequenceShapes.swift
//
//  The shapes of escape sequence Apple Terminal does not consume, as a check
//  the tests of everything TUIkit sends unasked can share.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Apple Terminal's CSI parser leaks a sequence's final byte onto the screen
/// when the sequence carries BOTH a `?` private-parameter marker and an
/// ECMA-48 intermediate byte (0x20…0x2F) — measured 2026-08-26 on 455.1
/// across all sixteen intermediates, with either half alone consumed
/// correctly. See `Documentation/Terminal-compatibility.md`, "Asking the
/// terminal — Device Attributes".
///
/// - Returns: Each CSI in `bytes` with both, as written; empty when there is
///   none.
func csiSequencesAppleTerminalLeaks(in bytes: String) -> [String] {
    var offending: [String] = []
    let scalars = Array(bytes.unicodeScalars)
    var index = 0
    while index < scalars.count {
        guard scalars[index].value == 0x1B, index + 1 < scalars.count,
            scalars[index + 1] == "["
        else {
            index += 1
            continue
        }
        var cursor = index + 2
        var isPrivate = false
        var hasIntermediate = false
        while cursor < scalars.count {
            let value = scalars[cursor].value
            if (0x3C...0x3F).contains(value) { isPrivate = true }
            if (0x20...0x2F).contains(value) { hasIntermediate = true }
            if (0x40...0x7E).contains(value) { break }
            cursor += 1
        }
        if isPrivate && hasIntermediate {
            offending.append(String(String.UnicodeScalarView(scalars[index...min(cursor, scalars.count - 1)])))
        }
        index = cursor + 1
    }
    return offending
}

/// The introducers of the string-terminated families Apple Terminal does not
/// parse — DCS (`ESC P`) and APC (`ESC _`), measured to print their payload,
/// and PM (`ESC ^`) and SOS (`ESC X`), which nothing TUIkit sends unasked has
/// any business carrying either. OSC (`ESC ]`) it parses. See
/// `Documentation/Terminal-compatibility.md`, "Apple Terminal parses OSC and
/// does NOT parse DCS or APC".
///
/// - Returns: Each introducer found in `bytes`, as `ESC` and its byte.
func stringIntroducersAppleTerminalPrints(in bytes: String) -> [String] {
    let scalars = Array(bytes.unicodeScalars)
    return zip(scalars, scalars.dropFirst()).compactMap { escape, introducer in
        escape.value == 0x1B && "P_^X".unicodeScalars.contains(introducer)
            ? "\u{1B}" + String(introducer) : nil
    }
}
