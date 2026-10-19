//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelColumnsTests.swift
//
//  The columns of a file panel's table at the widths a terminal has: the
//  name keeps its room, and the columns beside it give way from the right.
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

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel columns", .serialized)
struct FilePanelColumnsTests {
    /// The fixture's names, as the Name column draws them.
    private let names = ["Alpha/", "linked/", "beta.txt", "gamma.pdf", "notes.md"]

    /// An open panel over `fixture`'s root, in a terminal `width` × `height`,
    /// once the folder is read and notes.md, its last row, drawn whole —
    /// which, where the name had no room, it never was.
    private func screen(_ fixture: FilePanelFixture, width: Int, height: Int) async -> String {
        let caller = FilePanelCaller()
        let driver = FilePanelDriver(width: width, height: height) {
            FilePanelPresenter(
                content: Text("Page"), isPresented: caller.binding,
                request: {
                    FilePanelRequest(
                        purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(allowedContentTypes: []),
                        title: "Open", confirmationLabel: "Open", startDirectory: fixture.root,
                        homeDirectory: fixture.root)
                },
                onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
        }
        return await driver.waitFor("notes.md", timeout: .seconds(10))
    }

    @Test("The columns beside the name give way from the right, each where the name would have under 20 cells")
    func shownByWidth() {
        // Inset 4, then 20 for the name, then each column and its spacing.
        #expect(FilePanelColumns.shown(inWidth: 120) == 3)
        #expect(FilePanelColumns.shown(inWidth: 73) == 3)
        #expect(FilePanelColumns.shown(inWidth: 72) == 2)
        #expect(FilePanelColumns.shown(inWidth: 57) == 2)
        #expect(FilePanelColumns.shown(inWidth: 56) == 1)
        #expect(FilePanelColumns.shown(inWidth: 35) == 1)
        #expect(FilePanelColumns.shown(inWidth: 34) == 0)
        #expect(FilePanelColumns.shown(inWidth: 0) == 0)
    }

    @Test("A wide panel shows all four columns")
    func wide() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let shown = await screen(fixture, width: 100, height: 30)
        for header in ["Name", "Size", "Date Modified", "Kind"] {
            #expect(shown.contains(header), "\(header): \(shown)")
        }
    }

    @Test("At 64 columns Kind gives way, and every name is whole")
    func sixtyFour() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let shown = await screen(fixture, width: 64, height: 20)
        for name in names {
            #expect(shown.contains(name), "\(name): \(shown)")
        }
        #expect(shown.contains("Date Modified"))
        #expect(!shown.contains("Kind"), "\(shown)")
    }

    @Test("At 50 columns Date Modified gives way too, and every name is whole")
    func fifty() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let shown = await screen(fixture, width: 50, height: 16)
        for name in names {
            #expect(shown.contains(name), "\(name): \(shown)")
        }
        #expect(shown.contains("Size"))
        #expect(!shown.contains("Date Modified"), "\(shown)")
    }
}
