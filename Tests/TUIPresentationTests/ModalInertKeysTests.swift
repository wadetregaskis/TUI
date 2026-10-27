//  🖥️ TUI — A Terminal UI framework for Swift
//  ModalInertKeysTests.swift
//
//  Behind a modal, only the modal's own keys work (decisions A-MODALS-1, the
//  owner's option 3, 2026-10-27): a status bar item and a keyboard shortcut
//  declared OUTSIDE the view that presents a sheet used to show and fire behind
//  it. Measured on macOS 15.8.1: behind a sheet a window's key equivalents and
//  its menu commands do nothing; behind an app-modal alert nothing does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("Keys declared outside a modal are inert behind it")
struct ModalInertKeysTests {
    /// What fired.
    final class Log {
        var fired: [String] = []
    }

    /// A page whose status bar item and shortcut are declared OUTSIDE the view
    /// that presents the sheet, and a sheet with a shortcut of its own.
    private func page(_ log: Log, presented: Bool) -> some View {
        VStack {
            Button("Outside") { log.fired.append("outside") }
                .keyboardShortcut("k", modifiers: .control)
            Text("presenter")
                .sheet(isPresented: .constant(presented)) {
                    Button("Inside") { log.fired.append("inside") }
                        .keyboardShortcut("j", modifiers: .control)
                }
        }
        .statusBarItems {
            StatusBarItem(shortcut: "n", label: "new") { log.fired.append("new") }
        }
    }

    @Test("Without a modal, the page's item and shortcut work")
    func pageKeysWorkWithoutAModal() {
        let harness = InputChainHarness(width: 60, height: 20)
        let log = Log()
        harness.frame(page(log, presented: false))
        harness.frame(page(log, presented: false))
        harness.press(KeyEvent(key: .character("k"), ctrl: true))
        harness.press(KeyEvent(key: .character("n")))
        #expect(log.fired == ["outside", "new"])
        #expect(harness.statusBar.currentItems.contains { $0.shortcut == "n" })
    }

    @Test("Behind a sheet, the page's item and shortcut neither show nor fire; the sheet's own does")
    func pageKeysAreInertBehindASheet() {
        let harness = InputChainHarness(width: 60, height: 20)
        let log = Log()
        harness.frame(page(log, presented: true))
        harness.frame(page(log, presented: true))
        #expect(
            !harness.statusBar.currentItems.contains { $0.shortcut == "n" },
            "the page's item shows over the sheet: \(harness.statusBar.currentItems.map(\.shortcut))")
        harness.press(KeyEvent(key: .character("k"), ctrl: true))
        harness.press(KeyEvent(key: .character("n")))
        #expect(log.fired.isEmpty, "a key of the page's fired behind the sheet: \(log.fired)")
        harness.press(KeyEvent(key: .character("j"), ctrl: true))
        #expect(log.fired == ["inside"])
    }
}
