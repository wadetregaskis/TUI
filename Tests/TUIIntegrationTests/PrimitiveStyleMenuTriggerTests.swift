//  🖥️ TUI — A Terminal UI framework for Swift
//  PrimitiveStyleMenuTriggerTests.swift
//
//  A pop-up menu's trigger under a primitive button style (`.glass`, or an
//  app's own `PrimitiveButtonStyle`) is the style's `Button(configuration)`,
//  and it must still be the menu's trigger: open on the press, as every Mac
//  menu does (`MenuPressTrackingTests`). The configuration carried only the
//  role, the label and the action, so the button the style built was an
//  ordinary one, and the menu opened on the release.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A menu trigger under a primitive button style")
struct PrimitiveStyleMenuTriggerTests {
    private func harness(width: Int = 40, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.overlayContentHeight = height
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        )
    }

    /// Renders a full frame and arms the dispatcher with the composited
    /// regions, as the run loop does (`MenuPressTrackingTests.renderArmed`).
    @discardableResult
    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    @Test("Under .glass, pressing a pop-up menu's label opens it before the button comes back up")
    func menuUnderGlassOpensOnThePress() {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("Rename") {}
            Button("Delete") {}
        }
        .selectionIndicatorStyle(.none)
        .buttonStyle(.glass)

        renderArmed(view, tui: tui, context: context)
        context.environment.focusManager?.noteInputSource(.pointer)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        let opened = renderArmed(view, tui: tui, context: context)

        #expect(!opened.overlays.isEmpty, "\(opened.lines.map(\.stripped))")
    }
}
