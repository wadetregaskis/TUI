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
                        screenWidth: context.environment.terminalWidth,
                        screenHeight: context.environment.overlayContentHeight)
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
final class _DialogDragHandler {
    enum DragMode: Sendable {
        case move
        case resizeWidth
        case resizeHeight
        case resizeBoth
    }

    private(set) var offsetX = 0
    private(set) var offsetY = 0

    private(set) var userWidth: Int?
    private(set) var userHeight: Int?

    var currentWidth = 0
    var currentHeight = 0
    var isHovered = false

    private var pressLocalX = 0
    private var pressLocalY = 0
    private var pressOffsetX = 0
    private var pressOffsetY = 0
    private var pressWidth = 0
    private var pressHeight = 0
    private var dragMode: DragMode = .move

    static let minWidth = 16
    static let minHeight = 4

    /// Records the press point (region-local) and the offset at that moment.
    func beginDrag(mode: DragMode, atX x: Int, y: Int) {
        pressLocalX = x
        pressLocalY = y
        pressOffsetX = offsetX
        pressOffsetY = offsetY
        pressWidth = userWidth ?? currentWidth
        pressHeight = userHeight ?? currentHeight
        dragMode = mode
    }

    /// Legacy convenience for move-only drags.
    func beginDrag(atX x: Int, y: Int) {
        beginDrag(mode: .move, atX: x, y: y)
    }

    /// Applies the drag: either translates the dialog or resizes one or both dimensions.
    /// When resizing, the opposite edges (top and left) remain anchored in place on screen.
    func updateDrag(toX x: Int, y: Int, screenWidth: Int = Int.max, screenHeight: Int = Int.max) {
        switch dragMode {
        case .move:
            offsetX = pressOffsetX + (x - pressLocalX)
            offsetY = pressOffsetY + (y - pressLocalY)
        case .resizeWidth:
            let minW = min(Self.minWidth, screenWidth)
            let targetW = min(max(minW, pressWidth + (x - pressLocalX)), screenWidth)
            userWidth = targetW
            let pressCentre = max(0, screenWidth - pressWidth) / 2
            let targetCentre = max(0, screenWidth - targetW) / 2
            offsetX = pressOffsetX + (pressCentre - targetCentre)
        case .resizeHeight:
            let minH = min(Self.minHeight, screenHeight)
            let targetH = min(max(minH, pressHeight + (y - pressLocalY)), screenHeight)
            userHeight = targetH
            let pressYCentre = max(0, screenHeight - pressHeight) / 2
            let targetYCentre = max(0, screenHeight - targetH) / 2
            offsetY = pressOffsetY + (pressYCentre - targetYCentre)
        case .resizeBoth:
            let minW = min(Self.minWidth, screenWidth)
            let targetW = min(max(minW, pressWidth + (x - pressLocalX)), screenWidth)
            userWidth = targetW
            let pressCentre = max(0, screenWidth - pressWidth) / 2
            let targetCentre = max(0, screenWidth - targetW) / 2
            offsetX = pressOffsetX + (pressCentre - targetCentre)

            let minH = min(Self.minHeight, screenHeight)
            let targetH = min(max(minH, pressHeight + (y - pressLocalY)), screenHeight)
            userHeight = targetH
            let pressYCentre = max(0, screenHeight - pressHeight) / 2
            let targetYCentre = max(0, screenHeight - targetH) / 2
            offsetY = pressOffsetY + (pressYCentre - targetYCentre)
        }
    }

    func endDrag() {}

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
        offsetX = 0
        offsetY = 0
        userWidth = nil
        userHeight = nil
        isHovered = false
    }
}
