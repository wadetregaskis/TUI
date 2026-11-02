//  🖥️ TUI — A Terminal UI framework for Swift
//  PixelMouseLocationTests.swift
//
//  What a report within a cell reaches, and what it doesn't: a gesture's and a
//  hover's location carry the fraction, a view's hit test and a control's drag go
//  by the whole cell, and only a view that reads a location asks for any of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private final class Log: @unchecked Sendable {
    var locations: [CGPoint] = []
    var phases: [HoverPhase] = []
    var events: [MouseEvent] = []
}

private func report(
    _ phase: MousePhase, _ x: Double, _ y: Double, button: MouseButton = .left
) -> MouseEvent {
    MouseEvent(
        button: button, phase: phase, x: Int(x), y: Int(y),
        subcellX: x - x.rounded(.down), subcellY: y - y.rounded(.down))
}

@MainActor
@Suite("Locations within a cell")
struct PixelMouseLocationTests {
    private func padded(_ content: some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("top")
            HStack(spacing: 0) {
                Text("ab")
                content
            }
        }
    }

    @Test("A drag's value carries the fraction, in the view's own cells and the terminal's")
    func dragValue() {
        let log = Log()
        let global = Log()
        let harness = InputChainHarness()
        let view = padded(
            Text("drag me here")
                .gesture(DragGesture(minimumDistance: 0).onChanged { log.locations.append($0.location) })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { global.locations.append($0.location) }))
        harness.frame(view)
        harness.mouse(report(.pressed, 3.25, 1.5))
        harness.mouse(report(.dragged, 3.75, 1.5))
        harness.mouse(report(.dragged, 5.5, 1.25))
        #expect(log.locations == [CGPoint(x: 1.25, y: 0.5), CGPoint(x: 1.75, y: 0.5), CGPoint(x: 3.5, y: 0.25)])
        #expect(global.locations.last == CGPoint(x: 5.5, y: 1.25))
    }

    @Test("A drag's distance is the real one, and a translation is fractional with it")
    func dragDistance() {
        var values: [DragGesture.Value] = []
        let harness = InputChainHarness()
        let view = padded(Text("drag me here").gesture(DragGesture().onChanged { values.append($0) }))
        harness.frame(view)
        harness.mouse(report(.pressed, 3.9, 1))
        harness.mouse(report(.dragged, 4.1, 1))
        #expect(values.isEmpty, "into the next cell, but only a fifth of one")
        harness.mouse(report(.dragged, 4.9, 1))
        #expect(abs((values.last?.translation.width ?? 0) - 1) < 0.0001)
    }

    @Test("A tap's location carries the fraction, and its strays go by the whole cell")
    func tapLocation() {
        let log = Log()
        let harness = InputChainHarness()
        let view = padded(Text("tap me here").onTapGesture { log.locations.append($0) })
        harness.frame(view)
        harness.mouse(report(.pressed, 3.25, 1.5))
        harness.mouse(report(.dragged, 3.5, 1.5))
        harness.mouse(report(.released, 3.5, 1.5))
        #expect(log.locations == [CGPoint(x: 1.5, y: 0.5)])
    }

    @Test("onContinuousHover hears moves within a cell, with the fraction")
    func hover() {
        let log = Log()
        let harness = InputChainHarness()
        harness.frame(padded(Text("hover").onContinuousHover { log.phases.append($0) }))
        harness.mouse(report(.moved, 3.25, 1, button: .none))
        harness.mouse(report(.moved, 3.75, 1, button: .none))
        #expect(log.phases == [.active(CGPoint(x: 1.25, y: 0)), .active(CGPoint(x: 1.75, y: 0))])
    }

    @Test("A control's own handler hears only moves and drags to another cell, as ever")
    func controlsHearWholeCells() {
        let log = Log()
        let harness = InputChainHarness()
        let view = padded(
            Text("handler")
                .onMouseEvent { event in
                    log.events.append(event)
                    return true
                })
        harness.frame(view)
        harness.mouse(report(.pressed, 3.25, 1))
        harness.mouse(report(.dragged, 3.5, 1))
        harness.mouse(report(.dragged, 3.75, 1))
        harness.mouse(report(.dragged, 4.25, 1))
        harness.mouse(report(.released, 4.5, 1))
        #expect(log.events.map(\.phase) == [.pressed, .dragged, .released], "the press's wobble within its cell is not a drag")
        #expect(log.events.first?.preciseX == 1.25, "and what it does hear says where, local to its region")
    }

    @Test("Only a view that reads a location asks for it")
    func demand() {
        func asks(_ view: some View) -> Bool {
            let harness = InputChainHarness()
            harness.frame(view)
            return harness.tui.mouseEventDispatcher.effectiveSupport(baseConfig: .standard).subCellLocations
        }
        #expect(asks(Text("x").onContinuousHover { _ in }))
        #expect(asks(Text("x").gesture(DragGesture())))
        #expect(asks(Text("x").gesture(SpatialTapGesture())))
        #expect(asks(Text("x").onTapGesture { (_: CGPoint) in }))
        #expect(asks(Text("x").gesture(DragGesture().simultaneously(with: TapGesture()))), "as part of another")
        #expect(!asks(Text("x")))
        #expect(!asks(Text("x").onHover { _ in }))
        #expect(!asks(Text("x").onTapGesture {}))
        #expect(!asks(Text("x").gesture(LongPressGesture())))
        #expect(!asks(Text("x").onMouseEvent { _ in false }))
    }

    @Test("The cell a location falls in rounds down, not toward zero, and survives what is not a number")
    func cellOfLocation() {
        #expect(CellPoint(CGPoint(x: 2.75, y: 0.25)) == CellPoint(x: 2, y: 0))
        #expect(CellPoint(CGPoint(x: -0.25, y: -1)) == CellPoint(x: -1, y: -1), "left of the view, not its first cell")
        #expect(CellPoint(CGPoint(x: Double.nan, y: Double.infinity)) == CellPoint(x: 0, y: 0))
        #expect(CellSize(CGSize(width: 2.5, height: -2.4)) == CellSize(width: 3, height: -2))
    }

    @Test("A drag's translation and location feed offset and position as SwiftUI's do")
    func portedModifiers() {
        let harness = InputChainHarness()
        let moved = { (offset: CGSize) in
            harness.frame(Text("x").offset(offset)).lines
        }
        #expect(moved(CGSize(width: 2.4, height: 0)) == moved(CGSize(width: 2, height: 0)), "to the nearest cell")
        _ = Text("x").offset(x: CGFloat(1.5), y: CGFloat(2)).position(CGPoint(x: 1.5, y: 2))
    }
}
