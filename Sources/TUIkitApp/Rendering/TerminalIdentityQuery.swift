//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalIdentityQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - Asking

/// The startup exchange that asks a terminal who it is.
///
/// ## Why this exists
///
/// `TERM_PROGRAM` does not cross an ssh hop (see
/// ``TerminalHost/hostProgram(environment:)``), and the one host whose
/// cursor-advance quirks most need compensating — Apple Terminal — sets no
/// variable ssh forwards and answers no XTVERSION. An escape query has neither
/// problem: it is answered by the terminal itself, at the far end of however
/// many hops.
///
/// ## Shape of the exchange
///
/// One write, one round trip. The queries are sent back to back and finished
/// with a DSR status request, `CSI 5 n`, which every terminal answers with
/// `CSI 0 n`; reading until that reply arrives means a query nobody implements
/// costs nothing and hangs nothing.
///
/// ## Why the fence is not the cursor report
///
/// It was `CSI 6 n` until 2026-10-05, and that reply, `CSI row;column R`, is
/// the shape xterm gives a modified F3: Shift-F3 is `CSI 1;2 R`. A Shift-F3 or
/// Ctrl-F3 pressed during the exchange therefore ENDED it, before DA2 had
/// arrived — the terminal went unidentified, so uncompensated, and the key was
/// lost. No key sends `CSI 0 n`, so a key now is just a key: it is handed back
/// with the other bytes that are not replies. (Ghostty's VT reference, by way
/// of `Documentation/Ghostty-VT-adoption.md`, K4.)
///
/// **CSI queries only.** A DCS query (XTGETTCAP, `ESC P + q … ESC \`) is not
/// safe here: Apple Terminal does not parse DCS and *prints the payload* —
/// measured, it left a literal `+q544e` on the screen. Every query below is a
/// CSI sequence, which even a terminal that implements none of them consumes
/// correctly, because CSI parsing is generic (parameter bytes, then a final
/// byte).
enum TerminalIdentityQuery {

    /// The queries, in the order their replies come back:
    /// XTVERSION (`ESC[>0q`), DA1 (`ESC[c`), DA2 (`ESC[>c`), then the status
    /// fence (`ESC[5n`) that ends the read.
    static let request = "\u{1B}[>0q\u{1B}[c\u{1B}[>c" + TerminalQueryReplies.statusFence

    /// Sorts a raw reply buffer into ``TerminalIdentity``.
    ///
    /// Walks escape sequences with the repo's canonical CSI rule
    /// (``String/isCSIBodyByte(_:)`` /
    /// ``String/isCSIFinalByte(_:)``) rather than "digits and `;` then a
    /// letter", which stops at the `?` of a DA1 reply and would strand the rest
    /// as text.
    ///
    /// Anything that is not one of the replies asked for is preserved in
    /// ``TerminalIdentity/unconsumed`` — a keystroke that landed during the
    /// round trip is the user's, not ours.
    static func parse(_ bytes: [UInt8]) -> TerminalIdentity {
        var identity = TerminalIdentity()
        var index = bytes.startIndex

        while index < bytes.endIndex {
            guard bytes[index] == 0x1B else {
                // Not an escape at all, so not a reply: someone typed while the
                // app was starting. Keep it and carry on — abandoning the walk
                // here would strand every reply after it, and the replies are
                // what we came for.
                identity.unconsumed.append(bytes[index])
                index += 1
                continue
            }
            // A trailing bare ESC, or a sequence whose tail has not arrived, is
            // a split sequence: not ours to interpret, so hand back the rest.
            guard index + 1 < bytes.endIndex,
                let next = consume(bytes, from: index, into: &identity)
            else {
                identity.unconsumed.append(contentsOf: bytes[index...])
                return identity
            }
            if identity.sawFence {
                identity.unconsumed.append(contentsOf: bytes[next...])
                return identity
            }
            index = next
        }
        return identity
    }

    /// Consumes the one escape sequence beginning at `index`, recording what it
    /// says, and returns the index just past it — or `nil` if it is truncated.
    private static func consume(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        switch bytes[index + 1] {
        case 0x5B: return consumeCSI(bytes, from: index, into: &identity)
        case 0x50: return consumeDCS(bytes, from: index, into: &identity)
        default:
            // ESC followed by anything else is not a reply we asked for.
            identity.unconsumed.append(bytes[index])
            return index + 1
        }
    }

    /// The CSI branch: a DA1 reply, a DA2 reply, the status fence, or someone's
    /// key — an arrow, or a modified F3, whose `CSI 1;2 R` is a cursor report's
    /// shape and is nobody's reply here.
    private static func consumeCSI(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        var end = index + 2
        while end < bytes.endIndex, String.isCSIBodyByte(UInt32(bytes[end])) { end += 1 }
        guard end < bytes.endIndex, String.isCSIFinalByte(UInt32(bytes[end])) else { return nil }
        // The first parameter byte is what tells a DA1 reply (`?`) from a DA2
        // reply (`>`); `end > index + 2` guards a parameterless `ESC[c`, where
        // that byte IS the final one.
        let lead: UInt8? = end > index + 2 ? bytes[index + 2] : nil
        if TerminalQueryReplies.isStatusFence(bytes[index...end]) {
            // `CSI 0 n` — the status fence, which ends the exchange.
            identity.sawFence = true
            return end + 1
        }
        switch (bytes[end], lead) {
        case (0x63, 0x3F):  // 'c' after '?' — Primary Device Attributes
            identity.primaryAttributes = ascii(bytes[index...end])
        case (0x63, 0x3E):  // 'c' after '>' — Secondary Device Attributes
            identity.secondaryAttributes = ascii(bytes[index...end])
        default:
            identity.unconsumed.append(contentsOf: bytes[index...end])
        }
        return end + 1
    }

    /// The DCS branch. Any DCS here is an XTVERSION reply — it is the only
    /// query in ``request`` that answers with one — so its content is not
    /// examined, only its existence.
    private static func consumeDCS(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        var end = index + 2
        while end < bytes.endIndex {
            if bytes[end] == 0x07 { break }  // BEL terminator
            if bytes[end] == 0x1B, end + 1 < bytes.endIndex, bytes[end + 1] == 0x5C {
                end += 1  // ST — ESC \
                break
            }
            end += 1
        }
        guard end < bytes.endIndex else { return nil }
        identity.answeredVersion = true
        return end + 1
    }

    /// An escape sequence as a `String`. Every byte of a CSI sequence is ASCII
    /// by construction — ESC, `[`, parameter bytes (`0x20...0x3F`) and a final
    /// byte (`0x40...0x7E`) — so each maps to exactly one scalar, and there is
    /// no decoding to get wrong.
    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        var text = ""
        text.unicodeScalars.append(contentsOf: bytes.map { Unicode.Scalar($0) })
        return text
    }
}
