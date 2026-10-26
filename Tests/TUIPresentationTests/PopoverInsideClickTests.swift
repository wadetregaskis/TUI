//  🖥️ TUI — A Terminal UI framework for Swift
//  PopoverInsideClickTests.swift
//
//  A click inside a popover that nothing in it takes — its text, its border, a
//  disabled button — leaves it up, as a click inside a macOS popover does
//  (`NSPopover.Behavior.transient` closes on interaction OUTSIDE it). The
//  panel's dismiss backdrop sat under the whole screen, the panel included, so
//  such a click fell through to it and closed the popover (lane TOOLBARS saw
//  it; the Overlays page's popover reproduced it in a PTY).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A click inside a popover")
struct PopoverInsideClickTests {
    @MainActor
    private final class Flag {
        var value = true
        var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 60
        return (tui, RenderContext(availableWidth: 60, availableHeight: 20, environment: environment, tuiContext: tui))
    }

    /// One frame as the run loop draws it: composited, its regions armed.
    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let composited = renderToBuffer(view, context: context).compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return composited
    }

    private func click(_ button: MouseButton = .left, at cell: (x: Int, y: Int), tui: TUIContext) {
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: button, phase: .pressed, x: cell.x, y: cell.y))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: button, phase: .released, x: cell.x, y: cell.y))
    }

    private func cell(of text: String, in screen: FrameBuffer) throws -> (x: Int, y: Int) {
        let row = try #require(screen.lines.firstIndex { $0.stripped.contains(text) }, "\(text) is on screen")
        let line = screen.lines[row].stripped
        let column = try #require(line.range(of: text)).lowerBound
        return (line.distance(from: line.startIndex, to: column), row)
    }

    private func page(_ flag: Flag) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Anchor")
                .popover(isPresented: flag.binding) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Inert words here")
                        Button("Unavailable") {}.disabled(true)
                    }
                }
            Text("Page below")
            Text("Page below")
            Text("Page below")
            Text("Page below")
            Text("Page below")
        }
    }

    @Test("A click on its text, on a disabled button or on its border leaves it up")
    func insideClicksKeepItUp() throws {
        let (tui, context) = harness()
        let flag = Flag()
        let view = page(flag)
        let open = frame(view, tui: tui, context: context)
        let words = try cell(of: "Inert words", in: open)
        let disabled = try cell(of: "Unavailable", in: open)

        click(at: (words.x + 2, words.y), tui: tui)
        #expect(flag.value, "a click on the popover's text closed it")
        frame(view, tui: tui, context: context)
        click(at: (disabled.x + 1, disabled.y), tui: tui)
        #expect(flag.value, "a click on a disabled button in the popover closed it")
        frame(view, tui: tui, context: context)
        // The border's left wall, beside the text.
        click(at: (words.x - 2, words.y), tui: tui)
        #expect(flag.value, "a click on the popover's border closed it")
        frame(view, tui: tui, context: context)
        click(.right, at: (words.x + 2, words.y), tui: tui)
        #expect(flag.value, "a right-click on the popover's text closed it")
    }

    @Test("A click outside it still closes it")
    func outsideClickClosesIt() {
        let (tui, context) = harness()
        let flag = Flag()
        let view = page(flag)
        frame(view, tui: tui, context: context)
        click(at: (55, 18), tui: tui)
        #expect(!flag.value, "a click outside the popover left it up")
    }
}
