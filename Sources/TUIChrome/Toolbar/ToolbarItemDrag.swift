//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarItemDrag.swift
//
//  A customizable toolbar's items dragged in the bar itself while the person
//  customizes it, as on macOS: sideways to move one among the others of its
//  place, off the bar to take it out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A customizable toolbar's item in the bar while its customization panel is
/// open (the owner, 2026-10-28, afternoon list #41): no control — its own
/// regions go, as an inert item's do, so a click does nothing — but a thing
/// to drag, under the open hand.
///
/// - Dragged sideways, it moves a place among the others of its place for
///   each neighbour's width the pointer crosses (the gap after it included),
///   each move worked out afresh from the order stored by the last, as the
///   panel's grip moves a row (``CustomizableToolbarDeclaration/neighbour``).
///   An item the bar does not draw is passed with the next one it does.
/// - Let go two or more rows off its bar, it is taken out of the bar, if the
///   person may take it out, and goes in a puff of smoke where it was let go
///   (``_ToolbarPoof``); one they may not stays where it is.
///
/// The bar's regions are under the panel's: the panel is a popover hanging
/// from the bar, and its backdrop, which closes it on a click outside, covers
/// the screen. So the window brings these regions to the front once it is
/// stacked (`_WindowChromeHost.frontingToolbarItemDrags(_:chrome:topRows:bottomRows:)`),
/// and notes where each is on the screen as it does.
enum _ToolbarItemDrag {
    /// Makes `buffer`, the bar's drawing of `key`, the item to drag while its
    /// toolbar is customized: its own regions removed, and one to drag it by
    /// over the whole of it, for an item the person may move or take out.
    @MainActor
    static func make(
        _ key: CustomizableToolbarDeclaration.ItemKey, of buffer: inout FrameBuffer, chrome: WindowChromeState,
        context: RenderContext
    ) {
        // The targets, not the geometry markers, as for an inert item.
        buffer.hitTestRegions.removeAll { !$0.isGeometryMarker }
        guard !context.isMeasuring, buffer.width > 0, buffer.height > 0,
            let dispatcher = context.environment.mouseEventDispatcher,
            let item = chrome.customizableToolbars.first(where: { $0.id == key.toolbarID })?
                .items.first(where: { $0.id == key.itemID }),
            item.isRemovable || item.canMoveEarlier || item.canMoveLater
        else { return }
        dispatcher.requestFeature(.drag, in: context)
        // Weak: the dispatcher holds this handler (see `Button`'s).
        let handlerID = dispatcher.register(in: context) { [weak chrome] event in
            guard let chrome else { return false }
            return handle(event, of: key, chrome: chrome)
        }
        dispatcher.fileControlPointerShape(PointerStyle.grabIdle.shape, for: handlerID, in: context)
        chrome.toolbarCustomization.note(key, width: buffer.width, for: handlerID)
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height, handlerID: handlerID))
    }

    /// Handles a left-button press, drag or release on the item `key`.
    @MainActor
    private static func handle(
        _ event: MouseEvent, of key: CustomizableToolbarDeclaration.ItemKey, chrome: WindowChromeState
    ) -> Bool {
        guard event.button == .left else { return false }
        let gestures = chrome.toolbarCustomization
        // A drag outlives the customization it began in when the panel closes
        // under it (Escape): the rest of it does nothing, so a release off the
        // bar takes nothing out.
        guard chrome.customizingToolbarID == key.toolbarID else {
            guard gestures.drag?.item == key else { return false }
            gestures.drag = nil
            return true
        }
        switch event.phase {
        case .pressed:
            guard let placement = gestures.placement(of: key) else { return false }
            gestures.drag = ToolbarCustomizationGestures.Drag(
                item: key, press: (event.x, event.y), origin: placement.origin, barRows: placement.barRows)
            return true
        case .dragged, .released:
            // Measured from the region the press was taken in: a captured
            // drag's events are, wherever the item has moved since.
            guard var drag = gestures.drag, drag.item == key else { return true }
            let toolbar = chrome.customizableToolbars.first { $0.id == key.toolbarID }
            let row = drag.origin.y + event.y
            let isOffBar = row >= drag.barRows.upperBound + 1 || row <= drag.barRows.lowerBound - 2
            if let toolbar, !isOffBar {
                reorder(&drag, by: event.x - drag.press.x, in: toolbar, gestures: gestures)
            }
            guard event.phase == .released else {
                gestures.drag = drag
                return true
            }
            gestures.drag = nil
            if isOffBar, let toolbar, toolbar.items.contains(where: { $0.id == key.itemID && $0.isRemovable }) {
                toolbar.setShown(key.itemID, false)
                gestures.poof = ToolbarCustomizationGestures.Poof(x: drag.origin.x + event.x, y: row)
            }
            return true
        default:
            return false
        }
    }

    /// Moves the dragged item a place for each neighbour the pointer has
    /// crossed since the moves `drag` has made — `distance` cells across from
    /// the press — each worked out from the order the last one stored.
    @MainActor
    private static func reorder(
        _ drag: inout ToolbarCustomizationGestures.Drag, by distance: Int, in toolbar: CustomizableToolbarDeclaration,
        gestures: ToolbarCustomizationGestures
    ) {
        let id = drag.item.itemID
        // Bounded by the items, each of which can be passed but once.
        for _ in toolbar.items.indices {
            let left = distance - drag.spent
            guard left != 0 else { return }
            let offset = left > 0 ? 1 : -1
            // The next neighbour the bar draws, and how many it does not draw
            // lie before it: those are passed with it.
            var passes = 0
            var cursor = id
            var width: Int?
            while passes < toolbar.items.count, let next = toolbar.neighbour(cursor, offset) {
                passes += 1
                width = gestures.width(of: .init(toolbarID: drag.item.toolbarID, itemID: next))
                if width != nil { break }
                cursor = next
            }
            // Its width, and the gap after it, which the item moves by.
            guard let width, abs(left) >= width + 1 else { return }
            for _ in 0..<passes { toolbar.move(id, offset) }
            drag.spent += offset * (width + 1)
        }
    }
}

@MainActor extension _WindowChromeHost {
    /// Brings the regions of the items drawn to be dragged (``_ToolbarItemDrag``)
    /// in front of every other region of `frame`, the stacked window, and notes
    /// where each is on the screen and the rows of the bar it is drawn in:
    /// the bar of the page's own that noted them, for an item a screen pushed
    /// onto a navigation stack put in the stack's bar
    /// (`ToolbarCustomizationGestures.noteBar(rows:of:)`); else the window's
    /// `topRows` or `bottomRows`, whichever it is in. Nothing while no toolbar
    /// is customized.
    func frontingToolbarItemDrags(
        _ frame: inout FrameBuffer, chrome: WindowChromeState, topRows: Range<Int>, bottomRows: Range<Int>
    ) {
        let gestures = chrome.toolbarCustomization
        guard gestures.hasDraggables else { return }
        var front: [HitTestRegion] = []
        frame.hitTestRegions.removeAll { region in
            guard gestures.isDraggable(region.handlerID) else { return false }
            front.append(region)
            return true
        }
        for region in front {
            // Judged against the bottom bar's rows, an item in a stack's bar
            // was off its bar where it was pressed: a click took it out.
            let top = region.localOriginY
            let barRows =
                gestures.ownBarRows(of: region.handlerID).map { ($0.lowerBound + top)..<($0.upperBound + top) }
                ?? (topRows.contains(region.offsetY) ? topRows : bottomRows)
            gestures.place(region.handlerID, origin: (region.localOriginX, top), barRows: barRows)
        }
        // The last region filed is the first hit.
        frame.hitTestRegions.append(contentsOf: front)
    }
}
