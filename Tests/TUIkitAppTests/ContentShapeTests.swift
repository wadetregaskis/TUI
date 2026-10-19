//  🖥️ TUIkit — Terminal UI Kit for Swift
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

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What the actions under test did, in order.
private final class ShapeLog: @unchecked Sendable {
    var entries: [String] = []
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

    @Test("A content shape draws nothing and moves nothing")
    func drawsNothing() {
        let context = makeRenderContext(width: 12, height: 6)
        let plain = renderToBuffer(disc(), context: context)
        let shaped = renderToBuffer(disc().contentShape(Circle()), context: context)
        #expect(shaped.lines == plain.lines)
    }
}
