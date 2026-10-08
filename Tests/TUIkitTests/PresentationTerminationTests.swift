//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationTerminationTests.swift
//
//  `presentationPreventsAppTermination(_:)` and
//  `dialogPreventsAppTermination(_:)` through the real input chain: the quit
//  key does nothing, and the bar stops offering it, while such a presentation
//  is up — and works again once it is gone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Presentations that prevent quitting")
struct PresentationTerminationTests {
    private let quitKey = KeyEvent(character: "q")

    /// Whether the presentation is up, by reference so a frame's binding
    /// reaches it.
    private final class Shown {
        var value = true
        var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private func sheet(_ shown: Shown, prevents: Bool?, inner: Bool? = nil) -> some View {
        Text("page").sheet(isPresented: shown.binding) {
            Text("editing")
                .presentationPreventsAppTermination(inner)
                .presentationPreventsAppTermination(prevents)
        }
    }

    private func offersQuit(_ harness: InputChainHarness) -> Bool {
        harness.statusBar.currentSystemItems.contains { $0.order == .quit }
    }

    @Test("A sheet that prevents termination stops the quit key until it is dismissed")
    func sheetPrevents() {
        let harness = InputChainHarness()
        let shown = Shown()
        harness.frame(sheet(shown, prevents: true))
        harness.press(quitKey)
        #expect(harness.quits == 0)
        #expect(!offersQuit(harness), "the bar does not offer a key that does nothing")

        shown.value = false
        harness.frame(sheet(shown, prevents: true))
        #expect(offersQuit(harness))
        harness.press(quitKey)
        #expect(harness.quits == 1, "dismissing the sheet lifted it")
    }

    @Test("The automatic behaviour, nil, leaves the quit key working behind a sheet")
    func automaticDoesNotPrevent() {
        let harness = InputChainHarness()
        harness.frame(sheet(Shown(), prevents: nil))
        harness.press(quitKey)
        #expect(harness.quits == 1)
    }

    @Test("Of two statements, true takes precedence over false, and non-nil over nil")
    func precedence() {
        let harness = InputChainHarness()
        harness.frame(sheet(Shown(), prevents: false, inner: true))
        harness.press(quitKey)
        #expect(harness.quits == 0, "true inside false still prevents")

        let other = InputChainHarness()
        other.frame(sheet(Shown(), prevents: nil, inner: false))
        other.press(quitKey)
        #expect(other.quits == 1)
    }

    @Test("A dialog that prevents termination stops the quit key while it is up")
    func dialogPrevents() {
        let harness = InputChainHarness()
        let shown = Shown()
        let page = {
            Text("page")
                .alert("Discard?", isPresented: shown.binding) {
                    Button("Discard", role: .destructive) {}
                }
                .dialogPreventsAppTermination(true)
        }
        harness.frame(page())
        harness.press(quitKey)
        #expect(harness.quits == 0)
        shown.value = false
        harness.frame(page())
        harness.press(quitKey)
        #expect(harness.quits == 1, "dismissed, the dialog prevents nothing")
    }

    /// Whether the quit key quits behind an alert with `actions`, under
    /// `severity` and `statement`.
    private func quitsBehind(
        severity: DialogSeverity = .automatic, statement: Bool? = nil,
        @ViewBuilder actions: @escaping () -> some View
    ) -> Bool {
        let harness = InputChainHarness()
        harness.frame(
            Text("page")
                .alert("Question", isPresented: .constant(true), actions: actions)
                .dialogSeverity(severity)
                .dialogPreventsAppTermination(statement))
        harness.press(quitKey)
        return harness.quits == 1
    }

    /// macOS's automatic rule (decisions B36): a dialog prevents quitting
    /// unless it has one non-destructive button and is not critical.
    @Test("Automatically, a one-button notice leaves the quit key working and a question holds it")
    func dialogsAutomaticRule() {
        #expect(quitsBehind { Button("OK") {} }, "a single plain button prevented quitting")
        #expect(quitsBehind { EmptyView() }, "no actions is SwiftUI's one OK button")
        #expect(quitsBehind { Button("Got it", role: .cancel) {} })
        #expect(!quitsBehind { Button("Delete", role: .destructive) {} }, "a lone destructive button")
        #expect(!quitsBehind {
            Button("Save") {}
            Button("Cancel", role: .cancel) {}
        }, "two buttons")
        #expect(!quitsBehind(severity: .critical) { Button("OK") {} }, "a critical dialog")
        // A statement wins over the rule either way.
        #expect(quitsBehind(statement: false) { Button("Delete", role: .destructive) {} })
        #expect(!quitsBehind(statement: true) { Button("OK") {} })
    }

    @Test("A dialog presenting an error is critical, so automatically holds the quit key")
    func errorDialogIsCritical() {
        struct Failure: LocalizedError { var errorDescription: String? { "It failed" } }
        let harness = InputChainHarness()
        harness.frame(
            Text("page").alert(isPresented: .constant(true), error: Failure?.some(Failure())) { _ in
                Button("OK") {}
            } message: { _ in
                Text("Try again")
            })
        harness.press(quitKey)
        #expect(harness.quits == 0)
    }

    @Test("A sheet keeps the automatic \"never\": it has no toolbar to read")
    func sheetsStayNever() {
        let harness = InputChainHarness()
        harness.frame(Text("page").sheet(isPresented: .constant(true)) {
            Text("form").presentationPreventsAppTermination(nil)
        })
        harness.press(quitKey)
        #expect(harness.quits == 1)
    }
}
