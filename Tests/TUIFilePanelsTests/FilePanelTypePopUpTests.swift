//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelTypePopUpTests.swift
//
//  A file panel's file-type pop-up: when it shows, what it offers, and what a
//  choice in it does — to an open panel's files, and to a save panel's name.
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
@Suite("File panel type pop-up", .serialized)
struct FilePanelTypePopUpTests {
    private static let markdown = UTType(filenameExtension: "md") ?? .plainText

    private func openRequest(_ types: [UTType], picker: Visibility = .automatic, files: Bool = true)
        -> FilePanelRequest
    {
        var request = FilePanelRequest(
            purpose: .open(allowsMultipleSelection: false),
            rule: FileChoiceRule(allowedContentTypes: types, choosesFiles: files), title: "Open",
            confirmationLabel: "Open", startDirectory: URL(fileURLWithPath: "/"))
        request.contentTypePicker = picker
        return request
    }

    @Test("An open panel offers its types together, each, and All Files, where it has several")
    func openChoices() {
        #expect(
            openRequest([.pdf, .json]).typeChoices == [.supported, .type(.pdf), .type(.json), .allFiles])
        #expect(openRequest([.pdf]).initialTypeChoice == .type(.pdf))
        #expect(openRequest([.pdf, .json]).initialTypeChoice == .supported)
    }

    @Test("One type shows the pop-up only when asked; none, or no files to choose, never")
    func whenItShows() {
        #expect(openRequest([.pdf]).typeChoices == nil)
        #expect(openRequest([.pdf], picker: .visible).typeChoices == [.type(.pdf), .allFiles])
        #expect(openRequest([.pdf, .json], picker: .hidden).typeChoices == nil)
        #expect(openRequest([], picker: .visible).typeChoices == nil)
        // A mover's panel, or one choosing a folder to save into, takes no files.
        #expect(openRequest([.folder, .pdf], picker: .visible, files: false).typeChoices == nil)
    }

    @Test("A save panel's Format pop-up offers the types it saves as, and no All Files")
    func saveChoices() {
        let request = FilePanelRequest(
            purpose: .save(contentTypes: [.plainText, Self.markdown]), rule: FileChoiceRule(), title: "Save",
            confirmationLabel: "Save", startDirectory: URL(fileURLWithPath: "/"))
        #expect(request.typeChoices == [.type(.plainText), .type(Self.markdown)])
    }

    @Test("The customization reaches the request")
    func customizationApplies() {
        var customization = FileDialogCustomization()
        customization.contentTypePicker = .visible
        var request = openRequest([.pdf])
        FilePanelPresenter<EmptyView>.apply(customization, to: &request)
        #expect(request.contentTypePicker == .visible)
    }

    @Test("A Format choice gives the name its type's extension; the name's type is the one it names")
    func formatRenames() {
        let types = [UTType.plainText, Self.markdown]
        #expect(SaveName.renamed("notes.txt", as: Self.markdown, among: types) == "notes.md")
        #expect(SaveName.renamed("notes.md", as: .plainText, among: types) == "notes.txt")
        #expect(SaveName.renamed("notes.md", as: Self.markdown, among: types) == "notes.md")
        #expect(SaveName.renamed("notes", as: Self.markdown, among: types) == "notes.md")
        // An extension of none of the types is part of the name, as a save keeps it.
        #expect(SaveName.renamed("v1.2", as: .plainText, among: types) == "v1.2.txt")
        #expect(SaveName.renamed("", as: .plainText, among: types).isEmpty)
        // Markdown conforms to plain text, but `.md` names Markdown itself.
        #expect(SaveName.type(for: "notes.md", among: types) == Self.markdown)
        #expect(SaveName.type(for: "notes.txt", among: types) == .plainText)
        #expect(SaveName.type(for: "notes", among: types) == .plainText)
    }

    /// An open panel over `fixture`'s root taking PDFs and JSON.
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: { openRequest([.pdf, .json]).with(fixture) },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    @Test("All Files lets a file of another type be chosen; a type of the caller's narrows to it")
    func allFilesWidens() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let shown = await driver.waitFor("notes.md")
        #expect(capless(shown).contains("Show: All Supported Files ▾"), "\(shown)")
        // Rows: Alpha/, linked/, beta.txt — dimmed, so Return chooses nothing.
        driver.press(.down, times: 2)
        driver.press(.enter)
        #expect(caller.heard.isEmpty)
        // Tab to the pop-up; open it and choose All Files, the last.
        driver.press(.tab)
        driver.press(.enter)
        driver.press(.end)
        driver.press(.enter)
        // The pop-up is as wide as its widest choice, so its value is padded.
        await settle { capless(driver.screen()).contains("Show: All Files   ") }
        // Back to the folder, whose cursor is still on beta.txt: it is chosen.
        driver.press([KeyEvent(key: .tab, shift: true)])
        await settle { driver.press(.enter); return !caller.heard.isEmpty }
        #expect(caller.chosenPaths == [fixture.url("beta.txt").path])
    }
}

extension FilePanelTypePopUpTests {
    @Test("A save panel's Format choice gives the name its extension, and the save is of that type")
    func formatChoiceRenames() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        var saved: [URL] = []
        let presented = FilePanelCaller()
        let driver = FilePanelDriver {
            FilePanelPresenter(
                content: Text("Page"), isPresented: presented.binding,
                request: {
                    FilePanelRequest(
                        purpose: .save(contentTypes: [.plainText, Self.markdown]), rule: FileChoiceRule(),
                        title: "Save", confirmationLabel: "Save", defaultFilename: "draft.txt",
                        startDirectory: fixture.root, homeDirectory: fixture.root)
                },
                onChoose: { saved = $0 }, onCancel: {})
        }
        let shown = await driver.waitFor("notes.md")
        #expect(capless(shown).contains("Format: Text "), "\(shown)")
        // From the name field past the path, the view switcher and the
        // folder to the pop-up; open it, and choose Markdown, the one after
        // the current.
        driver.press(.tab, times: 4)
        driver.press(.enter)
        driver.press(.down)
        driver.press(.enter)
        let renamed = await driver.waitFor("draft.md")
        #expect(capless(renamed).contains("Format: Markdown Text"), "\(renamed)")
        // Save is the default button.
        driver.press([KeyEvent(key: .tab, shift: true)])
        driver.press(.tab, times: 4)
        driver.press(.enter)
        await settle { !saved.isEmpty }
        #expect(saved.map(\.lastPathComponent) == ["draft.md"])
    }
}

extension FilePanelRequest {
    /// This request, opening on `fixture`'s root, which is also its home.
    fileprivate func with(_ fixture: FilePanelFixture) -> Self {
        var request = self
        request.startDirectory = fixture.root
        request.homeDirectory = fixture.root
        return request
    }
}

/// `screen` without a pop-up's caps — the control style's half blocks or a
/// lines face's brackets — and the blank inside each, so an expectation reads
/// the label and its value whatever face the control is drawn in.
private func capless(_ screen: String) -> String {
    screen.replacingOccurrences(of: #"[▐(] "#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #" [▌)]"#, with: "", options: .regularExpression)
}
