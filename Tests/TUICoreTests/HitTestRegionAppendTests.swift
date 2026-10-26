//  🖥️ TUI — A Terminal UI framework for Swift
//  HitTestRegionAppendTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// `appendShifted(_:byX:y:)` takes a different route for an empty receiver, a
/// zero shift and the general case; each must land the same regions, in the
/// same order, as the shifted copy it replaced.
@Suite("Hit-test region appending")
struct HitTestRegionAppendTests {
    private func region(_ x: Int, _ y: Int, id: UInt64, focusID: String? = nil) -> HitTestRegion {
        HitTestRegion(offsetX: x, offsetY: y, width: 2, height: 1, handlerID: .init(id), focusID: focusID)
    }

    private var children: [HitTestRegion] { [region(0, 0, id: 1, focusID: "a"), region(3, 1, id: 2)] }

    @Test("Each route lands the regions shifted, after the receiver's, in order", arguments: [
        (0, 0), (2, 0), (0, 5), (-1, 3),
    ])
    func everyRoute(dx: Int, dy: Int) {
        let expected = children.map { $0.shifted(byX: dx, y: dy) }

        var empty: [HitTestRegion] = []
        empty.appendShifted(children, byX: dx, y: dy)
        #expect(empty == expected)

        let first = region(9, 9, id: 99)
        var occupied = [first]
        occupied.appendShifted(children, byX: dx, y: dy)
        #expect(occupied == [first] + expected)

        // Twice over a grown receiver: the hand-grown capacity is not lost.
        occupied.appendShifted(children, byX: dx, y: dy)
        #expect(occupied == [first] + expected + expected)
    }

    @Test("An adopted array is not changed by later appends to the adopter")
    func adoptionCopiesOnWrite() {
        let source = children
        var adopter: [HitTestRegion] = []
        adopter.appendShifted(source, byX: 0, y: 0)
        adopter.appendShifted(source, byX: 1, y: 1)
        #expect(source == children)
        #expect(adopter.count == 4)
    }

    @Test("FrameBuffer carries a child's regions through appendHitTestRegions")
    func frameBuffer() {
        var child = FrameBuffer(lines: ["ab"])
        child.hitTestRegions = children
        var parent = FrameBuffer()
        parent.appendHitTestRegions(of: child, shiftedByX: 4, y: 2)
        parent.appendHitTestRegions(of: FrameBuffer(), shiftedByX: 1, y: 1)
        #expect(parent.hitTestRegions == child.shiftedHitTestRegions(byX: 4, y: 2))
    }
}
