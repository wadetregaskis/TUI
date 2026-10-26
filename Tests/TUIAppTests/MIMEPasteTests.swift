//  🖥️ TUI — A Terminal UI framework for Swift
//  MIMEPasteTests.swift
//
//  A paste through OSC 5522 paste events: the terminal lists the clipboard's
//  types under a one-time password, the app reads its text and first picture,
//  and the paste arrives as one key event carrying both.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUICore
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@testable import TUIApp
@testable import TUIFoundation

@MainActor
@Suite("OSC 5522 paste events")
struct MIMEPasteTests {
    static let password = Data("one-time".utf8).base64EncodedString()

    /// `OSC 5522 ; <metadata> [; <payload as base64>] ST`.
    static func packet(_ metadata: String, _ payload: [UInt8]? = nil) -> String {
        "\u{1B}]5522;" + metadata + (payload.map { ";" + Data($0).base64EncodedString() } ?? "") + "\u{1B}\\"
    }

    static func mime(_ type: String) -> String { Data(type.utf8).base64EncodedString() }

    /// The paste event a terminal sends when the user pastes, listing `types`.
    static func pasteEvent(_ types: String) -> String {
        packet("type=read:status=OK:pw=\(password)")
            + packet("type=read:status=DATA:pw=\(password):mime=\(mime("."))", Array((types + "\n").utf8))
            + packet("type=read:status=DONE:pw=\(password)")
    }

    static let picture = (0..<5000).map { UInt8($0 % 256) }

    /// The reply to the app's read: the text, then the picture in two packets.
    static let dataReply =
        packet("type=read:status=OK")
        + packet("type=read:status=DATA:mime=\(mime("text/plain"))", Array("hi".utf8))
        + packet("type=read:status=DATA:mime=\(mime("image/png"))", Array(picture[..<4096]))
        + packet("type=read:status=DATA:mime=\(mime("image/png"))", Array(picture[4096...]))
        + packet("type=read:status=DONE")

    private func feed(_ session: inout MIMEPasteSession, _ text: String) -> [MIMEPasteSession.Action] {
        text.components(separatedBy: "\u{1B}]5522;").dropFirst().compactMap { piece in
            session.receive(Substring(piece.components(separatedBy: "\u{1B}\\")[0]))
        }
    }

    @Test("A paste event is answered by a read of the text and the first picture, under its password")
    func request() throws {
        var session = MIMEPasteSession()
        let actions = feed(&session, Self.pasteEvent("text/html text/plain image/png image/jpeg"))
        let request = try #require(actions.first)
        #expect(actions.count == 1)
        let expected =
            "\u{1B}]5522;type=read:pw=\(Self.password):name=\(Self.mime("Paste event"));"
            + Self.mime("text/plain image/png") + "\u{1B}\\"
        #expect(request == .request(expected))
    }

    @Test("Asked, a paste reads the text and every listed type the app takes, never the list or text's other names")
    func readsWhatTheAppTakes() {
        let listed = [".", "text/plain", "UTF8_STRING", "text/html", "image/png", "image/tiff", "application/pdf"]
        let wanted = MIMEPasteSession.wanted(
            from: listed, accepting: { $0 == "application/pdf" || $0 == "image/tiff" })
        #expect(wanted == ["text/plain", "image/tiff", "application/pdf"])
        #expect(MIMEPasteSession.wanted(from: listed) == ["text/plain", "image/png"], "unasked: the first picture")
        var session = MIMEPasteSession()
        session.acceptsType = { $0 == "application/pdf" }
        let actions = feed(&session, Self.pasteEvent("text/plain application/pdf image/png"))
        let expected =
            "\u{1B}]5522;type=read:pw=\(Self.password):name=\(Self.mime("Paste event"));"
            + Self.mime("text/plain application/pdf") + "\u{1B}\\"
        #expect(actions == [.request(expected)])
    }

    @Test("A middle-click's paste of the primary selection reads the primary selection")
    func primarySelection() {
        var session = MIMEPasteSession()
        let event = Self.pasteEvent("text/plain")
            .replacingOccurrences(of: "status=OK:pw=", with: "status=OK:loc=primary:pw=")
        guard case .request(let request)? = feed(&session, event).first else {
            Issue.record("a request")
            return
        }
        #expect(request.hasPrefix("\u{1B}]5522;type=read:loc=primary:pw="))
    }

    @Test("The read's packets become one paste: the text, and the picture's bytes in order")
    func paste() {
        var session = MIMEPasteSession()
        _ = feed(&session, Self.pasteEvent("text/plain image/png"))
        let actions = feed(&session, Self.dataReply)
        #expect(actions == [.paste(text: "hi", attachments: [PasteAttachment(type: "image/png", bytes: Self.picture)])])
    }

    @Test("A clipboard of a picture alone is read and pasted without text; one of neither asks nothing")
    func pictureAlone() {
        var session = MIMEPasteSession()
        #expect(feed(&session, Self.pasteEvent("image/png")).count == 1)
        var nothing = MIMEPasteSession()
        #expect(feed(&nothing, Self.pasteEvent("application/x-something")).isEmpty)
    }

    @Test("A refused read loses the paste, and the next paste event starts afresh")
    func refused() {
        var session = MIMEPasteSession()
        _ = feed(&session, Self.pasteEvent("text/plain"))
        #expect(feed(&session, Self.packet("type=read:status=EPERM")).isEmpty)
        #expect(feed(&session, Self.pasteEvent("text/plain")).count == 1)
    }

    @Test("Through the parser: the request is written, and the paste arrives as one event before what follows")
    func throughTheParser() throws {
        final class Box {
            var bytes: [UInt8] = []
            var sent: [String] = []
        }
        let box = Box()
        let terminal = Terminal()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        terminal.exchangeTransport = Terminal.ExchangeTransport(
            send: { box.sent.append($0) }, waitForInput: { _ in true })
        func drain() -> [TerminalInput] {
            var events: [TerminalInput] = []
            var quiet = 0
            while quiet < 8 {
                if let event = terminal.readEvent() {
                    events.append(event)
                    quiet = 0
                } else {
                    quiet += 1
                }
            }
            return events
        }
        box.bytes = Array(Self.pasteEvent("text/plain image/png").utf8)
        #expect(drain().isEmpty, "the paste event types nothing")
        #expect(box.sent.count == 1)
        #expect(box.sent.first?.hasPrefix("\u{1B}]5522;type=read:pw=") == true)
        box.bytes = Array((Self.dataReply + "x").utf8)
        let events = drain()
        #expect(events.count == 2)
        guard case .key(let paste)? = events.first, case .key(let x)? = events.last else {
            Issue.record("two key events, got \(events)")
            return
        }
        #expect(paste.key == .paste("hi"))
        #expect(paste.pasteAttachments == [PasteAttachment(type: "image/png", bytes: Self.picture)])
        #expect(x.key == .character("x"))
    }

    #if canImport(UniformTypeIdentifiers)
    @Test("A paste command takes a paste whose types conform to its own, and declares no other")
    func pasteCommandTakes() {
        func paste(_ text: String, _ types: [String]) -> KeyEvent {
            KeyEvent(key: .paste(text), pasteAttachments: types.map { PasteAttachment(type: $0, bytes: []) })
        }
        #expect(Text.takes(paste("", ["application/pdf"]), [.pdf]))
        #expect(Text.takes(paste("", ["image/png"]), [.image]), "a PNG is an image")
        #expect(!Text.takes(paste("", ["image/png"]), [.pdf]))
        #expect(Text.takes(paste("hi", []), [.plainText]))
        #expect(!Text.takes(paste("hi", []), [.png]), "text is no picture")
        #expect(!Text.takes(KeyEvent(key: .character("v")), [.plainText]), "not a paste")
    }

    @Test("A paste command for pictures is offered the picture, as its UTType; one for text, the text")
    func itemProvider() throws {
        let picture = PasteAttachment(type: "image/png", bytes: Self.picture)
        let item = try #require(Text.pastedItem(text: "", attachments: [picture]))
        #expect(item.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        #expect(!item.canLoadObject(ofClass: NSString.self), "no text pasted")
        let text = try #require(Text.pastedItem(text: "hi", attachments: []))
        #expect(text.canLoadObject(ofClass: NSString.self))
        #expect(Text.pastedItem(text: "", attachments: []) == nil, "a paste of nothing offers nothing")
    }
    #endif
}
