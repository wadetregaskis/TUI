//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryPredictionTests.swift
//
//  The carried origin (design study A2 §10 step 5, rung 1): a reader is told
//  where the containers above it will place it before it is drawn, so its
//  owner finds it where it was told and draws nothing again. Each test's
//  oracle is the marker — the owner's finding — compared with the prediction
//  by the owner itself: no correction means they agreed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Where a reader's closure was told it was, each time it ran.
@MainActor
private final class Told {
    var frames: [CellRect] = []
}

/// A reader `width` × `height` noting `frame(in: space)` each time its content
/// is built.
@MainActor
private func reader(_ told: Told, in space: NamedCoordinateSpace, width: Int = 4, height: Int = 1) -> some View {
    GeometryReader { proxy in
        // swiftlint:disable:next redundant_discardable_let
        let _ = told.frames.append(proxy.frame(in: space))
        Text("R")
    }
    .frame(width: width, height: height)
}

/// Places subview `i` three cells right and one row down per step — a
/// `Layout` an app might write.
private struct Diagonal: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 20, height: 5)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(at: (x: bounds.x + 3 * index, y: bounds.y + index), proposal: .unspecified)
        }
    }
}

@MainActor
@Suite("Geometry prediction")
struct GeometryPredictionTests {

    @Test("Through a Grid: the cell's seat in its row's box")
    func grid() {
        let told = Told()
        let harness = InputChainHarness()
        harness.frame(
            Grid(horizontalSpacing: 1, verticalSpacing: 0) {
                GridRow {
                    Text("a")
                    Text("bbb")
                }
                GridRow {
                    Text("cc")
                    reader(told, in: .named("s"))
                }
            }
            .coordinateSpace(.named("s")))
        #expect(told.frames == [CellRect(x: 3, y: 1, width: 4, height: 1)])
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("Through a custom Layout: where placeSubviews put it")
    func customLayout() {
        let told = Told()
        let harness = InputChainHarness()
        harness.frame(
            Diagonal {
                Text("ab")
                Text("c")
                reader(told, in: .named("s"))
            }
            .coordinateSpace(.named("s")))
        #expect(told.frames == [CellRect(x: 6, y: 2, width: 4, height: 1)])
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("Through a lazy stack drawing whole rows outside a scroll view")
    func lazyWindow() {
        let told = Told()
        let harness = InputChainHarness()
        harness.frame(
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(0..<4, id: \.self) { index in
                    if index == 2 {
                        reader(told, in: .named("s"))
                    } else {
                        Text("row \(index)")
                    }
                }
            }
            .coordinateSpace(.named("s")))
        #expect(told.frames == [CellRect(x: 0, y: 4, width: 4, height: 1)])
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test(
        "Through a lazy stack's band in a scroll view, scrolled: rows placed in the list's space",
        arguments: [40, 400])
    func lazyBandInAScrollView(rows: Int) {
        // Forty uniform rows take the uniform window; four hundred the
        // anchored one, whose places past its threshold are an estimate the
        // prediction shares (the owner's answer 8).
        let told = Told()
        let harness = InputChainHarness()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let target = rows - 10
        let page = {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { index in
                        Text("row \(index)")
                            .background {
                                if index == target { reader(told, in: .named("list"), width: 6) }
                            }
                    }
                }
                .coordinateSpace(.named("list"))
            }
            .scrollPosition(binding)
            .frame(height: 6)
        }
        harness.frame(page())
        position.scrollTo(y: target - 2)
        harness.frame(page())
        let before = harness.geometryCorrections
        position.scrollTo(y: target - 3)
        harness.frame(page())
        // The row came into the band on the second frame and moved through
        // the viewport on the third, and it never moved in the list's space.
        #expect(told.frames.last?.y == target)
        #expect(harness.geometryCorrections.named == before.named)
        #expect(harness.geometryCorrections.named == 0)
    }

    @Test("An unconverted ZStack's centring is a constant the residual carries after one correction")
    func residualAbsorbsAZStack() {
        let told = Told()
        let harness = InputChainHarness()
        let view = { (label: String) in
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                ZStack {
                    Text("wide text")
                    reader(told, in: .named("s"))
                }
            }
            .coordinateSpace(.named("s"))
        }
        harness.frame(view("a"))
        // Centred in nine cells: two in. The stack above it said row 1.
        #expect(told.frames.last == CellRect(x: 2, y: 1, width: 4, height: 1))
        #expect(harness.geometryCorrections.named == 1)
        harness.frame(view("a"))
        // A row above it grows: the stack moves the ZStack, the prediction
        // follows, and the ZStack's centring is the same — no correction.
        harness.frame(view("a\nb"))
        #expect(told.frames.last == CellRect(x: 2, y: 2, width: 4, height: 1))
        #expect(harness.geometryCorrections.named == 1)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("No reader above, no carried origin: a tree that asks nothing carries nothing")
    func inactiveWithoutReaders() {
        let harness = InputChainHarness()
        var seen: Bool?
        harness.frame(
            VStack {
                Text("a")
                OriginProbe { seen = $0 }
            })
        #expect(seen == false)
        // A declaration carries one for its content, always.
        harness.frame(
            VStack {
                Text("a")
                OriginProbe { seen = $0 }
            }
            .coordinateSpace(.named("s")))
        #expect(seen == true)
    }

    @Test("RenderContext's stride stays 104 bytes with the carried origin in it")
    func renderContextStride() {
        // The two halves of the carried origin sit in padding that was already
        // there (`RenderContext.geometryOriginX`): an `Int` more measured
        // +2.4% on `anyview`, the stride moving to 112.
        #expect(MemoryLayout<RenderContext>.size == 104)
        #expect(MemoryLayout<RenderContext>.stride == 104)
    }
}

/// Reports whether its context carries a geometry origin.
private struct OriginProbe: View, Renderable {
    let report: (Bool) -> Void
    var body: Never { fatalError("OriginProbe renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { report(context.carriesGeometryOrigin) }
        return FrameBuffer(text: "p")
    }
}
