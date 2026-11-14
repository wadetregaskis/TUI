//  🖥️ TUI — A Terminal UI framework for Swift
//  WideTextScreens.swift
//
//  Real-world screens: long and wide text in narrow panes. CJK in a detail
//  pane beside a sidebar, emoji and combining marks in list rows, and long
//  one-line titles in a toolbar row. Nothing may run past the screen's edge
//  or a pane's, and what is cut must show that it was.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private let japanese = "東京都の天気予報：明日は晴れのち曇り、最高気温は二十三度です。"
private let combining = "Cafe\u{301} Zu\u{308}rich nai\u{308}ve"
private let emoji = "Team 👩‍👩‍👧‍👦 party 🎉🎂 at 8"

/// A fixed sidebar of buttons and a detail pane of CJK text.
private struct CJKDetailPage: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Button("Tokyo") {}.focusID("tokyo")
                Button("Osaka") {}.focusID("osaka")
            }
            .frame(width: 9)
            Divider()
            VStack(alignment: .leading) {
                Text("天気").bold()
                Text(japanese)
                Button("詳しく見る") {}.focusID("more")
            }
        }
    }
}

/// A list of rows with emoji, combining marks and CJK.
private struct MixedRowsPage: View {
    let rows = [emoji, combining, japanese, "plain ascii row"]

    var body: some View {
        VStack(alignment: .leading) {
            List(rows, id: \.self) { Text($0).lineLimit(1) }.focusID("rows")
            Button("Done") {}.focusID("done")
        }
    }
}

/// A toolbar row of a long title cut to one line, and two buttons.
private struct LongTitlePage: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Quarterly revenue report for the northern hemisphere, all divisions, final")
                    .lineLimit(1)
                Button("Share") {}.focusID("share")
                Button("Print") {}.focusID("print")
            }
            Text("Body")
        }
    }
}

@MainActor
@Suite("Real world: long and wide text in narrow panes")
struct WideTextScreens {
    @Test("CJK in a detail pane: wrapped within the pane, the button after it reachable", arguments: TerminalSize.all)
    func cjkDetail(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { CJKDetailPage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectNotSilentlyCut(app, japanese, "the forecast")
        for step in 0..<4 where app.focusedID != "more" {
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1)")
        }
        #expect(app.focusedID == "more", "Tab never reached the button after the text")
    }

    @Test("Emoji, combining marks and CJK in one-line rows: each cut with a sign, none past the edge",
          arguments: TerminalSize.all)
    func mixedRows(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { MixedRowsPage() }
        LayoutSanity.check(app, "launch")
        for row in [emoji, combining, japanese] { LayoutSanity.expectNotSilentlyCut(app, row, row) }
        app.press(.tab)
        app.press(.down, times: 3)
        LayoutSanity.check(app, "the last row chosen")
        LayoutSanity.reach("Done", in: app, by: .tab, limit: 3)
    }

    @Test("A long one-line title beside buttons: the buttons stay whole, the title shows it was cut",
          arguments: TerminalSize.all)
    func longTitle(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { LongTitlePage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectNotSilentlyCut(
            app, "Quarterly revenue report for the northern hemisphere, all divisions, final", "the title")
        if size.width >= 40 {
            #expect(app.screen.contains("Share"), "Share was squeezed out:\n\(app.screen)")
            #expect(app.screen.contains("Print"), "Print was squeezed out:\n\(app.screen)")
        }
    }
}
