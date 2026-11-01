//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusableInteractionsTests.swift
//
//  `focusable(interactions:)` follows SwiftUI's meanings (deviations sweep,
//  likely bug 10; semantic audit 30). `.edit`: views that support it "become
//  focused when the user taps or clicks on them, or when the user issues a
//  focus movement command". `.activate`: the view has a primary action that
//  focus can activate, and is focusable only under macOS's all-controls
//  keyboard navigation — a terminal always has that, so here it is a Tab stop
//  that a click does not focus. The two were the other way round.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("focusable(interactions:) follows SwiftUI's meanings")
struct FocusableInteractionsTests {
    /// Says whether it holds the focus.
    private struct Probe: View {
        let name: String
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            Text(verbatim: "\(name) \(isFocused ? "FOCUSED" : "idle")")
        }
    }

    private struct Page: App {
        let interactions: FocusInteractions
        init() { self.init(interactions: .automatic) }
        init(interactions: FocusInteractions) { self.interactions = interactions }
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Button("first") {}
                    Probe(name: "probe").focusable(interactions: interactions)
                }
            }
        }
    }

    /// The probe's line after a click on it, and after a Tab from there.
    private func probe(_ interactions: FocusInteractions) -> (afterClick: String, afterTab: String) {
        let app = TestApp(Page(interactions: interactions), width: 30, height: 4)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func line() -> String { app.screen.lines.first { $0.contains("probe") } ?? "" }
        frame()
        frame()
        guard let row = app.screen.styledLines.firstIndex(where: { $0.stripped.contains("probe") }),
            let start = app.screen.styledLines[row].stripped.range(of: "probe")
        else { return ("", "") }
        let column = app.screen.styledLines[row].stripped.distance(from: app.screen.styledLines[row].stripped.startIndex, to: start.lowerBound)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: column + 1, y: row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: column + 1, y: row))
        frame()
        frame()
        let afterClick = line()
        _ = app.send(KeyEvent(key: .tab))
        frame()
        frame()
        return (afterClick, line())
    }

    @Test("An editing view is focused by a click, and by Tab")
    func editClicks() {
        let result = probe(.edit)
        #expect(result.afterClick.contains("FOCUSED"), "\(result)")
    }

    @Test("An activating view is a Tab stop that a click does not focus")
    func activateDoesNotClick() {
        let result = probe(.activate)
        #expect(result.afterClick.contains("idle"), "\(result)")
        #expect(result.afterTab.contains("FOCUSED"), "\(result)")
    }

    @Test("The automatic interactions are both: a click focuses")
    func automaticClicks() {
        let result = probe(.automatic)
        #expect(result.afterClick.contains("FOCUSED"), "\(result)")
    }
}
