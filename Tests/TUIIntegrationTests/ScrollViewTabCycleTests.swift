//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollViewTabCycleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
private final class Count {
    var presses = 0
}

/// Tab walks a page's focus stops and comes back round, in a window with bars
/// as without. The bars are focus sections of their own, so the page is one
/// section of several; Tab past its last stop asked the next section to take
/// the focus, and where none had anything focusable the focus stayed put — on
/// the Example's Empty State page, whose one button sits in a page that
/// scrolls (two stops: the button and the page), no number of Tabs came back
/// to the button.
@MainActor
@Suite("Tab comes back round a page that scrolls")
struct ScrollViewTabCycleTests {
    /// The button, among lines enough to make the page scroll, under `wrap`;
    /// the button holds the focus first.
    private func page(_ count: Count, _ wrap: @escaping (AnyView) -> AnyView) -> TestApp {
        TestApp(width: 60, height: 12) {
            wrap(
                AnyView(
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(0..<6, id: \.self) { Text("Line \($0)") }
                            Button("Refresh") { count.presses += 1 }
                            ForEach(6..<14, id: \.self) { Text("Line \($0)") }
                        }
                    }))
        }
    }

    private func withBar(_ view: AnyView) -> AnyView {
        AnyView(view.toolbar { ToolbarItem(placement: .bottomBar) { Text("status") } })
    }

    @Test("Two Tabs from the button come back to it, with no bars (the control)")
    func noBars() {
        let count = Count()
        let app = page(count) { $0 }
        app.press(.enter)
        app.press(.tab, times: 2)
        app.press(.enter)
        #expect(count.presses == 2, "back on the button: \(app.screen)")
    }

    @Test("Two Tabs from the button come back to it, under a bar with nothing to focus")
    func underABar() {
        let count = Count()
        let app = page(count, withBar)
        app.press(.enter)
        #expect(count.presses == 1, "the button holds the focus first: \(app.screen)")
        app.press(.tab, times: 2)
        app.press(.enter)
        #expect(count.presses == 2, "back on the button: \(app.screen)")
    }

    @Test("Shift-Tab from the button goes round to the page, under a bar with nothing to focus")
    func backwardUnderABar() {
        let count = Count()
        let app = page(count, withBar)
        app.press(.tab, modifiers: .shift)
        app.press(.enter)
        #expect(count.presses == 0, "on the page, the stop before the button going round: \(app.screen)")
        app.press(.tab, modifiers: .shift)
        app.press(.enter)
        #expect(count.presses == 1, "and on round to the button: \(app.screen)")
    }
}
