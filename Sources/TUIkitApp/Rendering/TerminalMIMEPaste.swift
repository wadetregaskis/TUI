//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalMIMEPaste.swift
//
//  A paste that can be more than text: kitty's paste events (private mode
//  5522), where the terminal says what types the clipboard holds and the
//  application reads the ones it wants — a picture among them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

/// One paste through OSC 5522, from the terminal's word that the user pasted
/// to the data the paste carries.
///
/// With mode 5522 set, a paste arrives not as bracketed text but as an
/// unsolicited read reply listing the clipboard's types, under a one-time
/// password (measured from kitty's source, `kitty/clipboard.py`):
///
/// ```
/// OSC 5522 ; type=read:status=OK:pw=<b64> ST
/// OSC 5522 ; type=read:status=DATA:pw=<b64>:mime=Lg== ; <b64 "text/plain image/png\n"> ST
/// OSC 5522 ; type=read:status=DONE:pw=<b64> ST
/// ```
///
/// The session then asks for the text and the first picture with that
/// password (and the name the specification asks for, "Paste event"), and
/// collects the reply's `DATA` packets, a type's in order, until `DONE`. What
/// it read becomes one paste: its text as ``Key/paste(_:)`` would carry a
/// bracketed one, and anything else beside it (``PasteAttachment``).
struct MIMEPasteSession {
    /// What the session asks of the terminal or hands the app.
    enum Action: Equatable {
        /// Write this read request.
        case request(String)
        /// The paste is complete.
        case paste(text: String, attachments: [PasteAttachment])
    }

    private enum Phase {
        case idle
        /// A paste event: its password, whether it pastes the primary
        /// selection, and the types listed so far.
        case listing(password: String, primary: Bool, types: [String])
        /// The read for it: the bytes of each type, in arrival order.
        case reading(parts: [(type: String, bytes: [UInt8])])
    }

    private var phase = Phase.idle

    /// The text types asked for, most preferred first: the first the
    /// clipboard lists is read.
    static let textTypes = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"]

    /// Takes one packet, the body of `OSC 5522 ; … ST`, and says what to do.
    mutating func receive(_ body: Substring) -> Action? {
        let (metadata, payload) = Self.split(body)
        guard metadata["type"] == "read", let status = metadata["status"] else { return nil }
        switch (phase, status) {
        case (.idle, "OK"):
            // Unsolicited, with a password: the user pasted.
            // A middle-click's paste is of the primary selection, and says so.
            guard let password = metadata["pw"] else { return nil }
            phase = .listing(password: password, primary: metadata["loc"] == "primary", types: [])
        case (.listing(let password, let primary, let types), "DATA") where Self.decodedText(metadata["mime"]) == ".":
            let listed = Self.decoded(payload).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            let more = listed.split(whereSeparator: \.isWhitespace).map(String.init)
            phase = .listing(password: password, primary: primary, types: types + more)
        case (.listing(let password, let primary, let types), "DONE"):
            let wanted = Self.wanted(from: types)
            guard !wanted.isEmpty else {
                phase = .idle
                return nil
            }
            phase = .reading(parts: [])
            return .request(Self.readRequest(wanted, password: password, primary: primary))
        case (.reading(var parts), "DATA"):
            guard let type = Self.decodedText(metadata["mime"]), let bytes = Self.decoded(payload) else { return nil }
            if parts.last?.type == type {
                parts[parts.count - 1].bytes += bytes
            } else {
                parts.append((type, bytes))
            }
            phase = .reading(parts: parts)
        case (.reading(let parts), "DONE"):
            phase = .idle
            return Self.paste(parts)
        case (_, let status) where status.hasPrefix("E"):
            // Refused, busy, or no such type: the paste is lost, as one the
            // terminal never delivered would be.
            phase = .idle
        default:
            break
        }
        return nil
    }

    /// The types to read of those listed: the first text type, and the first
    /// picture.
    static func wanted(from types: [String]) -> [String] {
        var wanted: [String] = []
        if let text = textTypes.first(where: types.contains) { wanted.append(text) }
        if let picture = types.first(where: { $0.hasPrefix("image/") }) { wanted.append(picture) }
        return wanted
    }

    /// The read of `types` under a paste event's one-time password, of the
    /// primary selection where the paste was.
    static func readRequest(_ types: [String], password: String, primary: Bool = false) -> String {
        let name = Data("Paste event".utf8).base64EncodedString()
        let list = Data(types.joined(separator: " ").utf8).base64EncodedString()
        let location = primary ? ":loc=primary" : ""
        return "\u{1B}]5522;type=read\(location):pw=\(password):name=\(name);\(list)\u{1B}\\"
    }

    /// The paste `parts` make: the text type's bytes as the text, every other
    /// type's beside it.
    private static func paste(_ parts: [(type: String, bytes: [UInt8])]) -> Action? {
        guard !parts.isEmpty else { return nil }
        // Not UTF-8: read a byte to a character, as a bracketed paste's is.
        let text = parts.first { textTypes.contains($0.type) }.flatMap {
            String(bytes: $0.bytes, encoding: .utf8) ?? String(bytes: $0.bytes, encoding: .isoLatin1)
        } ?? ""
        let attachments = parts.filter { !textTypes.contains($0.type) }.map { PasteAttachment(type: $0.type, bytes: $0.bytes) }
        guard !text.isEmpty || !attachments.isEmpty else { return nil }
        return .paste(text: text, attachments: attachments)
    }

    /// A packet's `key=value` pairs (values as sent) and its payload.
    private static func split(_ body: Substring) -> ([String: String], Substring) {
        let semicolon = body.firstIndex(of: ";")
        let head = semicolon.map { body[..<$0] } ?? body
        let payload = semicolon.map { body[body.index(after: $0)...] } ?? ""
        var metadata: [String: String] = [:]
        for pair in head.split(separator: ":") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { metadata[String(parts[0])] = String(parts[1]) }
        }
        return (metadata, payload)
    }

    private static func decoded(_ base64: Substring) -> [UInt8]? {
        Data(base64Encoded: String(base64)).map { [UInt8]($0) }
    }

    private static func decodedText(_ base64: String?) -> String? {
        base64.flatMap { Data(base64Encoded: $0) }.flatMap { String(bytes: $0, encoding: .utf8) }
    }
}

extension Terminal {
    /// Mode 5522 on: a paste arrives as OSC 5522 paste events, which
    /// ``MIMEPasteSession`` turns into a paste that may carry a picture.
    static let mimePasteEventsOn = "\u{1B}[?5522h"

    /// Sets mode 5522 where the terminal takes OSC 5522
    /// (``TerminalClient/mimeClipboard``); called once the host is asked, and
    /// on every resume, since ``inputModesOff`` resets it.
    func enableMIMEPasteEventsIfSupported() {
        guard TerminalClient.mimeClipboard else { return }
        writeImmediate(Self.mimePasteEventsOn)
    }

    /// Hands the OSC 5522 reply of `length` bytes at the head of the input
    /// buffer to the paste session, before the parser consumes it: a request
    /// it makes is written at once, and a paste it completes is the next input
    /// (``completedMIMEPaste``), as a bracketed paste's text is.
    func noteClipboardReply(headOfInputLength length: Int) {
        let introducer: [UInt8] = Array("\u{1B}]5522;".utf8)
        guard length > introducer.count, input.count >= length,
            (0..<introducer.count).allSatisfy({ input[$0] == introducer[$0] })
        else { return }
        // Up to the terminator: ST (two bytes) or BEL (one).
        let end = input[length - 1] == 0x07 ? length - 1 : length - 2
        var bytes: [UInt8] = []
        bytes.reserveCapacity(end - introducer.count)
        for index in introducer.count..<end { bytes.append(input[index]) }
        // ASCII by the protocol: keys, values and payload are base64.
        guard let body = String(bytes: bytes, encoding: .ascii) else { return }
        switch mimePaste.receive(Substring(body)) {
        case .request(let request): writeImmediate(request)
        case .paste(let text, let attachments):
            completedMIMEPaste = .key(KeyEvent(key: .paste(text), pasteAttachments: attachments))
        case nil: break
        }
    }
}
