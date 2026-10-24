//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSelectionInteriorTests.swift
//
//  A bordered box keeps a drag selection begun inside it to its interior
//  (`BorderedSelectionScopeTests`). A list's own box is not such a box: its
//  presses are the list's, and its rows keep a selection to themselves
//  already, so it files no interior — a region a frame for nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("A list's own box files no selection interior")
struct ListSelectionInteriorTests {

    @Test("A bordered List files no interior, and a .border() around it does")
    func listFilesNoInterior() {
        let harness = InputChainHarness(width: 30, height: 10)
        let bare = List { Text("alpha"); Text("beta") }.listStyle(.bordered).frame(height: 5)
        harness.frame(bare)
        let scopes = harness.tui.mouseEventDispatcher.selectionScopes
        #expect(!scopes.values.contains(.interior), "the list's box filed an interior: \(scopes)")

        // The control: a box around the list is content's box, and files one.
        harness.frame(bare.border())
        #expect(harness.tui.mouseEventDispatcher.selectionScopes.values.filter { $0 == .interior }.count == 1)
    }
}
