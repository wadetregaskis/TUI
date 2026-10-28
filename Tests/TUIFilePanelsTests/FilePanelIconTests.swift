//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelIconTests.swift
//
//  A file panel's icons: the kind each item is, the glyph each kind is drawn
//  with, and which glyphs the terminal gets.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

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

    @Test("An app's icon takes the kind's place, in its two cells, and nil keeps the kind's")
    func appIcons() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        var asked: [String: String] = [:]
        let driver = FilePanelDriver {
            panel(fixture, caller: caller, icons: nil)
                .fileDialogIcon { url, type in
                    asked[url.lastPathComponent] = type.identifier
                    return type.conforms(to: .pdf) ? Text("P") : nil
                }
        }
        let shown = await driver.waitFor("notes.md")
        // One cell drawn in the two an emoji takes, so the name stays where
        // the others' are.
        #expect(shown.contains("P  gamma.pdf") || shown.contains(" P gamma.pdf"), "\(shown)")
        #expect(!shown.contains("📕"))
        #expect(shown.contains("📝 beta.txt"))
        #expect(shown.contains("📁 Alpha "))
        #expect(asked["gamma.pdf"] == UTType.pdf.identifier)
        let gamma = try #require(driver.position(of: "gamma.pdf"))
        let beta = try #require(driver.position(of: "beta.txt"))
        // In cells, the same column: the position is a character's offset,
        // and the emoji before beta.txt is one character of two cells.
        #expect(gamma.x == beta.x + 1)
    }

    @Test("Without emoji or symbols, an app's icon still draws, and a folder it gives one has no slash")
    func appIconsWithoutGlyphs() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            panel(fixture, caller: caller, icons: FilePanelIcon.none)
                .fileDialogIcon { _, type in type.conforms(to: .directory) ? Text("D") : nil }
        }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Alpha "), "\(shown)")
        #expect(!shown.contains("Alpha/"))
        #expect(shown.contains("beta.txt"))
    }

    @Test("The icon modifier's environment value is the same from frame to frame")
    func appIconsCompareEqual() {
        let harness = InputChainHarness(width: 40, height: 4) { _ in }
        var seen: [FileDialogItemViews?] = []
        // Made inside each pass, as an app's body makes it: a new modifier
        // value each frame, whose kept box is what makes the two equal.
        func view() -> some View {
            EnvironmentReader(\.fileDialogIcon) { seen.append($0) }
                .fileDialogIcon { _, _ in Text("x") }
        }
        harness.frame(view())
        harness.frame(view())
        #expect(seen.count >= 2)
        #expect(seen.first != nil)
        #expect(Set(seen.map { $0.map { ObjectIdentifier($0.box) } }).count == 1)
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

/// Hands `read` the environment value at `keyPath` when it renders.
private struct EnvironmentReader<Value>: View {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let read: (Value) -> Void

    init(_ keyPath: KeyPath<EnvironmentValues, Value>, read: @escaping (Value) -> Void) {
        self.keyPath = keyPath
        self.read = read
    }

    var body: some View {
        _EnvironmentReaderCore(keyPath: keyPath, read: read)
    }
}

private struct _EnvironmentReaderCore<Value>: View, Renderable {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let read: (Value) -> Void
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        read(context.environment[keyPath: keyPath])
        return FrameBuffer(lines: [" "])
    }
}
