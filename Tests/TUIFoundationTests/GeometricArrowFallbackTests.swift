//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometricArrowFallbackTests.swift
//
//  When the geometric arrows find nothing that way, the Tab-order neighbour
//  decides: one with a frame lies some other way, and the focus stays (no
//  wrap); one with none could lie anywhere, and the arrow goes on to it in
//  Tab order. Driven on the focus manager with frames stated outright, since
//  a control in the ring with no frame is rare in a drawn view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Geometric arrow fallback")
struct GeometricArrowFallbackTests {
    /// A manager in geometric mode holding `a`, `b` and `c` in that Tab order,
    /// `a` focused.
    private func manager() -> FocusManager {
        let manager = FocusManager()
        manager.arrowFocus = .geometric
        for id in ["a", "b", "c"] { manager.register(MockFocusable(id: id)) }
        #expect(manager.currentFocusedID == "a")
        return manager
    }

    /// A one-row frame four columns wide at (`x`, `y`) for `id`.
    private func frame(_ id: String, x: Int, y: Int) -> HitTestRegion {
        HitTestRegion(offsetX: x, offsetY: y, width: 4, height: 1, handlerID: .init(1), focusID: id)
    }

    @Test("Nothing below, and the next in Tab order beside: Down leaves the focus where it is")
    func stopsWhereTheNeighbourLiesElsewhere() {
        let manager = manager()
        manager.laidOutRegions = [frame("a", x: 0, y: 0), frame("b", x: 10, y: 0), frame("c", x: 20, y: 0)]
        #expect(manager.moveFocus(byArrow: .down))
        #expect(manager.currentFocusedID == "a")
        #expect(manager.moveFocus(byArrow: .right))
        #expect(manager.currentFocusedID == "b")
    }

    @Test("Nothing below, and the next in Tab order has no frame: Down goes on to it")
    func goesOnToAnUnplacedNeighbour() {
        let manager = manager()
        manager.laidOutRegions = [frame("a", x: 0, y: 0), frame("c", x: 20, y: 0)]
        #expect(manager.moveFocus(byArrow: .down))
        #expect(manager.currentFocusedID == "b")
        // And from `b`, itself unplaced, Tab order throughout.
        #expect(manager.moveFocus(byArrow: .down))
        #expect(manager.currentFocusedID == "c")
    }

    @Test("A frame that is only a scroll view's corners counts as a frame")
    func cornersAreAFrame() {
        let manager = manager()
        var regions = [frame("a", x: 0, y: 0)]
        regions.appendFocusFrameCorners(of: [frame("b", x: 0, y: 12)], clippedTo: 0..<80, rows: 0..<10)
        #expect(regions.count == 3)
        manager.laidOutRegions = regions
        #expect(manager.moveFocus(byArrow: .down))
        #expect(manager.currentFocusedID == "b")
    }
}
