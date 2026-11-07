//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogDrag.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Dialog Drag

/// Makes a presented dialog draggable by its title bar and border, and optionally
/// resizable by dragging its bottom/right borders or bottom-right corner.
///
/// Shared by the modal/sheet and alert presentation hosts. A dialog is centred
/// by the compositor; this adds a persisted `(x, y)` offset that the user can
/// change by dragging the dialog's title row or border. ``OverlayLayer/placed(maxWidth:maxHeight:)``
/// applies that offset as a post-centre delta and clamps it so the whole dialog
/// stays on screen.
///
/// The grab region is only the title row and the border frame — the interior is
/// left free so the dialog's own controls still receive their clicks.
@MainActor
enum DialogDrag {
    /// Wires the dialog `buffer`'s title/border cells as a drag handle and
    /// returns the current offset to feed into the centred ``OverlayLayer``.
    /// Returns `(0, 0)` while measuring or when no dispatcher/state is available.
    @MainActor
    static func offset(
        for buffer: inout FrameBuffer,
        context: RenderContext,
        propertyIndex: Int,
        resizable: Bool = false
    ) -> (x: Int, y: Int) {
        guard !context.isMeasuring, let stateStorage = context.stateStorage else {
            return (0, 0)
        }
        let box: StateBox<_DialogDragHandler> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex),
            default: _DialogDragHandler())
        let handler = box.value
        handler.currentWidth = buffer.width
        handler.currentHeight = buffer.height

        if let mouseDispatcher = context.environment.mouseEventDispatcher {
            // Clicks claim the press; drag reporting moves the dialog.
            mouseDispatcher.requestFeature(.clicks, in: context)
            mouseDispatcher.requestFeature(.drag, in: context)
            if resizable {
                mouseDispatcher.requestFeature(.motion, in: context)
            }
            appendGrabRegions(
                to: &buffer, handler: handler, resizable: resizable, context: context)
        }

        // Trim any overshoot from dragging hard past an edge so the next grab
        // starts from the on-screen range rather than through a dead zone. The
        // display was already clamped by OverlayLayer.placed(); this keeps the
        // *stored* offset in step. Uses the terminal size — a safe bound (the
        // real composite box is a little shorter, and placed() clamps precisely).
        handler.clampOffset(
            dialogWidth: buffer.width, dialogHeight: buffer.height,
            screenWidth: context.environment.terminalWidth,
            screenHeight: context.environment.terminalHeight)

        if resizable, buffer.width > 0, buffer.height > 1 {
            drawCornerGrip(into: &buffer, isHovered: handler.isHovered, context: context)
        }

        return (handler.offsetX, handler.offsetY)
    }

    /// Resets a dialog's drag offset. Called on the dismissed render path so a
    /// re-presented dialog opens centred rather than where it was last dragged.
    static func reset(context: RenderContext, propertyIndex: Int) {
        guard !context.isMeasuring, let stateStorage = context.stateStorage else { return }
        let box: StateBox<_DialogDragHandler> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex),
            default: _DialogDragHandler())
        box.value.reset()
    }

    /// Draws the corner grip mark at the bottom-right corner of a resizable dialog
    /// when the corner is a border cell (preventing damage to arbitrary text content).
    private static func drawCornerGrip(into buffer: inout FrameBuffer, isHovered: Bool, context: RenderContext) {
        let corner = (x: buffer.width - 1, y: buffer.height - 1)
        guard corner.x >= 0, corner.y >= 0, corner.y < buffer.lines.count else { return }
        let existing = buffer.lines[corner.y].stripped.last
        guard let existing, isBorderCell(existing) else { return }
        let glyphs = BorderGrip.Glyphs.standingOut(from: existing)
        let ink = BorderGrip.ink(isFocused: false, isHovered: isHovered, environment: context.environment)
        if BorderGrip.paintsItsCells(existing) {
            BorderGrip.mark(String(existing), cells: 1, into: &buffer, at: corner, ink: ink)
        } else {
            BorderGrip.mark(glyphs.corner, cells: 1, into: &buffer, at: corner, ink: ink)
        }
    }

    private static func isBorderCell(_ cell: Character) -> Bool {
        ("\u{2500}"..."\u{257F}").contains(cell) || ("\u{2580}"..."\u{259F}").contains(cell)
    }

    /// Registers the grab handle — the title row plus the left/right/bottom
    /// border cells, pointing at either the move handler or dedicated edge/corner resize handlers.
    ///
    /// The regions are registered *before* the dialog's own controls (the
    /// existing regions), so the dispatcher's innermost-first (last-registered)
    /// order lets any actual control win: the frame is draggable everywhere a
    /// control is NOT. This matters for `.modal` / `.sheet`, which take
    /// arbitrary content whose controls can sit on row 0, the last row, or an
    /// edge column (a bordered Dialog/Alert keeps those clear, but plain content
    /// need not).
    private static func appendGrabRegions(
        to buffer: inout FrameBuffer,
        handler: _DialogDragHandler,
        resizable: Bool,
        context: RenderContext
    ) {
        guard let mouseDispatcher = context.environment.mouseEventDispatcher else { return }
        let width = buffer.width
        let height = buffer.height
        guard width > 0, height > 0 else { return }

        let screenWidth = context.environment.terminalWidth
        let screenHeight = context.environment.overlayContentHeight

        func register(mode: _DialogDragHandler.DragMode, shape: PointerShape? = nil) -> HitTestRegion.HandlerID {
            let id = mouseDispatcher.register(in: context) { [weak handler] event in
                guard let handler else { return false }
                switch event.phase {
                case .entered:
                    if mode != .move { handler.isHovered = true }
                    return true
                case .exited:
                    if mode != .move { handler.isHovered = false }
                    return true
                case .pressed where event.button == .left:
                    handler.beginDrag(mode: mode, atX: event.x, y: event.y)
                    return true
                case .dragged:
                    handler.updateDrag(
                        toX: event.x, y: event.y,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight)
                    return true
                case .released where event.button == .left:
                    handler.endDrag()
                    return true
                default:
                    return false
                }
            }
            if let shape {
                mouseDispatcher.fileControlPointerShape(shape, for: id, in: context)
            }
            return id
        }

        if !resizable || height <= 1 {
            let moveID = register(mode: .move)
            var grab = [
                HitTestRegion(offsetX: 0, offsetY: 0, width: width, height: 1, handlerID: moveID)  // title row
            ]
            if height > 1 {
                grab.append(
                    HitTestRegion(offsetX: 0, offsetY: height - 1, width: width, height: 1, handlerID: moveID))
                grab.append(
                    HitTestRegion(offsetX: 0, offsetY: 0, width: 1, height: height, handlerID: moveID))
                grab.append(
                    HitTestRegion(offsetX: width - 1, offsetY: 0, width: 1, height: height, handlerID: moveID))
            }
            buffer.hitTestRegions.insert(contentsOf: grab, at: 0)
            return
        }

        let moveID = register(mode: .move)
        let resizeHeightID = register(mode: .resizeHeight, shape: .rowResize)
        let resizeWidthID = register(mode: .resizeWidth, shape: .columnResize)
        let resizeBothID = register(mode: .resizeBoth, shape: .resizeNorthWestSouthEast)

        let cornerSize = min(2, min(width, height))
        let grab = [
            HitTestRegion(offsetX: 0, offsetY: 0, width: width, height: 1, handlerID: moveID),  // title row
            HitTestRegion(offsetX: 0, offsetY: 0, width: 1, height: height, handlerID: moveID),  // left border
            HitTestRegion(offsetX: 0, offsetY: height - 1, width: width, height: 1, handlerID: resizeHeightID),  // bottom
            HitTestRegion(offsetX: width - 1, offsetY: 0, width: 1, height: height, handlerID: resizeWidthID),  // right
            HitTestRegion(
                offsetX: width - cornerSize, offsetY: height - cornerSize,
                width: cornerSize, height: cornerSize,
                handlerID: resizeBothID)  // bottom-right corner
        ]
        buffer.hitTestRegions.insert(contentsOf: grab, at: 0)
    }
}

/// Persisted drag state for a presented dialog: the current offset from centre,
/// plus the press anchor while a drag is in progress. Mirrors the shape of
/// ``_SplitDividerHandler``.
///
/// During a drag the dispatcher delivers coordinates localized to the press
/// region's origin, so the delta to apply is the difference between the current
/// localized coordinate and the one recorded at press time.
package final class _DialogDragHandler {
    package enum DragMode: Sendable {
        case move
        case resizeWidth
        case resizeHeight
        case resizeBoth
    }

    package private(set) var offsetX = 0
    package private(set) var offsetY = 0

    package private(set) var userWidth: Int?
    package private(set) var userHeight: Int?

    package var currentWidth = 0
    package var currentHeight = 0
    package var isHovered = false

    package var onResize: ((Int, Int) -> Void)?

    private var pressLocalX = 0
    private var pressLocalY = 0
    private var pressOffsetX = 0
    private var pressOffsetY = 0
    private var pressWidth = 0
    private var pressHeight = 0
    private var dragMode: DragMode = .move
    private var isDragging = false
    private var didResize = false

    package static let minWidth = 16
    package static let minHeight = 4

    package func setUserWidth(_ width: Int?) {
        userWidth = width
    }

    package func setUserHeight(_ height: Int?) {
        userHeight = height
    }

    /// Records the press point (region-local) and the offset at that moment.
    package func beginDrag(mode: DragMode, atX x: Int, y: Int) {
        isDragging = true
        didResize = false
        pressLocalX = x
        pressLocalY = y
        pressOffsetX = offsetX
        pressOffsetY = offsetY
        pressWidth = currentWidth > 0 ? currentWidth : (userWidth ?? 0)
        pressHeight = currentHeight > 0 ? currentHeight : (userHeight ?? 0)
        dragMode = mode
    }

    /// Legacy convenience for move-only drags.
    package func beginDrag(atX x: Int, y: Int) {
        beginDrag(mode: .move, atX: x, y: y)
    }

    /// Calculates the updated dimension and offset for a single axis during a resize drag.
    /// When the dialog was centred (`pressOffset == 0`), the resize applies symmetrically
    /// to both sides (changing the dimension by `2 * pressDelta`) while remaining centred (`offset = 0`).
    /// When off-centre (`pressOffset != 0`), the opposite edge remains anchored in place on screen.
    private func updatedDimension(
        pressDelta: Int,
        pressDimension: Int,
        pressOffset: Int,
        minDimension: Int,
        screenDimension: Int
    ) -> (dimension: Int, offset: Int) {
        let minD = min(minDimension, screenDimension)
        if pressOffset == 0 {
            let targetD = min(max(minD, pressDimension + 2 * pressDelta), screenDimension)
            return (targetD, 0)
        } else {
            let targetD = min(max(minD, pressDimension + pressDelta), screenDimension)
            let pressCentre = max(0, screenDimension - pressDimension) / 2
            let targetCentre = max(0, screenDimension - targetD) / 2
            let targetOffset = pressOffset + (pressCentre - targetCentre)
            return (targetD, targetOffset)
        }
    }

    /// Applies the drag: either translates the dialog or resizes one or both dimensions.
    package func updateDrag(toX x: Int, y: Int, screenWidth: Int = Int.max, screenHeight: Int = Int.max) {
        guard isDragging else { return }
        switch dragMode {
        case .move:
            offsetX = pressOffsetX + (x - pressLocalX)
            offsetY = pressOffsetY + (y - pressLocalY)
        case .resizeWidth:
            didResize = true
            let (w, ox) = updatedDimension(
                pressDelta: x - pressLocalX,
                pressDimension: pressWidth,
                pressOffset: pressOffsetX,
                minDimension: Self.minWidth,
                screenDimension: screenWidth)
            userWidth = w
            offsetX = ox
        case .resizeHeight:
            didResize = true
            let (h, oy) = updatedDimension(
                pressDelta: y - pressLocalY,
                pressDimension: pressHeight,
                pressOffset: pressOffsetY,
                minDimension: Self.minHeight,
                screenDimension: screenHeight)
            userHeight = h
            offsetY = oy
        case .resizeBoth:
            didResize = true
            let (w, ox) = updatedDimension(
                pressDelta: x - pressLocalX,
                pressDimension: pressWidth,
                pressOffset: pressOffsetX,
                minDimension: Self.minWidth,
                screenDimension: screenWidth)
            userWidth = w
            offsetX = ox

            let (h, oy) = updatedDimension(
                pressDelta: y - pressLocalY,
                pressDimension: pressHeight,
                pressOffset: pressOffsetY,
                minDimension: Self.minHeight,
                screenDimension: screenHeight)
            userHeight = h
            offsetY = oy
        }
    }

    package func endDrag() {
        guard isDragging else { return }
        isDragging = false
        if dragMode != .move && didResize {
            switch dragMode {
            case .resizeWidth:
                let finalW = userWidth ?? currentWidth
                userWidth = finalW
                onResize?(finalW, userHeight ?? currentHeight)
            case .resizeHeight:
                let finalH = userHeight ?? currentHeight
                userHeight = finalH
                onResize?(userWidth ?? currentWidth, finalH)
            case .resizeBoth:
                let finalW = userWidth ?? currentWidth
                let finalH = userHeight ?? currentHeight
                userWidth = finalW
                userHeight = finalH
                onResize?(finalW, finalH)
            case .move:
                break
            }
        }
        dragMode = .move
    }

    /// Trims the offset to the range that keeps the whole dialog on screen —
    /// the same range ``OverlayLayer/placed(maxWidth:maxHeight:)`` uses for
    /// display — so a hard overshoot past an edge doesn't leave a dead zone on
    /// the next grab. Idempotent, and never runs mid-computation of a drag (the
    /// drag recomputes from the press anchor each event).
    func clampOffset(dialogWidth: Int, dialogHeight: Int, screenWidth: Int, screenHeight: Int) {
        offsetX = clampAxis(offsetX, dialog: dialogWidth, screen: screenWidth)
        offsetY = clampAxis(offsetY, dialog: dialogHeight, screen: screenHeight)
    }

    /// Clamps a single axis so `centre + offset ∈ [0, screen − dialog]`, where
    /// `centre = (screen − dialog) / 2`.
    private func clampAxis(_ offset: Int, dialog: Int, screen: Int) -> Int {
        let span = max(0, screen - dialog)
        let centre = span / 2
        return min(max(offset, -centre), span - centre)
    }

    /// Recentres the dialog and clears user-requested size overrides.
    func reset() {
        isDragging = false
        didResize = false
        dragMode = .move
        offsetX = 0
        offsetY = 0
        userWidth = nil
        userHeight = nil
        isHovered = false
    }
}
