//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollAnchorAlignmentAcrossTests.swift
//
//  `ScrollAnchorRole.alignment` across: content NARROWER than a scroll view
//  that scrolls horizontally sits at the anchor's `x` of the room, as SwiftUI's
//  does (measured on macOS 15, decisions D2S B-D2S-1) — and a view that
//  scrolls both ways places each axis by its own coordinate, where SwiftUI
//  draws the content past its bounds.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("ScrollAnchorRole.alignment, across")
struct ScrollAnchorAlignmentAcrossTests {
    private func render<V: View>(_ view: V, tui: TUIContext = TUIContext()) -> FrameBuffer {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 4, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// The column the first card starts at on the first line.
    private func firstCardColumn(_ buffer: FrameBuffer) -> Int? {
        let line = buffer.lines.first?.stripped ?? ""
        return line.range(of: "card0").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    /// Three six-column cards: eighteen columns of a thirty-column view.
    private var cards: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { Text("card\($0)").frame(width: 6, alignment: .leading) }
        }
    }

    @Test(
        "Narrow content sits at the anchor's x of the room",
        arguments: [(UnitPoint?.none, 0), (.leading, 0), (.center, 6), (.trailing, 12), (.topTrailing, 12)])
    func placedByX(anchor: UnitPoint?, column: Int) {
        let view = ScrollView(.horizontal) { cards }.defaultScrollAnchor(anchor, for: .alignment)
        #expect(firstCardColumn(render(view)) == column)
    }

    @Test("The unlabelled .bottom states the role too, and its x of 0.5 centres")
    func unlabelledCentres() {
        let view = ScrollView(.horizontal) { cards }.defaultScrollAnchor(.bottom)
        #expect(firstCardColumn(render(view)) == 6)
    }

    @Test("Content wider than the view, or filling it, is not moved")
    func noRoom() {
        let wide = ScrollView(.horizontal) {
            HStack(spacing: 0) { ForEach(0..<8, id: \.self) { Text("card\($0)").frame(width: 6, alignment: .leading) } }
        }
        .defaultScrollAnchor(.trailing, for: .alignment)
        #expect(firstCardColumn(render(wide)) == 0)
        let filling = ScrollView(.horizontal) { Text("card0").frame(maxWidth: .infinity, alignment: .leading) }
            .defaultScrollAnchor(.trailing, for: .alignment)
        #expect(firstCardColumn(render(filling)) == 0)
    }

    @Test("A control in placed content is clickable where it is drawn")
    func hitRegionsMoveAcross() {
        let view = ScrollView(.horizontal) { Button("press") {} }.defaultScrollAnchor(.trailing, for: .alignment)
        let buffer = render(view)
        let line = buffer.lines.first?.stripped ?? ""
        let column = line.range(of: "press").map { line.distance(from: line.startIndex, to: $0.lowerBound) } ?? -1
        #expect(column > 0, "\(buffer.lines.map(\.stripped))")
        let regions = buffer.hitTestRegions.filter { $0.width < 30 }
        #expect(regions.contains { $0.offsetX <= column && column < $0.offsetX + $0.width }, "\(buffer.hitTestRegions)")
        #expect(!regions.contains { $0.offsetX == 0 }, "nothing left where it would be unplaced")
    }

    @Test("A view that scrolls both ways places each axis by its own coordinate, inside its bounds")
    func bothAxes() {
        let view = ScrollView([.horizontal, .vertical]) { cards }
            .defaultScrollAnchor(.bottomTrailing, for: .alignment)
        let buffer = render(view)
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.last?.contains("card2") == true, "the content is at the bottom: \(lines)")
        #expect(lines.first?.contains("card") == false, "\(lines)")
        let last = lines.last ?? ""
        let column = last.range(of: "card0").map { last.distance(from: last.startIndex, to: $0.lowerBound) }
        #expect(column == 12, "and against the trailing edge, inside it: \(lines)")
        #expect(lines.allSatisfy { $0.count <= 30 })
    }

    @Test("The geometry reports the room before the content as a leading inset")
    func geometryReportsALeadingInset() {
        var reported: ScrollGeometry?
        let view = ScrollView(.horizontal) { cards }
            .defaultScrollAnchor(.trailing, for: .alignment)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { reported = $1 })
        _ = render(view)
        #expect(reported?.contentInsets.leading == 12)
        #expect(reported?.contentOffset.x == -12)
    }
}
