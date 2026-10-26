//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipboardMIMETests.swift
//
//  OSC 5522, kitty's clipboard protocol: the write's spelling, its chunks,
//  which copies take it, and which terminals are asked whether they speak it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

@MainActor
@Suite("OSC 5522: a copy in every form")
struct ClipboardMIMETests {
    /// The packets of an OSC 5522 transaction, as (metadata, payload).
    private func packets(_ sequence: String) -> [(metadata: String, payload: String)] {
        sequence.components(separatedBy: "\u{1B}]5522;").dropFirst().map { packet in
            let body = packet.components(separatedBy: "\u{1B}\\")[0]
            let parts = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
        }
    }

    @Test("A write opens, sends each type as wdata, plain text first, and closes")
    func spelling() throws {
        let sequence = try #require(
            ClipboardSequence.write(
                "hi", representations: [ClipboardRepresentation(type: "text/html", text: "<b>hi</b>")]))
        let mime = { (type: String) in "type=wdata:mime=" + Data(type.utf8).base64EncodedString() }
        #expect(packets(sequence).map(\.metadata) == ["type=write", mime("text/plain"), mime("text/html"), "type=wdata"])
        #expect(packets(sequence)[1].payload == Data("hi".utf8).base64EncodedString())
        #expect(packets(sequence)[2].payload == Data("<b>hi</b>".utf8).base64EncodedString())
        #expect(sequence.hasSuffix("\u{1B}]5522;type=wdata\u{1B}\\"), "the close carries no type and no data")
    }

    @Test("A large part goes in packets of at most 4096 bytes, in order")
    func chunks() throws {
        let bytes = Data((0..<10_000).map { UInt8($0 % 251) })
        let sequence = try #require(
            ClipboardSequence.write("x", representations: [ClipboardRepresentation(type: "image/png", data: bytes)]))
        let png = packets(sequence).filter { $0.metadata.hasSuffix(Data("image/png".utf8).base64EncodedString()) }
        let decoded = try png.map { try #require(Data(base64Encoded: $0.payload)) }
        #expect(decoded.map(\.count) == [4096, 4096, 1808])
        #expect(decoded.reduce(Data(), +) == bytes)
    }

    @Test("An empty copy sends nothing; an empty part is left out, as its packet would close the write")
    func empties() throws {
        #expect(ClipboardSequence.write("", representations: []) == nil)
        let sequence = try #require(
            ClipboardSequence.write("a", representations: [ClipboardRepresentation(type: "text/html", data: Data())]))
        #expect(packets(sequence).count == 3)
    }

    @Test("A terminal copy goes by OSC 5522 where the terminal takes it, with every form")
    func terminalRoute() {
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: false, mime: true)
        let markdown = ClipboardRepresentation(type: "text/markdown", text: "**a**")
        #expect(writer.write("a", representations: [markdown], announcingSuccess: false) == .copied)
        let sent = writer.takePendingSequences()
        #expect(sent.hasPrefix("\u{1B}]5522;type=write\u{1B}\\"))
        #expect(sent.contains(Data("text/markdown".utf8).base64EncodedString()))
        #expect(!sent.contains("\u{1B}]52;"))
    }

    @Test("A copy with no text — a picture — goes by OSC 5522 alone, and nowhere else")
    func pictureAlone() throws {
        let png = ClipboardRepresentation(type: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let sequence = try #require(ClipboardSequence.write("", representations: [png]))
        let mime = { (type: String) in "type=wdata:mime=" + Data(type.utf8).base64EncodedString() }
        #expect(packets(sequence).map(\.metadata) == ["type=write", mime("image/png"), "type=wdata"])
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: false, mime: true)
        #expect(writer.write("", representations: [png], announcingSuccess: false) == .copied)
        #expect(writer.takePendingSequences().contains(Data("image/png".utf8).base64EncodedString()))
        let osc52 = ClipboardWriter.stated(terminal: .honoured, isLocal: false, mime: false)
        #expect(osc52.write("", representations: [png], announcingSuccess: false) == .unavailable)
        #expect(osc52.takePendingSequences().isEmpty, "OSC 52 carries text")
    }

    #if canImport(UniformTypeIdentifiers)
    @Test("An OSC 5522 paste is asked for only the types the focused view's paste command takes")
    func focusedPasteTypes() {
        let harness = InputChainHarness(width: 40, height: 6)
        func page() -> some View {
            Button("Attach") {}.onPasteCommand(of: [.pdf]) { _ in }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(harness.handler.acceptsPaste(ofMIMEType: "application/pdf"))
        #expect(!harness.handler.acceptsPaste(ofMIMEType: "image/png"), "not a type it takes")
    }

    @Test("A copy command writes an item's typed representations beside its text")
    func copyCommandWritesTypes() async throws {
        final class Written: @unchecked Sendable {
            var text: String?
            var types: [String] = []
        }
        let written = Written()
        let clipboard = ClipboardAccess(
            put: { text, _ in written.text = text; return .copied },
            putRepresentations: { text, representations, _ in
                written.text = text
                written.types = representations.map(\.type)
                return .copied
            },
            read: { nil })
        let item = NSItemProvider(object: "caption" as NSString)
        item.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
            completion(Data([0x89, 0x50, 0x4E, 0x47]), nil)
            return nil
        }
        // HTML conforms to `.text`, and is a representation of its own, not
        // the copy's text.
        item.registerDataRepresentation(forTypeIdentifier: "public.html", visibility: .all) { completion in
            completion(Data("<b>caption</b>".utf8), nil)
            return nil
        }
        ClipboardCommand.write([item], to: clipboard)
        await settle(until: { written.text != nil })
        #expect(written.text == "caption")
        #expect(Set(written.types) == ["image/png", "text/html"], "\(written.types)")
    }
    #endif

    @Test("Elsewhere a copy is its text: OSC 52 to a terminal without it, and this machine's helper")
    func textElsewhere() {
        let markdown = ClipboardRepresentation(type: "text/markdown", text: "**a**")
        let osc52 = ClipboardWriter.stated(terminal: .honoured, isLocal: false, mime: false)
        osc52.write("a", representations: [markdown], announcingSuccess: false)
        #expect(osc52.takePendingSequences() == "\u{1B}]52;c;YQ==\u{1B}\\")
        let log = SystemClipboardLog()
        let local = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log, mime: true)
        local.write("a", representations: [markdown], announcingSuccess: false)
        #expect(log.writes == ["a"])
        #expect(local.takePendingSequences().isEmpty)
    }

    @Test("The ladder: an override, then TUIKIT_OSC5522, then what the terminal said")
    func ladder() {
        #expect(TerminalClient.mimeClipboard(environment: [:], override: nil, detected: true))
        #expect(!TerminalClient.mimeClipboard(environment: [:], override: nil, detected: false))
        #expect(TerminalClient.mimeClipboard(environment: ["TUIKIT_OSC5522": "1"], override: nil, detected: false))
        #expect(!TerminalClient.mimeClipboard(environment: ["TUIKIT_OSC5522": "0"], override: nil, detected: true))
        #expect(!TerminalClient.mimeClipboard(environment: ["TUIKIT_OSC5522": "1"], override: false, detected: true))
    }

    @Test("Only hosts that consume DECRQM, and may say yes, are asked")
    func whoIsAsked() {
        #expect(TerminalClient.mayAskMIMEClipboard(environment: [:], program: .ghostty))
        #expect(TerminalClient.mayAskMIMEClipboard(environment: ["TERM": "xterm-kitty"], program: .unidentified))
        #expect(!TerminalClient.mayAskMIMEClipboard(environment: [:], program: .unidentified))
        // Apple Terminal prints DECRQM's final byte; iTerm2 answers "permanently reset".
        #expect(!TerminalClient.mayAskMIMEClipboard(environment: [:], program: .appleTerminal))
        #expect(!TerminalClient.mayAskMIMEClipboard(environment: [:], program: .iTerm2))
        #expect(!TerminalClient.mayAskMIMEClipboard(environment: ["TERM": "xterm-kitty"], program: .tmux))
    }
}
