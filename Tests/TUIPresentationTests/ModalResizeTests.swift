//  🖥️ TUI — A Terminal UI framework for Swift
//  ModalResizeTests.swift
//
//  A sheet's size, dragged by its borders and corner: symmetrical about the
//  centre while centred, anchored where moved off it, kept within the
//  terminal, and saved.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

/// A dialog's title grab region: the full-width one-row region nearest the top.
@MainActor
func dialogTitleRegion(_ buffer: FrameBuffer) -> HitTestRegion? {
    let fullWidth = buffer.hitTestRegions.map(\.width).max() ?? 0
    return buffer.hitTestRegions
        .filter { $0.width == fullWidth && $0.height == 1 }
        .min(by: { $0.offsetY < $1.offsetY })
}

@MainActor
@Suite("Modal resizing")
struct ModalResizeTests {
    private func titleRegion(_ buffer: FrameBuffer) -> HitTestRegion? {
        dialogTitleRegion(buffer)
    }

    @Test("Dragging a modal by its bottom-right corner resizes both dimensions symmetrically when centred")
    func draggingCornerResizesModal() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }

        // Find corner grab region (near bottom-right)
        guard let corner = before.hitTestRegions
            .filter({ $0.width <= 2 && $0.height <= 2 })
            .max(by: { ($0.offsetX + $0.offsetY) < ($1.offsetX + $1.offsetY) })
        else {
            Issue.record("no corner grab region")
            return
        }

        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let px = corner.offsetX + corner.width - 1
        let py = corner.offsetY + corner.height - 1
        let dx = 8, dy = 3
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + dx, y: py + dy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + dx, y: py + dy))

        let after = frame()
        guard let movedTitle = titleRegion(after) else {
            Issue.record("no title grab region after drag")
            return
        }
        #expect(movedTitle.offsetX == title.offsetX - dx, "dialog expanded symmetrically to the left by \(dx)")
        #expect(movedTitle.offsetY == title.offsetY - dy, "dialog expanded symmetrically upward by \(dy)")
        #expect(movedTitle.width == title.width + 2 * dx, "dialog width grew symmetrically by \(2 * dx)")
    }

    @Test("Dragging a modal by its right border resizes width symmetrically while keeping height unchanged")
    func draggingRightBorderResizesModalWidthOnly() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }
        guard let rightBorder = before.hitTestRegions
            .filter({ $0.width == 1 && $0.height > 1 })
            .max(by: { $0.offsetX < $1.offsetX })
        else {
            Issue.record("no right border grab region")
            return
        }
        guard let bottomBorder = before.hitTestRegions
            .filter({ $0.width == title.width && $0.height == 1 })
            .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("no bottom border grab region")
            return
        }

        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let px = rightBorder.offsetX
        let py = rightBorder.offsetY + 2
        let dx = 6
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + dx, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + dx, y: py))

        let after = frame()
        guard let movedTitle = titleRegion(after),
              let movedBottom = after.hitTestRegions
                  .filter({ $0.width == movedTitle.width && $0.height == 1 })
                  .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("regions missing after drag")
            return
        }
        #expect(movedTitle.offsetX == title.offsetX - dx, "dialog expanded symmetrically to the left by \(dx)")
        #expect(movedTitle.offsetY == title.offsetY, "top-left anchor did not move vertically")
        #expect(movedTitle.width == title.width + 2 * dx, "dialog width grew symmetrically by \(2 * dx)")
        #expect(movedBottom.offsetY == bottomBorder.offsetY, "dialog height did not change")
    }

    @Test("Dragging a modal by its bottom border resizes height symmetrically while keeping width unchanged")
    func draggingBottomBorderResizesModalHeightOnly() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }
        guard let bottomBorder = before.hitTestRegions
            .filter({ $0.width == title.width && $0.height == 1 })
            .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("no bottom border grab region")
            return
        }

        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let px = bottomBorder.offsetX + 5
        let py = bottomBorder.offsetY
        let dy = 4
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px, y: py + dy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px, y: py + dy))

        let after = frame()
        guard let movedTitle = titleRegion(after),
              let movedBottom = after.hitTestRegions
                  .filter({ $0.width == movedTitle.width && $0.height == 1 })
                  .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("regions missing after drag")
            return
        }
        #expect(movedTitle.offsetX == title.offsetX, "dialog horizontal position did not change")
        #expect(movedTitle.offsetY == title.offsetY - dy, "dialog expanded symmetrically upward by \(dy)")
        #expect(movedTitle.width == title.width, "dialog width did not change")
        #expect(movedBottom.offsetY == bottomBorder.offsetY + dy, "bottom edge shifted down by \(dy)")
    }

    @Test("Dragging a modal by its bottom-right corner resizes anchored when off-centre")
    func draggingCornerResizesModalAnchoredWhenOffCentre() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }

        // Move dialog off-centre first
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let mpx = title.offsetX + title.width / 2
        let mpy = title.offsetY
        let mx = 4, my = 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: mpx, y: mpy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: mpx + mx, y: mpy + my))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: mpx + mx, y: mpy + my))

        let beforeResize = frame()
        guard let movedTitle1 = titleRegion(beforeResize) else {
            Issue.record("no title grab region after move")
            return
        }
        guard let corner = beforeResize.hitTestRegions
            .filter({ $0.width <= 2 && $0.height <= 2 })
            .max(by: { ($0.offsetX + $0.offsetY) < ($1.offsetX + $1.offsetY) })
        else {
            Issue.record("no corner grab region")
            return
        }
        guard let bottomBorder = beforeResize.hitTestRegions
            .filter({ $0.width == movedTitle1.width && $0.height == 1 })
            .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("no bottom border grab region")
            return
        }

        dispatcher.setRegions(beforeResize.hitTestRegions)
        let px = corner.offsetX + corner.width - 1
        let py = corner.offsetY + corner.height - 1
        let dx = 6, dy = 3
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + dx, y: py + dy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + dx, y: py + dy))

        let after = frame()
        guard let movedTitle2 = titleRegion(after),
              let movedBottom = after.hitTestRegions
                  .filter({ $0.width == movedTitle2.width && $0.height == 1 })
                  .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("regions missing after resize drag")
            return
        }
        #expect(movedTitle2.offsetX == movedTitle1.offsetX, "top-left anchor did not move horizontally")
        #expect(movedTitle2.offsetY == movedTitle1.offsetY, "top-left anchor did not move vertically")
        #expect(movedTitle2.width == movedTitle1.width + dx, "dialog width grew by \(dx)")
        #expect(movedBottom.offsetY == bottomBorder.offsetY + dy, "bottom edge shifted down by \(dy)")
    }

    @Test("Dragging a modal by its right border resizes width anchored when off-centre")
    func draggingRightBorderResizesModalAnchoredWhenOffCentre() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }

        // Move dialog off-centre first
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let mpx = title.offsetX + title.width / 2
        let mpy = title.offsetY
        let mx = 4, my = 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: mpx, y: mpy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: mpx + mx, y: mpy + my))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: mpx + mx, y: mpy + my))

        let beforeResize = frame()
        guard let movedTitle1 = titleRegion(beforeResize) else {
            Issue.record("no title grab region after move")
            return
        }
        guard let rightBorder = beforeResize.hitTestRegions
            .filter({ $0.width == 1 && $0.height > 1 })
            .max(by: { $0.offsetX < $1.offsetX })
        else {
            Issue.record("no right border grab region")
            return
        }
        guard let bottomBorder = beforeResize.hitTestRegions
            .filter({ $0.width == movedTitle1.width && $0.height == 1 })
            .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("no bottom border grab region")
            return
        }

        dispatcher.setRegions(beforeResize.hitTestRegions)
        let px = rightBorder.offsetX
        let py = rightBorder.offsetY + 2
        let dx = 6
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + dx, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + dx, y: py))

        let after = frame()
        guard let movedTitle2 = titleRegion(after),
              let movedBottom = after.hitTestRegions
                  .filter({ $0.width == movedTitle2.width && $0.height == 1 })
                  .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("regions missing after resize drag")
            return
        }
        #expect(movedTitle2.offsetX == movedTitle1.offsetX, "top-left anchor did not move horizontally")
        #expect(movedTitle2.offsetY == movedTitle1.offsetY, "top-left anchor did not move vertically")
        #expect(movedTitle2.width == movedTitle1.width + dx, "dialog width grew by \(dx)")
        #expect(movedBottom.offsetY == bottomBorder.offsetY, "dialog height did not change")
    }

    @Test("Dragging a modal by its bottom border resizes height anchored when off-centre")
    func draggingBottomBorderResizesModalAnchoredWhenOffCentre() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }

        // Move dialog off-centre first
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let mpx = title.offsetX + title.width / 2
        let mpy = title.offsetY
        let mx = 4, my = 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: mpx, y: mpy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: mpx + mx, y: mpy + my))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: mpx + mx, y: mpy + my))

        let beforeResize = frame()
        guard let movedTitle1 = titleRegion(beforeResize) else {
            Issue.record("no title grab region after move")
            return
        }
        guard let bottomBorder = beforeResize.hitTestRegions
            .filter({ $0.width == movedTitle1.width && $0.height == 1 })
            .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("no bottom border grab region")
            return
        }

        dispatcher.setRegions(beforeResize.hitTestRegions)
        let px = bottomBorder.offsetX + 5
        let py = bottomBorder.offsetY
        let dy = 4
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px, y: py + dy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px, y: py + dy))

        let after = frame()
        guard let movedTitle2 = titleRegion(after),
              let movedBottom = after.hitTestRegions
                  .filter({ $0.width == movedTitle2.width && $0.height == 1 })
                  .max(by: { $0.offsetY < $1.offsetY })
        else {
            Issue.record("regions missing after resize drag")
            return
        }
        #expect(movedTitle2.offsetX == movedTitle1.offsetX, "dialog horizontal position did not change")
        #expect(movedTitle2.offsetY == movedTitle1.offsetY, "top-left anchor did not move vertically")
        #expect(movedTitle2.width == movedTitle1.width, "dialog width did not change")
        #expect(movedBottom.offsetY == bottomBorder.offsetY + dy, "bottom edge shifted down by \(dy)")
    }

    @Test("A saved 200×60 sheet in an 80×24 terminal still has reachable grips")
    func savedOversizedSheetHasReachableGrips() {
        let view = VStack { Text("bg") }
            .sheet(isPresented: .constant(true)) {
                Dialog(title: "Resizable") { Text("body") }
                    .presentationPersistedSize(width: 200, height: 60)
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 80, height = 24
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        fm.beginRenderPass()
        let raw = renderToBuffer(view, context: context)
        fm.endRenderPass()
        let frame = raw.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: context.environment.palette)

        // In an 80×24 terminal, the grips must be within the terminal bounds and reachable.
        let corner = frame.hitTestRegions
            .filter({ $0.width <= 2 && $0.height <= 2 })
            .max(by: { ($0.offsetX + $0.offsetY) < ($1.offsetX + $1.offsetY) })
        #expect(corner != nil, "corner grab region must be present and reachable")

        let rightBorder = frame.hitTestRegions
            .filter({ $0.width == 1 && $0.height > 1 })
            .max(by: { $0.offsetX < $1.offsetX })
        #expect(rightBorder != nil, "right border grab region must be present")
        if let rightBorder {
            #expect(rightBorder.offsetX < width, "right border must be within terminal bounds")
        }

        let bottomBorder = frame.hitTestRegions
            .filter({ $0.height == 1 && $0.width > 2 })
            .max(by: { $0.offsetY < $1.offsetY })
        #expect(bottomBorder != nil, "bottom border grab region must be present")
        if let bottomBorder {
            #expect(bottomBorder.offsetY < height, "bottom border must be within terminal bounds")
        }

        // When the terminal grows again, the unclamped user size comes back.
        var largerEnv = env
        largerEnv.terminalWidth = 250
        largerEnv.overlayContentHeight = 80
        let largerContext = RenderContext(
            availableWidth: 250, availableHeight: 80, environment: largerEnv, tuiContext: tui)
        fm.beginRenderPass()
        let largerRaw = renderToBuffer(view, context: largerContext)
        fm.endRenderPass()
        guard let modalOverlay = largerRaw.overlays.first(where: { $0.level == .modal }) else {
            Issue.record("no modal overlay in larger terminal")
            return
        }
        #expect(modalOverlay.content.width == 200, "user's saved size returns when the terminal grows")
        #expect(modalOverlay.content.height == 60, "user's saved size returns when the terminal grows")
    }

    @Test("A saved width of 0 renders at the minimum")
    func savedZeroWidthRendersAtMinimum() {
        let view = VStack { Text("bg") }
            .sheet(isPresented: .constant(true)) {
                Text("x")
                    .presentationPersistedSize(width: 0, height: nil)
            }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 80, height = 24
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        fm.beginRenderPass()
        let raw = renderToBuffer(view, context: context)
        fm.endRenderPass()

        guard let modalOverlay = raw.overlays.first(where: { $0.level == .modal }) else {
            Issue.record("no modal overlay")
            return
        }
        #expect(modalOverlay.content.width == _DialogDragHandler.minWidth)
    }

    @Test("onResize closure does not survive when sheet content changes to one without persisted size")
    func staleOnResizeDoesNotSurviveContentChange() {
        var callCount = 0
        var showPersisted = true

        struct TestView: View {
            @Binding var showPersisted: Bool
            let onResize: () -> Void

            var body: some View {
                VStack { Text("bg") }
                    .modal(isPresented: .constant(true)) {
                        if showPersisted {
                            Dialog(title: "Resizable") { Text("body") }
                                .presentationPersistedSize(width: 40, height: 10, onResize: { _, _ in onResize() })
                        } else {
                            Dialog(title: "Resizable") { Text("body") }
                        }
                    }
            }
        }

        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let width = 70, height = 24
        env.terminalWidth = width
        env.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        let binding = Binding(get: { showPersisted }, set: { showPersisted = $0 })
        let view = TestView(showPersisted: binding, onResize: { callCount += 1 })

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        // Pass 1: Render with persisted size and onResize
        _ = frame()

        // Pass 2: Switch to content without persisted size
        showPersisted = false
        let secondFrame = frame()

        // Drag corner in Pass 2
        guard let corner = secondFrame.hitTestRegions
            .filter({ $0.width <= 2 && $0.height <= 2 })
            .max(by: { ($0.offsetX + $0.offsetY) < ($1.offsetX + $1.offsetY) })
        else {
            Issue.record("no corner grab region")
            return
        }

        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(secondFrame.hitTestRegions)
        let px = corner.offsetX + corner.width - 1
        let py = corner.offsetY + corner.height - 1
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + 2, y: py + 2))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + 2, y: py + 2))

        #expect(callCount == 0, "stale onResize must not be called after content changes to one without persisted size")
    }
}
