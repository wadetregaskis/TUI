//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryMarkerTests.swift
//
//  The geometry marker: a zero-area hit-test region that says where a view
//  began, carried up through every container to the view that owns the
//  question (design study A2, §10 step 1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Draws a block of `#` and stamps a geometry marker at its top-left, the way
/// a reader or an anchor site will.
private struct MarkerProbe: View, Renderable, Layoutable {
    var width = 2
    var height = 1

    var body: Never { fatalError("MarkerProbe renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(width: width, height: height, isWidthFlexible: false, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(
            lines: Array(repeating: String(repeating: "#", count: width), count: height))
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            buffer.hitTestRegions.append(.geometryMarker(dispatcher.geometryMarkerID(in: context)))
        }
        return buffer
    }
}

@MainActor
private struct Frames {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()

    func render<V: View>(_ view: V, width: Int = 30, height: Int = 12) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext)
        tuiContext.mouseEventDispatcher.beginRenderPass()
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer
    }
}

/// Every marker a buffer reports, in order, with where it sits.
private func markers(in buffer: FrameBuffer) -> [(id: HitTestRegion.HandlerID, x: Int, y: Int)] {
    var found: [(id: HitTestRegion.HandlerID, x: Int, y: Int)] = []
    buffer.forEachGeometryMarker { found.append(($0, $1, $2)) }
    return found
}

/// The one marker in `buffer`, as a position.
private func onlyMarker(in buffer: FrameBuffer) -> CellPoint? {
    let found = markers(in: buffer)
    guard found.count == 1, let marker = found.first else { return nil }
    return CellPoint(x: marker.x, y: marker.y)
}

/// Where the probe's first `#` was DRAWN in the buffer's own lines.
private func drawnProbe(in buffer: FrameBuffer) -> CellPoint? {
    for (row, line) in buffer.lines.enumerated() {
        let plain = Array(line.stripped)
        if let column = plain.firstIndex(of: "#") { return CellPoint(x: column, y: row) }
    }
    return nil
}

/// Places its subviews on a diagonal, three cells right and one row down each.
private struct DiagonalLayout: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 3 * subviews.count + 2, height: subviews.count)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            subview.place(at: (x: bounds.x + 3 * index, y: bounds.y + index), proposal: .unspecified)
        }
    }
}

@MainActor
@Suite("Geometry markers")
struct GeometryMarkerTests {

    // MARK: - The marker itself

    @Test("A marker id carries the geometry bit, and the same view stamps the same id every frame")
    func markerIDsAreInternedAndMarked() {
        let frames = Frames()
        let view = VStack(spacing: 0) {
            MarkerProbe()
            MarkerProbe()
        }
        let first = markers(in: frames.render(view))
        let second = markers(in: frames.render(view))
        #expect(first.count == 2)
        #expect(first.allSatisfy { $0.id.isGeometryMarker })
        #expect(first.map(\.id) == second.map(\.id))
        // Two probes are two markers, not one.
        let ids = Set(first.map(\.id))
        #expect(ids.count == 2)
    }

    @Test("A marker has no area, so it contains no point")
    func markerHasNoArea() {
        let marker = HitTestRegion.geometryMarker(
            HitTestRegion.HandlerID(HitTestRegion.HandlerID.geometryMarkerBit | 7))
        #expect(marker.isGeometryMarker)
        #expect(marker.width == 0 && marker.height == 0)
        #expect(!marker.contains(x: 0, y: 0))
        // Handler ids never carry the bit.
        #expect(!TUIContext().mouseEventDispatcher.register { _ in true }.isGeometryMarker)
    }

    @Test("A clip keeps a marker whole, at its unclipped origin")
    func clipKeepsMarker() {
        let marker = HitTestRegion.geometryMarker(
            HitTestRegion.HandlerID(HitTestRegion.HandlerID.geometryMarkerBit)
        ).shifted(byX: 4, y: -6)
        let clipped = marker.clipped(toColumns: 0..<3, rows: 0..<3)
        #expect(clipped?.offsetX == 4)
        #expect(clipped?.offsetY == -6)
    }

    // MARK: - Carried through containers

    @Test("A marker comes out of .padding where the content was drawn")
    func throughPadding() {
        let buffer = Frames().render(MarkerProbe().padding(2))
        #expect(onlyMarker(in: buffer) == CellPoint(x: 2, y: 2))
        #expect(onlyMarker(in: buffer) == drawnProbe(in: buffer))
    }

    @Test("A marker comes out of .border() inside the rule")
    func throughBorder() {
        let buffer = Frames().render(MarkerProbe().border())
        // Inside the rule, past the space the border pads with.
        #expect(onlyMarker(in: buffer) == CellPoint(x: 2, y: 1))
        #expect(onlyMarker(in: buffer) == drawnProbe(in: buffer))
    }

    @Test("A marker comes out of VStack, HStack and ZStack where the probe was drawn")
    func throughStacks() {
        let frames = Frames()
        let vertical = frames.render(
            VStack(alignment: .leading, spacing: 0) {
                Text("a")
                Text("b")
                MarkerProbe()
            })
        #expect(onlyMarker(in: vertical) == CellPoint(x: 0, y: 2))

        let horizontal = frames.render(
            HStack(spacing: 0) {
                Text("abc")
                MarkerProbe()
            })
        #expect(onlyMarker(in: horizontal) == CellPoint(x: 3, y: 0))

        let layered = frames.render(
            ZStack {
                Text("hello world")
                MarkerProbe(width: 1, height: 1)
            })
        #expect(onlyMarker(in: layered) == drawnProbe(in: layered))
        #expect(onlyMarker(in: layered)?.x == 5)
    }

    @Test("A marker comes out of a Grid and a custom Layout where the probe was drawn")
    func throughGridAndLayout() {
        let frames = Frames()
        let grid = frames.render(
            Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 0) {
                GridRow {
                    Text("abcd")
                    Text("e")
                }
                GridRow {
                    Text("f")
                    MarkerProbe()
                }
            })
        #expect(onlyMarker(in: grid) == CellPoint(x: 5, y: 1))
        #expect(onlyMarker(in: grid) == drawnProbe(in: grid))

        let layout = frames.render(
            DiagonalLayout {
                Text("x")
                Text("y")
                MarkerProbe(width: 1, height: 1)
            })
        #expect(onlyMarker(in: layout) == CellPoint(x: 6, y: 2))
        #expect(onlyMarker(in: layout) == drawnProbe(in: layout))
    }

    @Test("A marker comes out of an overlay and a background where the probe was drawn")
    func throughOverlayAndBackground() {
        let frames = Frames()
        let over = frames.render(Text("hello").overlay { MarkerProbe(width: 1, height: 1) })
        #expect(onlyMarker(in: over) == CellPoint(x: 2, y: 0))
        let under = frames.render(
            Text("     ").background(alignment: .trailing) { MarkerProbe(width: 1, height: 1) })
        #expect(onlyMarker(in: under) == CellPoint(x: 4, y: 0))
    }

    @Test("A marker moved by .offset or .position is found in the layer it floats in")
    func throughOffsetAndPosition() {
        let frames = Frames()
        let offset = frames.render(
            VStack(alignment: .leading, spacing: 0) {
                Text("top")
                MarkerProbe().offset(x: 3, y: 1)
            })
        // Drawn as a floated layer, so not in the lines; the marker is where
        // the layer puts the drawing.
        #expect(offset.overlays.count == 1)
        #expect(onlyMarker(in: offset) == CellPoint(x: 3, y: 2))

        let positioned = frames.render(MarkerProbe(width: 2, height: 2).position(x: 6, y: 4))
        // `.position` centres the view on the point.
        #expect(onlyMarker(in: positioned) == CellPoint(x: 5, y: 3))
    }

    @Test("A clipped container keeps a marker its clip cut away")
    func throughClipped() {
        let buffer = Frames().render(
            HStack(spacing: 0) {
                Text("abc")
                MarkerProbe()
            }
            .fixedSize()
            .frame(width: 2, alignment: .leading)
            .clipped())
        // The stack is laid out in the two cells the frame offers — the text
        // in both, the probe after it — and the frame cuts the probe away.
        #expect(buffer.width == 2)
        #expect(drawnProbe(in: buffer) == nil)
        #expect(onlyMarker(in: buffer) == CellPoint(x: 2, y: 0))

        // And the clamp itself, the trim every clipping container makes.
        var drawn = FrameBuffer(lines: ["abc", "def", "ghi"])
        drawn.hitTestRegions = [
            HitTestRegion.geometryMarker(HitTestRegion.HandlerID(HitTestRegion.HandlerID.geometryMarkerBit))
                .shifted(byX: 2, y: 2)
        ]
        #expect(onlyMarker(in: drawn.clamped(toWidth: 1, height: 1)) == CellPoint(x: 2, y: 2))
    }

    @Test("A scroll view scrolled past a marker carries its unclipped origin")
    func throughScrolledScrollView() {
        let frames = Frames()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<10, id: \.self) { Text("row \($0)") }
                MarkerProbe()
                ForEach(11..<30, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(binding)
        .frame(height: 5)
        _ = frames.render(view)
        position.scrollTo(y: 15)
        let buffer = frames.render(view)
        // The probe is content row 10, the viewport starts at row 15.
        #expect(buffer.lines.first?.stripped.hasPrefix("row 15") == true)
        #expect(onlyMarker(in: buffer) == CellPoint(x: 0, y: -5))
        #expect(drawnProbe(in: buffer) == nil)
    }

    @Test("A marker in a List row comes out where the row draws it, enabled or not")
    func throughListRows() {
        let frames = Frames()
        let list = List {
            Text("first")
            MarkerProbe()
        }
        let enabled = frames.render(list.frame(height: 6))
        #expect(onlyMarker(in: enabled) != nil)
        #expect(onlyMarker(in: enabled) == drawnProbe(in: enabled))

        let disabled = frames.render(list.disabled(true).frame(height: 6))
        #expect(onlyMarker(in: disabled) == drawnProbe(in: disabled))
    }

    @Test("allowsHitTesting(false) and hidden() keep the marker, and drop the targets")
    func inertViewsKeepMarkers() {
        let frames = Frames()
        let inert = frames.render(
            HStack(spacing: 0) {
                Button("Go") {}
                MarkerProbe()
            }
            .allowsHitTesting(false))
        #expect(inert.hitTestRegions.allSatisfy { $0.isGeometryMarker })
        #expect(onlyMarker(in: inert) == drawnProbe(in: inert))

        let hidden = frames.render(
            VStack(spacing: 0) {
                Text("seen")
                MarkerProbe().hidden()
            })
        // Centred under the wider row, as the probe would have been drawn.
        #expect(onlyMarker(in: hidden) == CellPoint(x: 1, y: 1))
    }

    @Test("A click on a marker's cell reaches the control drawn there")
    func clickPassesThroughMarker() {
        let frames = Frames()
        var taps = 0
        let view = Button("Go") { taps += 1 }
            .overlay { MarkerProbe(width: 1, height: 1) }
        let buffer = frames.render(view)
        guard let marker = onlyMarker(in: buffer) else {
            Issue.record("no marker")
            return
        }
        let dispatcher = frames.tuiContext.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        #expect(dispatcher.handlerIDs(at: marker.x, y: marker.y).allSatisfy { !$0.isGeometryMarker })
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: marker.x, y: marker.y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: marker.x, y: marker.y))
        #expect(taps == 1)
    }

    @Test("A presented surface's markers are not the page's; displaced drawing's are")
    func surfacesAreNotDescended() {
        let id = HitTestRegion.HandlerID(HitTestRegion.HandlerID.geometryMarkerBit | 1)
        var content = FrameBuffer(lines: ["x"])
        content.hitTestRegions = [.geometryMarker(id)]
        var page = FrameBuffer(lines: ["....", "...."])
        page.overlays = [OverlayLayer(offsetX: 2, offsetY: 1, content: content)]
        #expect(markers(in: page).isEmpty)
        page.overlays = [OverlayLayer(offsetX: 2, offsetY: 1, content: content, isOpaque: false)]
        #expect(markers(in: page).map { CellPoint(x: $0.x, y: $0.y) } == [CellPoint(x: 2, y: 1)])
    }
}
