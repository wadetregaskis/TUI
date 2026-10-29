//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarCustomizationGestures.swift
//
//  What the window keeps of the person dragging a customizable toolbar's
//  items in the bar itself while they customize it: the items the bars drew
//  to be dragged, and the drag under way.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The person's gestures on a customizable toolbar's items in the bar, while
/// its customization panel is open (the owner, 2026-10-28, afternoon list
/// #41): as on macOS, an item dragged sideways moves among the others of its
/// place, and one dragged off the bar is taken out of it.
///
/// Kept in ``WindowChromeState``, which the bars draw from and the run loop
/// keeps from frame to frame; the toolbar's module (TUIChrome) fills it and
/// reads it.
package final class ToolbarCustomizationGestures: @unchecked Sendable {
    /// An item the bars drew this walk as one to drag.
    package struct Draggable {
        /// The item.
        package let item: CustomizableToolbarDeclaration.ItemKey
        /// The cells it is drawn in, across: what the pointer crosses to move
        /// another item past it.
        package let width: Int
        /// Where its region's origin is on the screen, which its drag's events
        /// are measured from, and the screen's rows its bar takes: set once
        /// the window is stacked (``place(_:origin:barRows:)``).
        package var placement: (origin: (x: Int, y: Int), barRows: Range<Int>)?
    }

    /// A drag of an item in the bar, from the press to the release.
    package struct Drag {
        /// The item dragged.
        package let item: CustomizableToolbarDeclaration.ItemKey
        /// Where it was pressed, in its region's cells.
        package let press: (x: Int, y: Int)
        /// Where its region's origin was on the screen at the press: what the
        /// drag's events are measured from, wherever the item moves since.
        package let origin: (x: Int, y: Int)
        /// The screen's rows its bar took at the press.
        package let barRows: Range<Int>
        /// The cells across that the moves made so far took up, right being
        /// positive: the pointer moves an item a place for each neighbour's
        /// width it crosses, beyond these.
        package var spent = 0

        package init(
            item: CustomizableToolbarDeclaration.ItemKey, press: (x: Int, y: Int), origin: (x: Int, y: Int),
            barRows: Range<Int>
        ) {
            self.item = item
            self.press = press
            self.origin = origin
            self.barRows = barRows
        }
    }

    /// The items the bars drew this walk to be dragged, by their regions'
    /// handlers.
    private var draggables: [HitTestRegion.HandlerID: Draggable] = [:]

    /// The drag under way, or `nil`.
    package var drag: Drag?

    package init() {}

    /// Whether the bars drew any item to be dragged this walk: while no
    /// toolbar is customized, none.
    package var hasDraggables: Bool { !draggables.isEmpty }

    /// Records `item`, drawn `width` cells across, as the one to drag through
    /// the region of handler `id`.
    package func note(_ item: CustomizableToolbarDeclaration.ItemKey, width: Int, for id: HitTestRegion.HandlerID) {
        draggables[id] = Draggable(item: item, width: width)
    }

    /// Whether `id` is the handler of an item's region to drag.
    package func isDraggable(_ id: HitTestRegion.HandlerID) -> Bool {
        draggables[id] != nil
    }

    /// Records where on the screen the region of handler `id` is, and the
    /// rows of the bar it is in.
    package func place(_ id: HitTestRegion.HandlerID, origin: (x: Int, y: Int), barRows: Range<Int>) {
        draggables[id]?.placement = (origin, barRows)
    }

    /// Where `item` is on the screen, and its bar's rows, as this walk drew it.
    package func placement(of item: CustomizableToolbarDeclaration.ItemKey)
        -> (origin: (x: Int, y: Int), barRows: Range<Int>)?
    {
        draggables.values.first { $0.item == item && $0.placement != nil }?.placement
    }

    /// How many cells across the bars drew `item` this walk, or `nil` where
    /// they did not draw it to be dragged.
    package func width(of item: CustomizableToolbarDeclaration.ItemKey) -> Int? {
        draggables.values.first { $0.item == item }?.width
    }

    /// Forgets the items the last walk drew: called as each walk begins.
    func beginWalk() {
        draggables.removeAll(keepingCapacity: true)
    }
}
