//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentToolbarItemsTests.swift
//
//  `.contentToolbar(for: .tabViewSidebar)` with toolbar content, as SwiftUI's
//  documentation writes it: the items at the foot of the sidebar, the top
//  bar's placements in a row and the bottom bar's under it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Content toolbar items")
struct ContentToolbarItemsTests {

    @Test("Toolbar items in a tab view sidebar's content toolbar are at its foot, the bottom bar's under the rest")
    func itemsAtTheFoot() {
        let tabs = TabView(selection: .constant(0)) {
            Tab("Only", value: 0) { Text("BODY") }
        }
        .tabViewSidebarFooter { Text("FOOTER") }
        .contentToolbar(for: .tabViewSidebar) {
            ToolbarItem(placement: .bottomBar) { Text("ACCOUNT") }
            ToolbarItem(placement: .automatic) { Text("DISCONNECT") }
            ToolbarItem(placement: .primaryAction) { Text("ADD") }
            ToolbarItem { Text("GONE") }
                .hidden()
        }
        let sidebar = renderToBuffer(
            tabs.tabViewStyle(.sidebarAdaptable), context: makeRenderContext(width: 60, height: 12)
        ).lines.map(\.stripped)
        let footer = sidebar.firstIndex { $0.contains("FOOTER") }
        let row = sidebar.firstIndex { $0.contains("DISCONNECT ADD") }
        let account = sidebar.firstIndex { $0.contains("ACCOUNT") }
        #expect(footer != nil && row != nil && account != nil, "\(sidebar)")
        if let footer, let row, let account {
            #expect(footer < row && row + 1 == account, "\(sidebar)")
        }
        #expect(!sidebar.contains { $0.contains("GONE") }, "\(sidebar)")
    }
}
