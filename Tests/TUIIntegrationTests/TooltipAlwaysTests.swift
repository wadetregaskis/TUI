//  🖥️ TUI — A Terminal UI framework for Swift
//  TooltipAlwaysTests.swift
//
//  `tooltips(.always)`: every `help(_:)` draws its own panel. Moved out of
//  HelpTooltipTests.swift, which had reached SwiftLint's file length.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

// MARK: - Every tooltip at once

/// `tooltips(.always)` — the first-launch tour: every `help(_:)` in the subtree
/// draws its own panel, unprompted, for as long as the subtree is on screen.
///
/// This mode resolves no candidate: there is no "which tooltip is showing", so
/// `HelpModifier` simply attaches its own panel, and the screen root places the
/// set (`TooltipPeerPlacementTests`, and `HelpRunLoopTests` through the run
/// loop).
@MainActor
@Suite("Tooltips shown all at once")
struct TooltipAlwaysTests {

    private func harness(trigger: TooltipTrigger, style: TooltipStyle = .popover)
        -> (tui: TUIContext, context: RenderContext)
    {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = FocusManager()
        env.tooltipTrigger = trigger
        env.tooltipStyle = style
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 12, environment: env, tuiContext: tui)
        )
    }

    private func panels(_ buffer: FrameBuffer) -> [OverlayLayer] {
        buffer.overlays.filter { $0.level == .popover }
    }

    @Test("Every help'd view draws its own panel, with nothing touched")
    func everyPanelDraws() {
        let h = harness(trigger: .always)
        let view = VStack {
            Button("One") {}.help("the first thing")
            Button("Two") {}.help("the second thing")
            Button("Three") {}.help("the third thing")
        }
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).count == 3, "one per help: \(panels(buffer).count)")
    }

    /// The panel is wrapped against the screen, not against the control: an
    /// `HStack` (a toolbar run, a fixed frame) offers a button only its own
    /// width, and wrapped at that, "Save the document to disk" was a column of
    /// fragments four cells wide. A `VStack` offers its own width, which is
    /// why `everyPanelDraws` never saw it.
    @Test("A help in an HStack is wrapped to the screen, not to its button")
    func panelInARowIsNotWrappedToItsControl() {
        let h = harness(trigger: .always)
        let view = HStack { Button("Save") {}.help("Save the document to disk") }
        let found = panels(renderToBuffer(view, context: h.context))
        #expect(found.count == 1, "one panel: \(found.count)")
        let rows = found.first?.content.lines.map(\.stripped) ?? []
        #expect(rows.count == 3, "top, one text row, bottom: \(rows)")
        #expect(
            rows.contains { $0.contains("Save the document to disk") },
            "the sentence on one row: \(rows)")
    }

    /// …and `.automatic` draws none of them without a hover or the help key, which
    /// is what makes the count above mean something.
    @Test("Under .automatic nothing draws unprompted")
    func automaticDrawsNothing() {
        let h = harness(trigger: .automatic)
        let view = VStack {
            Button("One") {}.help("the first thing")
            Button("Two") {}.help("the second thing")
        }
        #expect(panels(renderToBuffer(view, context: h.context)).isEmpty, "nothing unprompted")
    }

    /// **`.always` forces the popover presentation**, because the status bar has
    /// one row and this mode has many tooltips.
    ///
    /// The override travels on the CANDIDATE rather than being applied by the run
    /// loop, because `tooltipStyle` is a subtree setting and the run loop has only
    /// the root environment — the same reason `Candidate.style` exists. Without it
    /// the bar would show the hovered tooltip as a second, redundant presentation
    /// of a panel already on screen.
    @Test("The status-bar style is overridden rather than doubled up")
    func statusBarStyleIsOverridden() {
        let h = harness(trigger: .always, style: .statusBar)
        let view = Button("One") {}.help("the first thing")
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).count == 1, "the panel drew")
        #expect(
            h.tui.tooltipState.focused?.style == .popover,
            "candidate says popover so the bar declines: \(h.tui.tooltipState.focused?.style as Any)")
    }

    /// `.never` still wins over `.always`, since it is the same axis: nothing is
    /// published and nothing draws.
    @Test("tooltips(.never) beats everything")
    func neverStillWins() {
        let h = harness(trigger: .never)
        let view = Button("One") {}.help("the first thing")
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).isEmpty, "no panel")
        #expect(h.tui.tooltipState.focused == nil, "and no candidate")
    }
}
