//  🖥️ TUI — A Terminal UI framework for Swift
//  TooltipKeepsDialogsStillTests.swift
//
//  A tooltip in the status bar takes rows from the page as it shows, and a
//  page laid out in the middle of the window, or a dialog centred over it,
//  stays where it is unless those rows would cover it (the owner, 2026-11-10:
//  tips "should only move windows / dialogs / etc if _necessary_").
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
@Suite("A status-bar tooltip, the page and the dialogs over it")
struct TooltipKeepsDialogsStillTests {
    /// A page presenting a sheet of `rows` lines, the first `SHEET TOP`, and a
    /// button whose help the `?` key shows in the status bar.
    private struct SheetPage: View {
        let rows: Int

        var body: some View {
            Text("PAGE")
                .sheet(isPresented: .constant(true)) {
                    VStack {
                        Text("SHEET TOP")
                        ForEach(0..<rows, id: \.self) { row in Text("line \(row)") }
                        Button("Go") {}.help("HELP FOR GO")
                    }
                }
        }
    }

    /// A page of `rows` lines, the first `PAGE TOP`, laid out in the middle
    /// of the window as a `WindowGroup` lays out a page that doesn't fill it
    /// (a `TestApp` of a view puts it at the top), and a button whose help
    /// the `?` key shows.
    private struct CentredPageApp: App {
        var rows = 3

        init() {}

        init(rows: Int) {
            self.rows = rows
        }

        var body: some Scene {
            WindowGroup {
                VStack {
                    Text("PAGE TOP")
                    ForEach(0..<rows, id: \.self) { row in Text("line \(row)") }
                    Button("Go") {}.help("HELP FOR GO")
                }
            }
        }
    }

    private func row(of text: String, in app: TestApp) -> Int? {
        app.screen.lines.firstIndex { $0.contains(text) }
    }

    /// At two heights, one row apart, so that one of them centred the dialog
    /// in the rows the tooltip leaves a row higher: an odd number of spare
    /// rows split differently from an even one.
    @Test("A dialog with room to spare stays put as the tooltip shows", arguments: [20, 21])
    func staysPut(height: Int) {
        let app = TestApp(width: 60, height: height) { SheetPage(rows: 3) }
        let before = row(of: "SHEET TOP", in: app)
        #expect(before != nil, "\(app.screen)")
        app.press(.character("?"))
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("HELP FOR GO"), "precondition: the tooltip shows: \(app.screen)")
        #expect(row(of: "SHEET TOP", in: app) == before, "\(app.screen)")
    }

    @Test("A dialog the tooltip's rows would cover moves up just clear of them")
    func movesWhenItMust() throws {
        let app = TestApp(width: 60, height: 20) { SheetPage(rows: 14) }
        app.press(.character("?"))
        app.advance(by: .seconds(1))
        let help = try #require(row(of: "HELP FOR GO", in: app), "\(app.screen)")
        let go = try #require(row(of: "Go", in: app), "\(app.screen)")
        #expect(go < help, "the dialog stays clear of the tooltip: \(app.screen)")
    }

    @Test("A page with room to spare stays put as the tooltip shows", arguments: [20, 21])
    func pageStaysPut(height: Int) {
        let app = TestApp(CentredPageApp(rows: 3), width: 60, height: height)
        let before = row(of: "PAGE TOP", in: app)
        #expect(before != nil, "\(app.screen)")
        app.press(.character("?"))
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("HELP FOR GO"), "precondition: the tooltip shows: \(app.screen)")
        #expect(row(of: "PAGE TOP", in: app) == before, "\(app.screen)")
    }

    @Test("A page the tooltip's rows would cover moves up just clear of them")
    func pageMovesWhenItMust() throws {
        let app = TestApp(CentredPageApp(rows: 15), width: 60, height: 20)
        app.press(.character("?"))
        app.advance(by: .seconds(1))
        let help = try #require(row(of: "HELP FOR GO", in: app), "\(app.screen)")
        let go = try #require(row(of: "Go", in: app), "\(app.screen)")
        #expect(go < help, "the page stays clear of the tooltip: \(app.screen)")
        #expect(app.screen.contains("PAGE TOP"), "\(app.screen)")
    }
}
