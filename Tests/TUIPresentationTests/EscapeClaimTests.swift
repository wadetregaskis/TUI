//  🖥️ TUI — A Terminal UI framework for Swift
//  EscapeClaimTests.swift
//
//  A surface's claim on Escape is its own by the claim's token, not by its
//  label: a popover renames only the claim it made, and a sheet or alert that
//  takes the keyboard withdraws a claim made outside it.
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
@Suite("Claims on Escape", .rendersEnglishUI)
struct EscapeClaimTests {
    /// Whether a sheet is up, by reference so the bindings a frame built
    /// reach it.
    private final class Model {
        var presented = true
        var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    }

    /// The A28 review's failing input: a popover whose content draws a cancel
    /// button and presents a popover of its own. Both claim Escape as "close
    /// popover"; the outer one, renaming "its" claim to "cancel" once its
    /// content had drawn, renamed the inner one's — while Escape closed the
    /// inner note.
    @Test("A popover inside a popover keeps its own name for Escape")
    func nestedPopoverKeepsItsClaim() {
        let harness = InputChainHarness(width: 60, height: 20)
        let view = Text("p").popover(isPresented: .constant(true)) {
            VStack {
                Button("Revert") {}.keyboardShortcut(.cancelAction)
                Button("More") {}.popover(isPresented: .constant(true)) { Text("note") }
            }
        }
        harness.frame(view)
        harness.frame(view)
        #expect(harness.statusBar.escapeLabelOverride == "close popover")
    }

    @Test("A popover alone still renames its own claim for its cancel button")
    func popoverRenamesItsOwnClaim() {
        let harness = InputChainHarness(width: 60, height: 20)
        let view = Text("p").popover(isPresented: .constant(true)) {
            Button("Revert") {}.keyboardShortcut(.cancelAction)
        }
        harness.frame(view)
        harness.frame(view)
        #expect(harness.statusBar.escapeLabelOverride == "cancel")
    }

    /// The popover's claim was left standing over a sheet presented from
    /// inside it, and the status bar skips every Escape item while a claim
    /// stands: the bar called the sheet's Escape "cancel", the popover's name.
    @Test("A sheet presented from a popover names its own Escape, and Escape closes it")
    func sheetFromPopoverWithdrawsTheClaim() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        func view() -> some View {
            Text("p").popover(isPresented: .constant(true)) {
                Button("Revert") {}
                    .keyboardShortcut(.cancelAction)
                    .sheet(isPresented: model.binding) { Text("sheet") }
            }
        }
        harness.frame(view())
        harness.frame(view())
        #expect(harness.statusBar.escapeLabelOverride == nil, "the popover's claim stands over the sheet")
        let escape = harness.statusBar.currentItems.first { $0.shortcut == Shortcut.escape }
        #expect(escape?.label == "dismiss")
        harness.press(KeyEvent(key: .escape))
        harness.frame(view())
        #expect(!model.presented)
    }

    @Test("An alert presented from a popover withdraws the popover's claim")
    func alertFromPopoverWithdrawsTheClaim() {
        let harness = InputChainHarness(width: 60, height: 20)
        let view = Text("p").popover(isPresented: .constant(true)) {
            Button("Revert") {}
                .keyboardShortcut(.cancelAction)
                .alert("Sure?", isPresented: .constant(true)) { Button("OK") {} }
        }
        harness.frame(view)
        harness.frame(view)
        #expect(harness.statusBar.escapeLabelOverride == nil)
    }

    /// Before the token, the flag was a stored property: set ahead of the
    /// label, it made the label's claim lightweight. With the flag on the
    /// claim, setting it while no claim stood was dropped, and the claim then
    /// grabbed the input — the focused control's key handlers went deaf, and
    /// `t` and `a` were grounded.
    @Test("The lightweight flag set before the label is the label's claim's, and the next claim's no longer")
    func flagBeforeTheLabel() {
        let bar = StatusBarState()
        bar.escapeClaimGrabsInput = false
        bar.escapeLabelOverride = "clear selection"
        #expect(!bar.escapeClaimGrabsInput, "the flag set before the label was dropped")
        bar.escapeLabelOverride = "close menu"
        #expect(bar.escapeClaimGrabsInput, "the next claim inherited it")

        bar.beginSceneRender()
        bar.escapeClaimGrabsInput = false
        bar.withdrawEscapeClaim()
        bar.escapeLabelOverride = "close menu"
        #expect(bar.escapeClaimGrabsInput, "a withdrawal left the kept flag for a later claim")
        bar.beginSceneRender()
        bar.escapeClaimGrabsInput = false
        bar.beginSceneRender()
        bar.escapeLabelOverride = "close menu"
        #expect(bar.escapeClaimGrabsInput, "the kept flag outlived its frame")
    }

    @Test("A new claim grabs the input, whatever the claim it replaced said")
    func newClaimGrabsInput() {
        let bar = StatusBarState()
        bar.escapeLabelOverride = "clear selection"
        bar.escapeClaimGrabsInput = false
        bar.escapeLabelOverride = "close menu"
        #expect(bar.escapeClaimGrabsInput)
        let token = bar.claimEscape("close popover")
        bar.claimEscape("close popover")
        bar.renameEscapeClaim(token, to: "cancel")
        #expect(bar.escapeLabelOverride == "close popover", "a stale token renamed a later claim")
    }
}
