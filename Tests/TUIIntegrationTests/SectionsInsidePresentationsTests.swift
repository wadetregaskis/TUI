//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionsInsidePresentationsTests.swift
//
//  A focus section drawn inside a sheet, an alert or a popover — a
//  `.focusSection`, a navigation stack's pushed screen, a split view's
//  columns — is the presentation's own: the keyboard reaches it, its key
//  handlers and shortcuts hear the keys the presentation holds, and the
//  presentation does not take the focus back from it. Each was a section of
//  the page's: Tab inside a sheet never reached a split view's columns, a push
//  in a sheet left the focus on the sheet's resize stop, and Escape on the
//  pushed screen closed the sheet instead of going back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// What the controls below were asked to do, reachable from the views.
@MainActor
private final class Pressed {
    var log: [String] = []
}

@MainActor
@Suite("Focus sections inside a presentation are the presentation's")
struct SectionsInsidePresentationsTests {
    /// The focus IDs Tab visits, `count` presses from where the focus starts.
    private func tabStops(_ app: TestApp, count: Int) -> [String] {
        var seen: [String] = []
        for _ in 0..<count {
            seen.append(app.focusedID ?? "nil")
            app.press(.tab)
        }
        return seen
    }

    @Test("Tab reaches the controls of every .focusSection in a sheet")
    func focusSectionsInASheet() {
        let app = TestApp(width: 60, height: 16) {
            Text(verbatim: "page")
                .sheet(isPresented: .constant(true)) {
                    HStack {
                        VStack {
                            Button("L1") {}.focusID("L1")
                            Button("L2") {}.focusID("L2")
                        }
                        .focusSection()
                        VStack {
                            Button("R1") {}.focusID("R1")
                            Button("R2") {}.focusID("R2")
                        }
                        .focusSection()
                    }
                }
        }
        let seen = Set(tabStops(app, count: 8))
        #expect(seen.isSuperset(of: ["L1", "L2", "R1", "R2"]), "\(seen)")
    }

    @Test("Tab reaches both columns of a NavigationSplitView in a sheet")
    func splitViewInASheet() {
        let app = TestApp(width: 70, height: 16) {
            Text(verbatim: "page")
                .sheet(isPresented: .constant(true)) {
                    NavigationSplitView {
                        Button("S1") {}.focusID("S1")
                    } detail: {
                        Button("D1") {}.focusID("D1")
                    }
                }
        }
        let seen = Set(tabStops(app, count: 8))
        #expect(seen.isSuperset(of: ["S1", "D1"]), "\(seen)")
    }

    /// A sheet holding a navigation stack whose pushed screen has a button.
    private struct StackSheet: View {
        let pressed: Pressed
        @State private var shown = true

        var body: some View {
            Text(verbatim: "shown=\(shown)")
                .sheet(isPresented: $shown) {
                    NavigationStack {
                        VStack {
                            Button("Other") {}.focusID("other")
                            NavigationLink("Deeper") {
                                Button("Inner") { pressed.log.append("inner") }.focusID("inner")
                                    .onKeyPress("x") {
                                        pressed.log.append("x")
                                        return .handled
                                    }
                            }
                        }
                    }
                }
        }
    }

    @Test("A screen pushed in a sheet takes the focus, and Escape goes back to the link before it closes the sheet")
    func navigationStackInASheet() {
        let pressed = Pressed()
        let app = TestApp(width: 50, height: 16) { StackSheet(pressed: pressed) }
        #expect(app.focusedID == "other")
        app.press(.tab)
        let link = app.focusedID
        #expect(link?.contains("NavigationLink") == true, "\(String(describing: link))")
        app.press(.enter)
        #expect(app.focusedID == "inner", "the pushed screen's control has the focus")
        // Its handlers hear the keys the sheet holds.
        app.press(.character("x"))
        app.press(.enter)
        #expect(pressed.log == ["x", "inner"])
        app.press(.escape)
        #expect(app.screen.contains("Deeper"), "Escape went back: \(app.screen)")
        #expect(app.screen.contains("shown=true"), "and left the sheet up: \(app.screen)")
        #expect(app.focusedID == link, "the focus is back on the link")
        app.press(.escape)
        #expect(app.screen.contains("shown=false"), "a second Escape closes the sheet: \(app.screen)")
    }

    @Test("A sheet dismissed with the focus in a section of its content gives the focus back to its opener")
    func dismissedFromANestedSection() {
        struct Page: View {
            @State private var shown = false
            var body: some View {
                VStack {
                    Button("Before") {}.focusID("before")
                    Button("Open") { shown = true }.focusID("open")
                }
                .sheet(isPresented: $shown) {
                    VStack {
                        Button("Nested") {}.focusID("nested")
                    }
                    .focusSection()
                }
            }
        }
        let app = TestApp(width: 50, height: 16) { Page() }
        app.press(.tab)
        #expect(app.focusedID == "open")
        app.press(.enter)
        var tries = 0
        while app.focusedID != "nested", tries < 4 {
            app.press(.tab)
            tries += 1
        }
        #expect(app.focusedID == "nested")
        app.press(.escape)
        #expect(!app.screen.contains("Nested"), "\(app.screen)")
        #expect(app.focusedID == "open")
    }

    @Test("A keyboard shortcut in a .focusSection of a sheet fires")
    func shortcutInASectionOfASheet() {
        let pressed = Pressed()
        let app = TestApp(width: 50, height: 16) {
            Text(verbatim: "page")
                .sheet(isPresented: .constant(true)) {
                    VStack {
                        Button("Go") { pressed.log.append("go") }
                            .keyboardShortcut("g", modifiers: .control)
                    }
                    .focusSection()
                }
        }
        _ = app.screen
        app.press(.character("g"), modifiers: .control)
        #expect(pressed.log == ["go"])
    }
}
