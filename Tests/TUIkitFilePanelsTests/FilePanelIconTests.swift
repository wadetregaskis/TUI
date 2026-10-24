//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelIconTests.swift
//
//  A file panel's icons: the kind each item is, the glyph each kind is drawn
//  with, and which glyphs the terminal gets.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel icons", .serialized)
struct FilePanelIconTests {
    @Test("An item's kind is its type's narrowest: code before text, a PDF before a document")
    func kinds() throws {
        let kind = { (type: UTType) in FileKind.of(type, isFolder: false, isSymbolicLink: false) }
        #expect(FileKind.of(.folder, isFolder: true, isSymbolicLink: false) == .folder)
        #expect(FileKind.of(.folder, isFolder: true, isSymbolicLink: true) == .alias)
        #expect(FileKind.of(.plainText, isFolder: false, isSymbolicLink: true) == .alias)
        #expect(kind(.applicationBundle) == .application)
        #expect(kind(.pdf) == .pdf)
        #expect(kind(.png) == .image)
        #expect(kind(.mp3) == .audio)
        #expect(kind(.quickTimeMovie) == .video)
        #expect(kind(.zip) == .archive)
        #expect(kind(.swiftSource) == .code)
        #expect(kind(.json) == .code)
        #expect(kind(.shellScript) == .code)
        #expect(kind(.plainText) == .text)
        #expect(kind(try #require(UTType(filenameExtension: "md"))) == .text)
        #expect(kind(.data) == .document)
        #expect(kind(.spreadsheet) == .document)
    }

    @Test("Each kind has an emoji of its own, two cells wide with no selector")
    func emoji() {
        let glyphs = FileKind.allCases.map(\.emoji)
        #expect(Set(glyphs).count == FileKind.allCases.count)
        for glyph in glyphs {
            #expect(glyph.unicodeScalars.count == 1, "\(glyph)")
            #expect(glyph.unicodeScalars.first?.properties.isEmojiPresentation == true, "\(glyph)")
            #expect(glyph.strippedLength == 2, "\(glyph)")
        }
    }

    #if canImport(AppKit)
        @Test("Each kind's SF Symbol is one the table knows")
        func symbolsKnown() {
            for kind in FileKind.allCases {
                #expect(SFSymbol.glyph(named: kind.symbolName) != nil, "\(kind.symbolName)")
            }
        }
    #endif

    @Test("Emoji where the terminal draws emoji chrome; else SF Symbols where they draw; else none")
    func tiers() {
        #expect(FilePanelIcon.resolve(supportsEmojiChrome: true, symbolsRender: true) == .emoji)
        #expect(FilePanelIcon.resolve(supportsEmojiChrome: false, symbolsRender: true) == .symbols)
        #expect(FilePanelIcon.resolve(supportsEmojiChrome: false, symbolsRender: false) == .none)
    }

    /// A panel over `fixture`'s root, in a terminal that draws emoji chrome.
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller, icons: FilePanelIcon?) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() }
        )
        .environment(\.supportsEmojiChrome, true)
        .environment(\.filePanelIcons, icons)
    }

    @Test("In a terminal that draws emoji chrome, each name has its kind's emoji, and a folder no slash")
    func emojiIcons() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        // Unpinned: the terminal's own, which here draws emoji.
        let driver = FilePanelDriver { panel(fixture, caller: caller, icons: nil) }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("📁 Alpha "), "\(shown)")
        #expect(!shown.contains("Alpha/"))
        #expect(shown.contains("🔗 linked "))
        #expect(shown.contains("📝 beta.txt"))
        #expect(shown.contains("📕 gamma.pdf"))
        // Typing still finds a name by its first letters, past the icon.
        driver.press(.character("g"))
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("gamma.pdf").path])
    }

    @Test("With no icons, a folder's name ends in a slash")
    func noIcons() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, icons: FilePanelIcon.none) }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Alpha/"))
        #expect(!shown.contains("📁"))
    }
}
