//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationCancelButtonTests.swift
//
//  Escape on a sheet or a popover whose content draws a cancel button presses
//  that button: the status bar names the key for it, "cancel" rather than the
//  presentation's own "dismiss" or "close popover", and a held Escape's
//  repeats press it again only if the button repeats.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport

@MainActor
@Suite("A presentation's cancel button on Escape", .rendersEnglishUI)
struct PresentationCancelButtonTests {
    /// The page's state, by reference so the bindings a frame built reach it.
    private final class Model {
        var presented = true
        /// Whether a dismissal confirmation would ask.
        var unsaved = false
        /// How many times the cancel button's action ran. It does not
        /// dismiss: what Escape does is the button's to decide.
        var cancels = 0
        var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    }

    /// The content of a sheet with a `.cancellationAction` item, and a
    /// dismissal confirmation that asks while `model.unsaved`.
    private func draft(_ model: Model, repeats: Bool = false) -> some View {
        Text("draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Revert") { model.cancels += 1 }
                        .buttonRepeatBehavior(repeats ? .enabled : .automatic)
                }
            }
            .dismissalConfirmationDialog("Discard?", shouldPresent: model.unsaved) {
                Button("Discard", role: .destructive) {}
            }
    }

    private func sheet(_ model: Model, repeats: Bool = false) -> some View {
        Text("page").sheet(isPresented: model.binding) { draft(model, repeats: repeats) }
    }

    /// A sheet whose content puts items of its own in the sheet's section,
    /// which replace its ESC item: Escape reaches the sheet's key handler.
    private func sheetWithItems(_ model: Model) -> some View {
        Text("page").sheet(isPresented: model.binding) {
            draft(model).statusBarItems([StatusBarItem(shortcut: "r", label: "reload")])
        }
    }

    private func plainSheet(_ model: Model) -> some View {
        Text("page").sheet(isPresented: model.binding) { Text("draft") }
    }

    private func popover(_ model: Model, repeats: Bool = false) -> some View {
        Text("page").popover(isPresented: model.binding) {
            Button("Revert") { model.cancels += 1 }
                .keyboardShortcut(.cancelAction)
                .buttonRepeatBehavior(repeats ? .enabled : .automatic)
        }
    }

    /// Escape, then two of its repeats, a frame after each, into the view
    /// `build` makes: how many times the cancel button ran, and whether each
    /// key was taken.
    private func holdEscape(_ model: Model, _ build: () -> some View) -> (cancels: Int, taken: [Bool]) {
        let harness = InputChainHarness(width: 60, height: 20)
        let taken = harness.play(
            [
                KeyEvent(key: .escape), KeyEvent(key: .escape, phase: .repeat),
                KeyEvent(key: .escape, phase: .repeat),
            ], build)
        return (model.cancels, taken)
    }

    private func plainPopover(_ model: Model) -> some View {
        Text("page").popover(isPresented: model.binding) { Text("note") }
    }

    /// The labels of the bar's Escape items, as the bar draws them.
    private func escapeLabels(_ harness: InputChainHarness) -> [String] {
        harness.statusBar.currentItems
            .filter { $0.shortcut == Shortcut.escape }
            .map { harness.statusBar.escapeLabelOverride ?? $0.label }
    }

    @Test("A sheet's Escape is called cancel while it presses the cancel button, and dismiss otherwise")
    func sheetNamesItsCancelButton() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        #expect(escapeLabels(harness) == ["cancel"], "\(escapeLabels(harness))")

        let plain = InputChainHarness(width: 60, height: 20)
        plain.frame(plainSheet(model))
        plain.frame(plainSheet(model))
        #expect(escapeLabels(plain) == ["dismiss"], "no cancel button: \(escapeLabels(plain))")

        let asking = InputChainHarness(width: 60, height: 20)
        let unsaved = Model()
        unsaved.unsaved = true
        asking.frame(sheet(unsaved))
        asking.frame(sheet(unsaved))
        #expect(escapeLabels(asking) == ["dismiss"], "Escape asks to dismiss first: \(escapeLabels(asking))")
    }

    @Test("A popover's Escape is called cancel while it presses the cancel button, and close popover otherwise")
    func popoverNamesItsCancelButton() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(popover(model))
        harness.frame(popover(model))
        #expect(harness.statusBar.escapeLabelOverride == "cancel")

        let plain = InputChainHarness(width: 60, height: 20)
        plain.frame(plainPopover(model))
        plain.frame(plainPopover(model))
        #expect(plain.statusBar.escapeLabelOverride == "close popover")
    }

    @Test("A held Escape presses a sheet's cancel button once, unless the button repeats")
    func sheetCancelButtonRepeatsOnlyIfItDoes() {
        let model = Model()
        let held = holdEscape(model) { sheet(model) }
        #expect(held.cancels == 1, "the press, not the repeats")
        #expect(held.taken == [true, true, true], "the repeats are taken, and reach nothing else")
        #expect(model.presented)

        let repeating = Model()
        #expect(holdEscape(repeating) { sheet(repeating, repeats: true) }.cancels == 3)
    }

    @Test("So does a held Escape that reaches the sheet's key handler, with no ESC item on the bar")
    func sheetHandlerRepeatsOnlyIfTheButtonDoes() {
        let model = Model()
        let held = holdEscape(model) { sheetWithItems(model) }
        #expect(held.cancels == 1)
        #expect(held.taken == [true, true, true])
    }

    @Test("A held Escape presses a popover's cancel button once, unless the button repeats")
    func popoverCancelButtonRepeatsOnlyIfItDoes() {
        let model = Model()
        let held = holdEscape(model) { popover(model) }
        #expect(held.cancels == 1)
        #expect(held.taken == [true, true, true])

        let repeating = Model()
        #expect(holdEscape(repeating) { popover(repeating, repeats: true) }.cancels == 3)
    }
}
