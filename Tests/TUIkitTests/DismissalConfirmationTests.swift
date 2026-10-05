//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissalConfirmationTests.swift
//
//  `dismissalConfirmationDialog` through the real input chain: Escape on a
//  sheet, Escape on a popover, the quit key at the top level and the
//  content's own `dismiss()` ask first while there is something to lose; Cancel keeps what was about to go, and
//  any other answer lets it go once it has run.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A form whose own Done button calls `dismiss()`, the shape SwiftUI's
/// documentation teaches.
private struct DoneForm: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}

@MainActor
@Suite("Dismissal confirmation", .rendersEnglishUI)
struct DismissalConfirmationTests {
    private let escape = KeyEvent(key: .escape)
    private let enter = KeyEvent(key: .enter)

    /// The page's state, by reference so the bindings a frame built reach it.
    private final class Model {
        var presented = true
        var unsaved = true
        var saved = 0
        var discarded = 0
        var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    }

    private func editor(_ model: Model) -> some View {
        Text("draft")
            .dismissalConfirmationDialog("Save this draft?", shouldPresent: model.unsaved) {
                Button("Save") { model.saved += 1 }
                Button("Don't Save", role: .destructive) { model.discarded += 1 }
            } message: {
                Text("It has not been sent.")
            }
    }

    private func sheet(_ model: Model) -> some View {
        Text("page").sheet(isPresented: model.binding) { editor(model) }
    }

    private func shows(_ buffer: FrameBuffer, _ text: String) -> Bool {
        buffer.compositingOverlays(maxWidth: 60, maxHeight: 20, palette: EnvironmentValues().palette)
            .lines.contains { $0.stripped.contains(text) }
    }

    @Test("Escape on a sheet with unsaved changes asks, and an answer lets the sheet go once it has run")
    func escapeAsksThenProceeds() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        harness.press(escape)
        let asking = harness.frame(sheet(model))
        #expect(model.presented, "the sheet stays while the question is open")
        #expect(shows(asking, "Save this draft?"))
        harness.frame(sheet(model))
        harness.press(enter)  // the dialog's first action, Save
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        #expect(model.saved == 1)
        #expect(!model.presented, "answering Save let the dismissal go ahead")
    }

    @Test("Cancel — Escape, in the dialog — keeps the sheet")
    func cancelKeepsTheSheet() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        harness.press(escape)
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        harness.press(escape)  // the dialog's standard Cancel
        let after = harness.frame(sheet(model))
        #expect(model.presented, "Cancel prevented the dismissal")
        #expect(model.saved == 0 && model.discarded == 0)
        #expect(!shows(after, "Save this draft?"), "and closed the dialog")
    }

    @Test("With nothing to lose, Escape dismisses at once")
    func nothingToLose() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        model.unsaved = false
        harness.frame(sheet(model))
        harness.frame(sheet(model))
        harness.press(escape)
        harness.frame(sheet(model))
        #expect(!model.presented)
    }

    @Test("At the top level the quit key asks first, and quits on an answer")
    func quitAsks() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(editor(model))
        harness.frame(editor(model))
        harness.press(KeyEvent(character: "q"))
        let asking = harness.frame(editor(model))
        #expect(harness.quits == 0)
        #expect(shows(asking, "Save this draft?"))
        harness.frame(editor(model))
        harness.press(enter)
        harness.frame(editor(model))
        #expect(model.saved == 1 && harness.quits == 1, "Save ran, then the app quit")
    }

    /// Decisions B36 meets the question: it has Cancel and another answer, so
    /// by the automatic rule it holds the quit key while it is up; an app
    /// that lets the quit key work under dialogs gets the question asked
    /// again, never a quit past it.
    @Test("While the question is up the quit key is held, or with dialogs told not to hold it, asks again")
    func quitWhileAsking() {
        for letsQuitWork in [false, true] {
            let harness = InputChainHarness(width: 60, height: 20)
            let model = Model()
            let page = {
                letsQuitWork ? AnyView(editor(model).dialogPreventsAppTermination(false)) : AnyView(editor(model))
            }
            harness.frame(page())
            harness.frame(page())
            harness.press(KeyEvent(character: "q"))
            harness.frame(page())
            harness.frame(page())
            harness.press(KeyEvent(character: "q"))
            let after = harness.frame(page())
            harness.frame(page())
            #expect(harness.quits == 0, "the quit key quit past the question (letsQuitWork: \(letsQuitWork))")
            #expect(shows(after, "Save this draft?"))
            #expect(model.saved == 0 && model.discarded == 0)
        }
    }

    private func doneSheet(_ model: Model) -> some View {
        Text("page").sheet(isPresented: model.binding) {
            DoneForm()
                .dismissalConfirmationDialog("Save this draft?", shouldPresent: model.unsaved) {
                    Button("Save") { model.saved += 1 }
                    Button("Don't Save", role: .destructive) { model.discarded += 1 }
                }
        }
    }

    /// Decisions B37's fuller version: the content's `\.dismiss` is wrapped.
    @Test("The content's own dismiss() asks while there is something to lose, and dismisses at once when not")
    func ownDismissAsks() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        harness.frame(doneSheet(model))
        harness.frame(doneSheet(model))
        harness.press(enter)  // Done
        let asking = harness.frame(doneSheet(model))
        #expect(model.presented, "dismiss() closed the sheet without asking")
        #expect(shows(asking, "Save this draft?"))
        harness.frame(doneSheet(model))
        harness.press(enter)  // Save
        harness.frame(doneSheet(model))
        harness.frame(doneSheet(model))
        #expect(model.saved == 1)
        #expect(!model.presented, "answering Save let dismiss() go ahead")

        let clean = Model()
        clean.unsaved = false
        let other = InputChainHarness(width: 60, height: 20)
        other.frame(doneSheet(clean))
        other.frame(doneSheet(clean))
        other.press(enter)
        other.frame(doneSheet(clean))
        #expect(!clean.presented, "with nothing to lose, dismiss() dismisses")
    }

    @Test("Escape on a popover with unsaved changes asks too")
    func popoverAsks() {
        let harness = InputChainHarness(width: 60, height: 20)
        let model = Model()
        let page = { Text("page").popover(isPresented: model.binding) { editor(model) } }
        harness.frame(page())
        harness.frame(page())
        harness.press(escape)
        harness.frame(page())
        #expect(model.presented, "the popover stays while the question is open")

        let plain = InputChainHarness(width: 60, height: 20)
        let saved = Model()
        saved.unsaved = false
        let savedPage = { Text("page").popover(isPresented: saved.binding) { editor(saved) } }
        plain.frame(savedPage())
        plain.frame(savedPage())
        plain.press(escape)
        plain.frame(savedPage())
        #expect(!saved.presented, "with nothing to lose, the same Escape closes it")
    }
}
