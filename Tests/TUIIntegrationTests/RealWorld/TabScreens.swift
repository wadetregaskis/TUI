//  🖥️ TUI — A Terminal UI framework for Swift
//  TabScreens.swift
//
//  Real-world screens: tab views whose tabs are nothing alike — a form, a
//  long list, a page of text, an empty tab — as a preferences window or an
//  inspector has them. Switching must draw each tab whole, keep each tab's
//  state, and leave the focus on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

/// Four tabs: a form, a list of 40, a paragraph, and nothing.
private struct InspectorPage: View {
    @State private var tab = 0
    @State private var title = "Untitled"
    @State private var locked = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", value: 0) {
                Form {
                    TextField("Title", text: $title).focusID("title")
                    Toggle("Locked", isOn: $locked).focusID("locked")
                }
            }
            Tab("History", value: 1) {
                List(1...40, id: \.self) { Text("Revision \($0)") }.focusID("history")
            }
            Tab("Notes", value: 2) {
                ScrollView {
                    Text(String(repeating: "A paragraph of notes about the document. ", count: 12))
                }
            }
            Tab("Empty", value: 3) {
                Text("Nothing here")
            }
        }
    }
}

/// Two tabs, the second a tall scroll view of buttons.
private struct TallTabPage: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Summary", value: 0) { Text("All good") }
            Tab("Details", value: 1) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(1...25, id: \.self) { Button("Detail \($0)") {}.focusID("detail-\($0)") }
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("Real world: tab views with heterogeneous tabs")
struct TabScreens {
    @Test("Every tab drawn whole in turn, and the form's text kept across switches", arguments: TerminalSize.all)
    func heterogeneousTabs(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { InspectorPage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<4 where app.focusedID != "title" { app.press(.tab) }
        #expect(app.focusedID == "title")
        app.type(" draft")
        LayoutSanity.focus("General", in: app)
        for (index, marker) in ["Revision 1", "A paragraph", "Nothing here"].enumerated() {
            app.press(.right)
            LayoutSanity.check(app, "tab \(index + 1)")
            if size.height >= 12 {
                #expect(app.screen.contains(marker), "tab \(index + 1) shows no \(marker):\n\(app.screen)")
            }
        }
        app.press(.left, times: 3)
        LayoutSanity.check(app, "back to General")
        if size.width >= 40 {
            #expect(app.screen.contains("Untitled draft"), "the title was lost:\n\(app.screen)")
        }
    }

    @Test("A tall tab: Tab reaches its last button, the strip stays on screen", arguments: TerminalSize.all)
    func tallTab(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TallTabPage() }
        LayoutSanity.focus("Summary", in: app)
        app.press(.right)
        LayoutSanity.check(app, "Details")
        for step in 0..<30 where app.focusedID != "detail-25" {
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1)")
        }
        #expect(app.focusedID == "detail-25", "the last button is not focused: \(app.focusedID ?? "none")")
        if size.height >= 12 {
            #expect(app.screen.contains("Summary"), "the strip scrolled away:\n\(app.screen)")
        }
    }
}
