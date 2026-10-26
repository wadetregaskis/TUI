//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelLayoutTests.swift
//
//  How a file panel lays out its parts: the room between them at each
//  control size.
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
@Suite("File panel layout", .serialized)
struct FilePanelLayoutTests {
    @Test("A blank row parts the panel's parts at .regular and .large, two at .extraLarge, none when small")
    func spacingFollowsControlSize() {
        #expect(FilePanel.spacing(controlSize: .mini, verticalSizeClass: .regular) == 0)
        #expect(FilePanel.spacing(controlSize: .small, verticalSizeClass: .regular) == 0)
        #expect(FilePanel.spacing(controlSize: .regular, verticalSizeClass: .regular) == 1)
        #expect(FilePanel.spacing(controlSize: .large, verticalSizeClass: nil) == 1)
        #expect(FilePanel.spacing(controlSize: .extraLarge, verticalSizeClass: .regular) == 2)
        // A short terminal stays dense whatever the size.
        #expect(FilePanel.spacing(controlSize: .extraLarge, verticalSizeClass: .compact) == 0)
    }

    /// A save panel over `fixture`'s root, at `size`.
    private func savePanel(
        _ fixture: FilePanelFixture, caller: FileExporterCaller, size: ControlSize
    ) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .save(contentTypes: [.plainText]), rule: FileChoiceRule(), title: "Save",
                    confirmationLabel: "Save", defaultFilename: "note.txt", startDirectory: fixture.root,
                    homeDirectory: fixture.root)
            },
            onChoose: { _ in }, onCancel: {}
        )
        .controlSize(size)
    }

    /// The screen's rows from the name field's to the table header's.
    private func rows(between screen: String) -> [Substring] {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        guard let name = lines.firstIndex(where: { $0.contains("Save As:") }),
            let header = lines.firstIndex(where: { $0.contains("Name") && $0.contains("Size") })
        else { return [] }
        return Array(lines[name...header])
    }

    @Test("At .regular a blank row parts the name field, the path and the folder; at .small none does")
    func blankRowsOnScreen() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        for (size, expected) in [(ControlSize.regular, 5), (.small, 3)] {
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { savePanel(fixture, caller: caller, size: size) }
            let shown = await driver.waitFor("notes.md")
            // Save As:, (blank), the path, (blank), the header — or the three alone.
            #expect(rows(between: shown).count == expected, "\(size): \(shown)")
        }
    }
}
