//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PointerStyleTests.swift
//
//  `pointerStyle(_:)`: the regions it files, and the shape the pointer is
//  given where it rests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What a styled view's action did, kept outside the memo's key.
private final class Tally: @unchecked Sendable {
    var taps = 0
}

/// A memoizable card with a style on it, equal by its title alone.
private struct StyledCard: View, @MainActor Equatable {
    let title: String
    let tally: Tally

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Text(title).pointerStyle(.link)
    }
}

private typealias Harness = PointerShapeHarness

@MainActor
@Suite("Pointer styles")
struct PointerStyleTests {

    @Test("SwiftUI's styles come down to the shapes a terminal names")
    func styles() {
        #expect(PointerStyle.default.shape == .arrow)
        #expect(PointerStyle.horizontalText.shape == .text)
        #expect(PointerStyle.link.shape == .link)
        #expect(PointerStyle.grabIdle.shape == .grab)
        #expect(PointerStyle.grabActive.shape == .grabbing)
        #expect(PointerStyle.rectSelection.shape == .crosshair)
        #expect(PointerStyle.columnResize(directions: .leading).shape == .columnResizeLeft)
        #expect(PointerStyle.columnResize(directions: .trailing).shape == .columnResizeRight)
        #expect(PointerStyle.columnResize(directions: .all) == .columnResize)
        #expect(PointerStyle.columnResize(directions: []) == .columnResize, "SwiftUI takes an empty set too")
        #expect(PointerStyle.rowResize(directions: .up).shape == .rowResizeUp)
        #expect(PointerStyle.rowResize(directions: .down).shape == .rowResizeDown)
        #expect(PointerStyle.rowResize(directions: .all) == .rowResize)
    }

    @Test("A frame's edge resizes outward away from it, inward toward it, and both ways along it")
    func frameResize() {
        #expect(PointerStyle.frameResize(position: .top, directions: .outward).shape == .resizeNorth)
        #expect(PointerStyle.frameResize(position: .top, directions: .inward).shape == .resizeSouth)
        #expect(PointerStyle.frameResize(position: .top).shape == .resizeNorthSouth)
        #expect(PointerStyle.frameResize(position: .trailing, directions: .outward).shape == .resizeEast)
        #expect(PointerStyle.frameResize(position: .bottomLeading, directions: .outward).shape == .resizeSouthWest)
        #expect(PointerStyle.frameResize(position: .bottomLeading, directions: .inward).shape == .resizeNorthEast)
        #expect(PointerStyle.frameResize(position: .topLeading).shape == .resizeNorthWestSouthEast)
        #expect(PointerStyle.frameResize(position: .topTrailing).shape == .resizeNorthEastSouthWest)
    }

    @Test("SwiftUI's raw values and set bits, as a SwiftUI build reports them")
    func frameResizeRawValues() {
        #expect(FrameResizePosition.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5, 6, 7])
        #expect(FrameResizePosition.topLeading.rawValue == 4 && FrameResizePosition.bottomTrailing.rawValue == 7)
        #expect(FrameResizeDirection.inward.rawValue == 0 && FrameResizeDirection.outward.rawValue == 1)
        #expect(FrameResizeDirection.Set.all.rawValue == 3 && FrameResizeDirection.Set.outward.rawValue == 2)
    }

    @Test("Where the terminal takes no shapes a style files nothing and asks for no motion")
    func inertWhereUnsupported() {
        let harness = Harness(shapes: false)
        let buffer = harness.frame(Text("styled").pointerStyle(.link))
        #expect(buffer.hitTestRegions.isEmpty)
        #expect(!harness.dispatcher.effectiveSupport(baseConfig: .standard).motion)
        #expect(harness.shape(atX: 1, y: 0) == nil)
    }

    @Test("A style gives the pointer its shape over the view and nowhere else, and asks for motion")
    func shapeOverTheView() {
        let harness = Harness()
        harness.frame(VStack(alignment: .leading, spacing: 0) {
            Text("styled").pointerStyle(.link)
            Text("plain")
        })
        #expect(harness.dispatcher.effectiveSupport(baseConfig: .standard).motion)
        #expect(harness.shape(atX: 1, y: 0) == .link)
        #expect(harness.shape(atX: 1, y: 1) == nil)
        #expect(harness.shape(atX: 30, y: 5) == nil)
    }

    @Test("Of nested styles the innermost wins, and one on a container reaches what has none of its own")
    func innermostWins() {
        let harness = Harness()
        harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("inner").pointerStyle(.link).pointerStyle(.grabIdle)
                Text("plain")
            }
            .pointerStyle(.rectSelection))
        #expect(harness.shape(atX: 1, y: 0) == .link)
        #expect(harness.shape(atX: 1, y: 1) == .crosshair)
    }

    @Test("nil sets no style, and inside .disabled(true) a style sets none")
    func nilAndDisabled() {
        let harness = Harness()
        harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("none").pointerStyle(nil)
                Text("disabled").pointerStyle(.link).disabled(true)
            }
            .pointerStyle(.rectSelection))
        #expect(harness.shape(atX: 1, y: 0) == .crosshair, "nil leaves the pointer to the style further out")
        #expect(harness.shape(atX: 1, y: 1) == .crosshair, "a disabled view's own style shows nothing")
        let alone = Harness()
        let buffer = alone.frame(Text("disabled").pointerStyle(.link).disabled(true))
        #expect(buffer.hitTestRegions.isEmpty)
    }

    @Test("A control drawn over a styled view covers its style")
    func controlInFrontCovers() {
        let harness = Harness()
        let buffer = harness.frame(
            Text("styled-styled-styled")
                .pointerStyle(.link)
                .overlay(alignment: .leading) { Button("B") {} })
        guard let button = buffer.hitTestRegions.first(where: { $0.focusID?.hasPrefix("button-") == true }) else {
            Issue.record("the Button drew no region: \(buffer.hitTestRegions)")
            return
        }
        #expect(harness.shape(atX: button.offsetX, y: button.offsetY) == nil)
        #expect(harness.shape(atX: 18, y: 0) == .link)
    }

    @Test("A style on a control shows over it, and the control still hears its clicks and lights")
    func styleOnAControl() {
        let harness = Harness()
        let tally = Tally()
        let view = Button("Go") { tally.taps += 1 }.pointerStyle(.link)
        let rest = harness.frame(view)
        guard let button = rest.hitTestRegions.first(where: { $0.focusID?.hasPrefix("button-") == true }) else {
            Issue.record("the Button drew no region: \(rest.hitTestRegions)")
            return
        }
        let (x, y) = (button.offsetX + 1, button.offsetY)
        #expect(harness.shape(atX: x, y: y) == .link)
        let lit = harness.frame(view)
        #expect(lit.lines != rest.lines, "the Button did not light under the pointer: the style took its hover")
        _ = harness.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = harness.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(tally.taps == 1, "the style's region took the click")
    }

    @Test("Crossing a style's edge asks for no frame: the shape is written without one")
    func crossingAsksForNoFrame() {
        let harness = Harness()
        harness.frame(VStack(alignment: .leading, spacing: 0) {
            Text("styled").pointerStyle(.link)
            Text("plain")
        })
        #expect(!harness.move(x: 1, y: 0))
        #expect(!harness.move(x: 1, y: 1))
        #expect(!harness.move(x: 1, y: 0))
        #expect(harness.dispatcher.pointerShapeUnderPointer() == .link)
    }

    @Test("A pointer that leaves the window, or has not moved, gets the terminal's own")
    func pointerLeft() {
        let harness = Harness()
        harness.frame(Text("styled").pointerStyle(.link))
        #expect(harness.dispatcher.pointerShapeUnderPointer() == nil, "nowhere known yet")
        #expect(harness.shape(atX: 1, y: 0) == .link)
        harness.dispatcher.pointerLeft()
        #expect(harness.dispatcher.pointerShapeUnderPointer() == nil)
    }

    @Test("A reshape under a resting pointer moves the shape with it")
    func reshapeUnderTheRestingPointer() {
        let harness = Harness()
        harness.frame(VStack(alignment: .leading, spacing: 0) {
            Text("styled").pointerStyle(.link)
            Text("plain")
        })
        #expect(harness.shape(atX: 1, y: 0) == .link)
        harness.frame(VStack(alignment: .leading, spacing: 0) {
            Text("plain")
            Text("styled").pointerStyle(.link)
        })
        #expect(harness.dispatcher.pointerShapeUnderPointer() == nil)
    }

    @Test("A memoized view served on a later frame still gives the pointer its shape")
    func servedMemoFilesItsStyle() {
        let harness = Harness()
        let tally = Tally()
        let page = VStack(alignment: .leading, spacing: 0) {
            Text("ahead").focusable()
            StyledCard(title: "card", tally: tally).equatable()
        }
        harness.frame(page)
        let hits = harness.cache.stats.hits
        harness.frame(page)
        #expect(harness.cache.stats.hits > hits, "no memo hit on the second frame")
        #expect(harness.shape(atX: 1, y: 1) == .link, "the served card filed no style")
        #expect(harness.dispatcher.effectiveSupport(baseConfig: .standard).motion, "the served card asked for no motion")
    }

    @Test("TUIkit's controls set their own shapes only where the terminal is trusted to put the pointer back")
    func controlShapesOnlyWhereAsked() {
        let view = VStack(alignment: .leading, spacing: 0) {
            Button("Go") {}
            Text("resize me").frame(width: 12, height: 3).userResizable()
        }
        let off = Harness()
        let drawn = off.frame(view)
        guard let go = off.cell(of: "Go", in: drawn) else {
            Issue.record("the Button was not drawn: \(drawn.lines.map(\.stripped))")
            return
        }
        #expect(off.shape(atX: go.x, y: go.y) == nil, "no control sets a shape until a host's reset is read")
        let on = Harness(controlShapes: true)
        on.frame(view)
        #expect(on.shape(atX: go.x, y: go.y) == .link, "a pointing hand over a button")
    }

    @Test("A user-resizable view's edges give a resize arrow along the axis each moves, its corner the diagonal")
    func resizableEdges() {
        let harness = Harness(controlShapes: true)
        let buffer = harness.frame(
            Text("resize me").frame(width: 12, height: 3).userResizable())
        let corner = buffer.hitTestRegions.last { $0.width == 2 && $0.height == 2 }
        let bottom = buffer.hitTestRegions.first { $0.height == 1 && $0.width > 2 }
        let right = buffer.hitTestRegions.first { $0.width == 1 && $0.height > 2 }
        guard let corner, let bottom, let right else {
            Issue.record("the resizable view drew no edges: \(buffer.hitTestRegions)")
            return
        }
        #expect(harness.shape(atX: bottom.offsetX, y: bottom.offsetY) == .rowResize)
        #expect(harness.shape(atX: right.offsetX, y: right.offsetY) == .columnResize)
        #expect(harness.shape(atX: corner.offsetX + 1, y: corner.offsetY + 1) == .resizeNorthWestSouthEast)
    }

    @Test("A style the app set beats a control's own shape, even one set further out")
    func appStyleBeatsTheControls() {
        let harness = Harness(controlShapes: true)
        let buffer = harness.frame(VStack { Button("Go") {} }.pointerStyle(.rectSelection))
        guard let go = harness.cell(of: "Go", in: buffer) else {
            Issue.record("the Button was not drawn")
            return
        }
        #expect(harness.shape(atX: go.x, y: go.y) == .crosshair)
    }
}
