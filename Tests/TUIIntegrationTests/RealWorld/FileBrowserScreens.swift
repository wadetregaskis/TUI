//  🖥️ TUI — A Terminal UI framework for Swift
//  FileBrowserScreens.swift
//
//  Real-world screens: file browsers. A folder tree in a hierarchical List
//  beside a path bar, and a sortable Table of two hundred files under a
//  toolbar. Expanding a folder must push the rows below it down without gaps,
//  sorting must keep the table whole, and the last file must be reachable.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

private let tree = [
    Node(id: "Documents", children: (1...6).map { Node(id: "report-\($0).txt") }),
    Node(id: "Pictures", children: [Node(id: "Holidays", children: (1...3).map { Node(id: "beach-\($0).jpg") })]),
    Node(id: "README.md"),
]

/// A path bar over a folder tree.
private struct TreePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("~/home/someone")
            List(tree, children: \.children) { node in Text(node.id) }.focusID("tree")
            Text("3 items")
        }
    }
}

private struct FileInfo: Identifiable, Sendable {
    let id: Int
    var name: String { "file-\(id).dat" }
    var bytes: Int { id * 1_031 % 9_973 }
}

/// A toolbar over a sortable table of 200 files, a count under it.
private struct FileTablePage: View {
    @State private var files = (1...200).map(FileInfo.init)
    @State private var sortOrder = [KeyPathComparator(\FileInfo.id)]
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("New Folder") {}.focusID("new-folder")
                Button("Delete") {}.focusID("delete").disabled(selection == nil)
            }
            Table(files, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \FileInfo.id) { Text($0.name) }
                TableColumn("Size", value: \FileInfo.bytes) { Text("\($0.bytes) B") }
            }
            .focusID("files")
            Text("\(files.count) files")
        }
        .onChange(of: sortOrder) { files.sort(using: sortOrder) }
    }
}

@MainActor
@Suite("Real world: file browsers")
struct FileBrowserScreens {
    @Test("A folder tree: expanding a folder puts its children right under it, the count line stays",
          arguments: TerminalSize.all)
    func folderTree(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TreePage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<3 where app.focusedID != "tree" { app.press(.tab) }
        #expect(app.focusedID == "tree")
        app.press(.right)
        LayoutSanity.check(app, "Documents expanded")
        LayoutSanity.expectContiguous(
            app, ["Documents"] + (1...6).map { "report-\($0).txt" } + ["Pictures"], "the expanded folder")
        if size.height >= 12 {
            #expect(app.screen.contains("3 items"), "the count line is pushed off:\n\(app.screen)")
        }
        LayoutSanity.reach("README.md", in: app, by: .down, limit: 12)
    }

    @Test("A sortable table of 200 files: End reaches the last, sorting by size keeps the table whole",
          arguments: TerminalSize.all)
    func fileTable(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { FileTablePage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<4 where app.focusedID != "files" { app.press(.tab) }
        #expect(app.focusedID == "files")
        app.press(.end)
        LayoutSanity.check(app, "End")
        // At 20×6 the table has room for one cut row.
        if size.height >= 12 { #expect(LayoutSanity.shows("file-200.dat", in: app), "End fell short:\n\(app.screen)") }
        app.press(.character("s"), modifiers: .control)
        LayoutSanity.check(app, "sorted by size")
        app.press(.home)
        LayoutSanity.check(app, "Home")
        if size.height >= 12 {
            #expect(app.screen.contains("200 files"), "the count line is pushed off:\n\(app.screen)")
        }
        LayoutSanity.expectNotSilentlyCut(app, "file-", "a file name")
    }
}
