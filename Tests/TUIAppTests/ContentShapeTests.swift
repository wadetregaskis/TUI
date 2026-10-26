//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentShapeTests.swift
//
//  `contentShape(_:eoFill:)` and `contentShape(_:_:eoFill:)` (refusal review
//  P3): a shape as a view's hit area — the cells it covers at least half of —
//  and as the preview a drag of it carries.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the actions under test did, in order.
private final class ShapeLog: @unchecked Sendable {
    var entries: [String] = []
}

/// What a layout read off its subviews: each one's `Int` tag.
@MainActor
private final class SubviewReadings {
    var tags: [Int?] = []
}

/// Records its subviews' tags, and draws nothing.
private struct ReadsSubviews: Layout {
    let readings: SubviewReadings

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        readings.tags = subviews.map { $0.containerValues.tag(for: Int.self) }
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {}
}

@MainActor
@Suite("Content shapes", .serialized)
struct ContentShapeTests {
    /// A left click at `(x, y)`: the press and its release.
    private func click(_ harness: InputChainHarness, _ x: Int, _ y: Int) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }

    /// A 9 × 5 block whose circle — 9 columns across and five rows of two
    /// units down — keeps its middle and the middle of each edge, and not its
    /// corners.
    private func disc(_ glyph: Character = "#") -> some View {
        GlyphFill(glyph).frame(width: 9, height: 5)
    }

    @Test("A tap around a circular content shape answers inside the circle, not in its corners")
    func tapInsideTheShape() {
        let log = ShapeLog()
        let harness = InputChainHarness()
        let view = { disc().contentShape(Circle()).onTapGesture { log.entries.append("tap") } }
        harness.frame(view())
        click(harness, 0, 0)
        click(harness, 8, 4)
        #expect(log.entries.isEmpty, "the corners are outside the circle")
        click(harness, 4, 2)
        click(harness, 8, 2)
        #expect(log.entries == ["tap", "tap"], "the middle and the middle of an edge are inside")
    }

    @Test("A control shaped by a content shape takes clicks only inside the shape")
    func controlCutToTheShape() {
        let log = ShapeLog()
        let harness = InputChainHarness()
        let view = {
            Button { log.entries.append("press") } label: { disc() }
                .buttonStyle(.plain)
                .contentShape(Circle())
        }
        harness.frame(view())
        click(harness, 0, 0)
        #expect(log.entries.isEmpty)
        click(harness, 4, 2)
        #expect(log.entries == ["press"])
    }

    @Test("A click outside the shape reaches what is behind the view")
    func outsideReachesBehind() {
        let log = ShapeLog()
        let harness = InputChainHarness()
        let view = {
            ZStack {
                GlyphFill(".").frame(width: 9, height: 5).onTapGesture { log.entries.append("behind") }
                disc().contentShape(Circle()).onTapGesture { log.entries.append("front") }
            }
        }
        harness.frame(view())
        click(harness, 0, 0)
        click(harness, 4, 2)
        #expect(log.entries == ["behind", "front"])
    }

    @Test("A rectangle keeps the whole frame, and the even-odd rule decides a ring's hole")
    func rectangleAndEvenOdd() {
        let log = ShapeLog()
        let harness = InputChainHarness()
        let ring = Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: 9, height: 10))
            path.addRect(CGRect(x: 3, y: 4, width: 3, height: 2))
        }
        let view = {
            VStack(spacing: 0) {
                disc().contentShape(Rectangle()).onTapGesture { log.entries.append("rectangle") }
                disc().contentShape(ring, eoFill: true).onTapGesture { log.entries.append("ring") }
            }
        }
        harness.frame(view())
        click(harness, 0, 0)
        click(harness, 4, 7)
        click(harness, 0, 5)
        #expect(log.entries == ["rectangle", "ring"], "the ring's hole, at (4, 7), takes nothing")
    }

    @Test("A content shape for the drag preview cuts the preview, and leaves where a drag starts alone")
    func dragPreviewCut() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 20, availableHeight: 8, environment: environment, tuiContext: tui)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()
        let view = disc().contentShape(.dragPreview, Circle()).draggable("disc")
        dispatcher.setRegions(renderToBuffer(view, context: context).hitTestRegions)
        // Grabbed by its corner, which the preview's shape leaves out: where a
        // drag starts is the whole frame still.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 3))
        guard let preview = tui.dragAndDropSession.active?.preview else {
            Issue.record("no drag began")
            return
        }
        let lines = preview.lines.map(\.stripped)
        #expect(Array(lines[0])[0] == " ", "the corner is cut away")
        #expect(Array(lines[2])[4] == "#", "the middle is kept")
    }

    @Test("A container reaches past a content shape to the members, tags, z-indices, priorities and guides inside it")
    func containersSeeThrough() {
        let context = makeRenderContext(width: 12, height: 4)
        func lines(_ view: some View) -> [String] { renderToBuffer(view, context: context).lines.map(\.stripped) }
        // A loop's members stay the row's: drawn whole, a loop stacks them.
        let row = lines(HStack(spacing: 1) { ForEach(0..<3) { Text("\($0)") } })
        #expect(lines(HStack(spacing: 1) { ForEach(0..<3) { Text("\($0)") }.contentShape(Rectangle()) }) == row)
        #expect(lines(HStack(spacing: 1) { ForEach(0..<3) { Text("\($0)") }.contentShape(Circle()) }) == row)
        // A z-index still orders the stack.
        let ordered = lines(ZStack { Text("A").zIndex(1).contentShape(Rectangle()); Text("B") })
        #expect(ordered.first?.hasPrefix("A") == true, "\(ordered)")
        // A guide still places the column's row.
        let guided = lines(
            VStack(alignment: .leading, spacing: 0) {
                Text("x").alignmentGuide(.leading) { _ in -2 }.contentShape(Rectangle())
                Text("abc")
            })
        #expect(guided.first?.hasPrefix("  x") == true, "\(guided)")
        // A priority still decides who keeps the row's width.
        let squeezed = lines(
            HStack(spacing: 0) {
                Text("aaaaaaaa")
                Text("bbbbbbbb").layoutPriority(1).contentShape(Rectangle())
            })
        #expect(squeezed.first?.contains("bbbbbbbb") == true, "\(squeezed)")
        // A tag is still the subview's.
        let readings = SubviewReadings()
        _ = renderToBuffer(
            ReadsSubviews(readings: readings) {
                Text("a").tag(5).contentShape(Circle())
                Text("b")
            }, context: context)
        #expect(readings.tags == [5, nil])
        // And a removal transition inside it plays from its own picture.
        let departing = departingPictureType(heldAs: _ContentShapeView<Text, Circle>.self)
        #expect(ObjectIdentifier(departing) == ObjectIdentifier(Text.self))
    }

    @Test("A content shape draws nothing and moves nothing")
    func drawsNothing() {
        let context = makeRenderContext(width: 12, height: 6)
        let plain = renderToBuffer(disc(), context: context)
        let shaped = renderToBuffer(disc().contentShape(Circle()), context: context)
        #expect(shaped.lines == plain.lines)
    }
}
