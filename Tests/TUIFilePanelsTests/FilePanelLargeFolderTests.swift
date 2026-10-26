//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelLargeFolderTests.swift
//
//  The open panel over a folder of thousands of items: what selecting them
//  all costs, against what a frame of the same folder costs.
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
@Suite("File panel, large folder", .serialized)
struct FilePanelLargeFolderTests {
    /// How many files of each kind the folder holds: a plain-text file that
    /// can be chosen and a `.bin` one that cannot, `file0.txt`, `file0.bin`, ….
    private static let pairs = 1500

    /// A folder of ``pairs`` text and binary files, beside the fixture's tree.
    private func largeFolder(in fixture: FilePanelFixture) throws -> URL {
        let folder = fixture.url("Large")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<Self.pairs {
            for ext in ["txt", "bin"] {
                _ = FileManager.default.createFile(
                    atPath: folder.appendingPathComponent("file\(index).\(ext)").path, contents: nil)
            }
        }
        return folder
    }

    /// A ratio, not a budget: a guard against a cost per item selected that
    /// grows with the folder, which an absolute time would only test the
    /// machine for. Selecting all 3,000 items once listed the dimmed rows
    /// afresh for each of them — seconds, where a frame is milliseconds.
    @Test("Selecting every item costs about a frame, whatever the folder holds")
    func selectAllCostsAboutAFrame() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let folder = try largeFolder(in: fixture)
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            FilePanelPresenter(
                content: Text("Page"), isPresented: caller.binding,
                request: {
                    FilePanelRequest(
                        purpose: .open(allowsMultipleSelection: true),
                        rule: FileChoiceRule(allowedContentTypes: [.plainText]), title: "Open",
                        confirmationLabel: "Open", startDirectory: folder, homeDirectory: fixture.root)
                },
                onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
        }
        await driver.waitFor("file0.txt")
        let clock = ContinuousClock()
        // A frame of the folder: the cursor moved one row, the quickest of
        // five, after one to warm up. Rows: file0.bin, file0.txt, file1.bin, ….
        driver.press(.down)
        var frame = Duration.seconds(3600)
        for _ in 0..<5 {
            frame = min(frame, clock.measure { driver.press(.down) })
        }
        // Ctrl+A, the table's select-all: every row is offered to the
        // selection, and the dimmed ones are refused. The quickest of three;
        // measured at a few frames' worth, and at a thousand before the rows
        // were looked up.
        var selectAll = Duration.seconds(3600)
        for _ in 0..<3 {
            selectAll = min(selectAll, clock.measure { driver.press([KeyEvent(key: .character("a"), ctrl: true)]) })
        }
        #expect(selectAll < frame * 50, "select-all took \(selectAll), a frame \(frame)")
        // The cursor is on file3.bin, a dimmed row; on file3.txt, it is in the
        // selection, and Return chooses the selection: the text files alone.
        driver.press(.down)
        driver.press(.enter)
        #expect(caller.chosen.count == Self.pairs)
        #expect(caller.chosen.allSatisfy { $0.pathExtension == "txt" })
    }
}
