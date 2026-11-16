//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewCollapseFocusTests.swift
//
//  A split view narrowed into its stack takes its dividers away. The one that
//  held the focus hands it on, and widening the split again must not leave
//  the focus on nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUINavigation
import TUITesting

@MainActor
@Suite("A focused divider across a split view's collapse")
struct NavigationSplitViewCollapseFocusTests {
    /// Three columns, a button in each, so each column is a focus stop.
    private struct ThreeButtons: View {
        var body: some View {
            NavigationSplitView {
                Button("SIDE") {}.focusID("side")
            } content: {
                Button("CONT") {}.focusID("cont")
            } detail: {
                Button("DETL") {}.focusID("detl")
            }
        }
    }

    /// Three columns of text: the dividers are the only focus stops.
    private struct ThreeTexts: View {
        var body: some View {
            NavigationSplitView {
                Text("SIDE")
            } content: {
                Text("CONT")
            } detail: {
                Text("DETL")
            }
        }
    }

    /// Tabs to the divider after `column`, or returns `nil` if none takes the focus.
    private func focusDivider(after column: String, _ app: TestApp) -> String? {
        for _ in 0..<8 {
            if let focused = app.focusedID, focused.hasPrefix("nav-split-divider-\(column)-") { return focused }
            app.press(.tab)
        }
        return nil
    }

    @Test(
        "Collapsed, the focus moves from a divider to the column on top, and stays there widened",
        arguments: ["sidebar", "content"])
    func dividerFocusToTheColumnOnTop(column: String) throws {
        let app = TestApp(width: 80, height: 6) { ThreeButtons() }
        let divider = try #require(focusDivider(after: column, app), "no divider took the focus: \(app.screen)")
        app.resize(width: 20, height: 6)
        #expect(!app.screen.contains("CONT"), "collapsed: \(app.screen)")
        // Where focus goes from a control that leaves the tree, and from a
        // section that does: the first section left, here the column on top.
        #expect(app.focusedID == "side", "collapsed: \(app.focusedID ?? "nothing") has the focus, not SIDE")
        app.resize(width: 80, height: 6)
        #expect(app.screen.contains("CONT"), "expanded: \(app.screen)")
        #expect(app.focusedID == "side", "expanded: \(app.focusedID ?? "nothing") has the focus, not SIDE")
        #expect(app.focusedID != divider)
    }

    /// Collapsed, columns of text have nothing to focus, so nothing is
    /// focused. Widened, the dividers are back, and one of them takes it:
    /// before, the keyboard stayed with the sidebar's empty section, and Tab
    /// was the only way back to anything.
    @Test("Columns of text: collapsed, nothing to focus; widened, a divider has the focus again")
    func textColumnsGetTheFocusBack() throws {
        let app = TestApp(width: 80, height: 6) { ThreeTexts() }
        _ = try #require(focusDivider(after: "content", app), "no divider took the focus: \(app.screen)")
        app.resize(width: 20, height: 6)
        #expect(app.focusedID == nil, "collapsed, there is nothing to focus")
        app.resize(width: 80, height: 6)
        let focused = try #require(app.focusedID, "expanded, the focus is on nothing")
        #expect(focused.hasPrefix("nav-split-divider-"), "\(focused)")
    }
}
