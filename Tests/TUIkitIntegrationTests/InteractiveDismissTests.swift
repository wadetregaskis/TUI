//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InteractiveDismissTests.swift
//
//  `interactiveDismissDisabled(_:)` — a sheet that insists on an answer.
//
//  The two halves that matter are opposite in sign, so both are pinned: the
//  reader's own routes out (Escape, a click outside) STOP working, and every
//  programmatic one — a Done button, `@Environment(\.dismiss)` — keeps
//  working. A modifier that took both away would just be a stuck dialog.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Interactive dismissal can be disabled", .rendersEnglishUI)
struct InteractiveDismissTests {

    /// A frame rendered the way the run loop does, reporting what the
    /// presentation left behind: the status bar's Escape offer, and the modal's
    /// own rendered height.
    private func present(
        _ view: some View, width: Int = 60, height: Int = 20
    ) -> (
        escapeLabels: [String], overlayHeight: Int, context: TUIContext, statusBar: StatusBarState,
        focusManager: FocusManager?
    ) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        // A status bar of this frame's own. `StatusBarKey`'s default value is a
        // SHARED instance, so without this every test in the suite registers
        // into the same object and a parallel neighbour's "dismiss" is read as
        // this one's. And `RenderLoop` wires the focus manager at the start of
        // every pass: without it the bar cannot resolve which section's items
        // are showing, and every assertion below reads an empty list and passes
        // for the wrong reason.
        let statusBar = StatusBarState()
        statusBar.focusManager = environment.focusManager
        environment.statusBar = statusBar
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        environment.focusManager?.endRenderPass()

        let escapes = statusBar.currentUserItems
            .filter { $0.shortcut == Shortcut.escape }
            .map { $0.label }
        let tallest = buffer.overlays.map { $0.content.height }.max() ?? 0
        return (escapes, tallest, tui, statusBar, environment.focusManager)
    }

    private func sheet(
        _ disabled: Bool?, isPresented: Binding<Bool> = .constant(true)
    ) -> some View {
        Text(verbatim: "page").sheet(isPresented: isPresented) {
            if let disabled {
                Text(verbatim: "body").interactiveDismissDisabled(disabled)
            } else {
                Text(verbatim: "body")
            }
        }
    }

    // MARK: - The status bar's offer

    /// The fixture first: an ordinary sheet really does offer Escape, so the
    /// tests below are measuring its removal rather than its absence.
    @Test("an ordinary sheet offers ESC = dismiss")
    func baselineOffersEscape() {
        #expect(present(sheet(nil)).escapeLabels.contains("dismiss"))
    }

    /// Removing the binding without removing the offer would be worse than
    /// leaving both: the status bar would advertise a way out that does nothing.
    @Test("a dismissal-disabled sheet offers no ESC at all")
    func disabledRemovesEscape() {
        #expect(!present(sheet(true)).escapeLabels.contains("dismiss"))
    }

    @Test("passing false changes nothing")
    func falseIsANoOp() {
        #expect(present(sheet(false)).escapeLabels.contains("dismiss"))
    }

    // MARK: - Escape stays the sheet's

    /// An app's own Escape, declared outside the presentation — the Example's
    /// "⎋ back" on every page — is live behind a sheet. A sheet that will not
    /// close must still keep the key: unclaimed, it fell through to that item,
    /// which took the page away from under a sheet still insisting on an
    /// answer.
    ///
    /// Read with the frame's focus manager kept alive: the bar holds it weakly,
    /// and released, it cannot tell which section's items are showing.
    @Test("a dismissal-disabled sheet keeps Escape from the app's own binding behind it")
    func escapeStaysWithTheSheet() {
        let back = StateBox(false)
        let outcome = present(
            sheet(true).statusBarItems([
                StatusBarItem(shortcut: Shortcut.escape, label: "back") { back.value = true }
            ]))
        withExtendedLifetime(outcome.focusManager) {
            let offered = outcome.statusBar.currentItems.filter {
                $0.shortcut == Shortcut.escape && $0.displayInStatusBar
            }
            #expect(offered.isEmpty, "the bar offers \(offered.map(\.label))")
            _ = outcome.statusBar.handleKeyEvent(KeyEvent(key: .escape))
            _ = outcome.context.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        }
        #expect(!back.value, "Escape reached the app's binding behind the sheet")
    }

    /// The other half of keeping the key: a cancel button is an answer, so
    /// Escape still presses it — as on a Mac — and the bar says so.
    @Test("Escape still presses a dismissal-disabled sheet's cancel button")
    func escapePressesCancel() {
        let cancelled = StateBox(false)
        let outcome = present(
            Text(verbatim: "page").sheet(isPresented: .constant(true)) {
                Button("Cancel") { cancelled.value = true }
                    .keyboardShortcut(.cancelAction)
                    .interactiveDismissDisabled()
            })
        #expect(outcome.escapeLabels.contains("cancel"), "\(outcome.escapeLabels)")
        withExtendedLifetime(outcome.focusManager) {
            _ = outcome.statusBar.handleKeyEvent(KeyEvent(key: .escape))
        }
        #expect(cancelled.value, "Escape did not press the cancel button")
    }

    // MARK: - What still works

    /// The whole point of the modifier rather than a stuck dialog: the app can
    /// still close it, once whatever it was insisting on is done.
    @Test("dismiss() still closes a dismissal-disabled sheet")
    func programmaticStillWorks() {
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        _ = present(sheet(true, isPresented: binding))
        #expect(box.value, "the fixture is presented")
        binding.wrappedValue = false
        #expect(!box.value, "the binding is still the way out")
    }

    // MARK: - Composition with the other presentation trait

    /// Both traits travel as wrapper views the presenter looks for. Applied
    /// together one is necessarily inside the other, so it has to be found
    /// through the outer one — and it has to work identically either way round,
    /// which is exactly the kind of asymmetry nobody would think to check.
    ///
    /// The detent's height is observed through a `Panel`, because that is where
    /// a detent lands: on the sheet's own box. Boxless content has nothing to
    /// stretch and keeps its size, so a bare `Text` would prove nothing here.
    @Test("it composes with presentationDetents in both orders", arguments: [true, false])
    func composesWithDetents(dismissOutermost: Bool) {
        let outcome = present(
            Text(verbatim: "page").sheet(isPresented: .constant(true)) {
                if dismissOutermost {
                    Panel("box") { Text(verbatim: "body") }
                        .presentationDetents([.height(7)])
                        .interactiveDismissDisabled()
                } else {
                    Panel("box") { Text(verbatim: "body") }
                        .interactiveDismissDisabled()
                        .presentationDetents([.height(7)])
                }
            })
        #expect(
            !outcome.escapeLabels.contains("dismiss"),
            "the dismissal trait was found (outermost: \(dismissOutermost))")
        #expect(
            outcome.overlayHeight == 7,
            "…and so was the detent (outermost: \(dismissOutermost))")
    }

    // MARK: - Popover

    /// A popover's Escape is a key handler rather than a status-bar action, so
    /// it is dispatched for real: registering nothing and registering something
    /// inert are indistinguishable from the outside, and only one of them is
    /// what was asked for.
    @Test("Escape does not close a dismissal-disabled popover", arguments: [true, false])
    func popoverEscape(disabled: Bool) {
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let outcome = present(
            Text(verbatim: "anchor").popover(isPresented: binding) {
                Text(verbatim: "inside").interactiveDismissDisabled(disabled)
            })
        _ = outcome.context.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        #expect(box.value == disabled, "Escape closes it only when allowed to")
    }

    // MARK: - Written anywhere in the content

    /// Terms the reader must accept, which say so in their own body.
    private struct Terms: View {
        var body: some View {
            Text(verbatim: "terms").interactiveDismissDisabled(true)
        }
    }

    @Test("Written in a view of the app's own, or under a modifier, it still holds the sheet")
    func anywhereInTheSheet() {
        // The deviations sweep's likely bug 16 (semantic audit 40): SwiftUI
        // honours it "from anywhere inside the presented content"; read off the
        // content's outermost trait chain alone, these two closed on Escape.
        let own = present(Text(verbatim: "page").sheet(isPresented: .constant(true)) { Terms() })
        #expect(!own.escapeLabels.contains("dismiss"), "\(own.escapeLabels)")
        let padded = present(
            Text(verbatim: "page").sheet(isPresented: .constant(true)) {
                Text(verbatim: "terms").interactiveDismissDisabled(true).padding()
            })
        #expect(!padded.escapeLabels.contains("dismiss"), "\(padded.escapeLabels)")
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let dispatched = present(Text(verbatim: "page").sheet(isPresented: binding) { Terms() })
        _ = dispatched.context.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        #expect(box.value, "Escape closed a sheet whose content forbade it")
    }

    @Test("Written in a view of the app's own, it still holds a popover against Escape")
    func anywhereInThePopover() {
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let outcome = present(Text(verbatim: "anchor").popover(isPresented: binding) { Terms() })
        _ = outcome.context.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        #expect(box.value, "Escape closed a popover whose content forbade it")
    }
}
