//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryPredictionTests.swift
//
//  The carried origin (design study A2 §10 steps 5 and 7, rungs 1 and 3): a
//  reader is told where the containers above it will place it before it is
//  drawn, so its owner finds it where it was told and draws nothing again. Each test's
//  oracle is the marker — the owner's finding — compared with the prediction
//  by the owner itself: no correction means they agreed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
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

    @Test("A container the prediction does not follow is a constant the residual carries after one correction")
    func residualAbsorbsAnUnconvertedOffset() {
        let told = Told()
        let harness = InputChainHarness()
        let view = { (label: String) in
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                UnconvertedContainer(rows: 2) { reader(told, in: .named("s")) }
            }
            .coordinateSpace(.named("s"))
        }
        harness.frame(view("a"))
        // Two rows into the container, which the stack said was at row 1.
        #expect(told.frames.last == CellRect(x: 0, y: 3, width: 4, height: 1))
        #expect(harness.geometryCorrections.named == 1)
        harness.frame(view("a"))
        // A row above it grows: the stack moves the container, the prediction
        // follows, and the container's shift is the same — no correction.
        harness.frame(view("a\nb"))
        #expect(told.frames.last == CellRect(x: 0, y: 4, width: 4, height: 1))
        #expect(harness.geometryCorrections.named == 1)
        #expect(harness.geometryCorrections.residual == 0)
    }

    /// A reader four cells wide and one row tall, in each of the composers rung
    /// 3 converts, and where SwiftUI's layout puts it there.
    private static func composers(_ told: Told) -> [(name: String, view: AnyView, frame: CellRect)] {
        [
            (
                "padding", AnyView(reader(told, in: .named("s")).padding(.leading, 2).padding(.top, 1)),
                CellRect(x: 2, y: 1, width: 4, height: 1)
            ),
            // Inside the wall, and the cell of padding a border keeps.
            ("border", AnyView(reader(told, in: .named("s")).border()), CellRect(x: 2, y: 1, width: 4, height: 1)),
            (
                "titled borderless container",
                AnyView(
                    ContainerView(title: "T", style: ContainerStyle(hasBorder: false)) {
                        reader(told, in: .named("s"))
                    }),
                CellRect(x: 1, y: 1, width: 4, height: 1)
            ),
            (
                "frame alignment",
                AnyView(reader(told, in: .named("s")).frame(width: 10, height: 3, alignment: .bottomTrailing)),
                CellRect(x: 6, y: 2, width: 4, height: 1)
            ),
            (
                "overlay",
                AnyView(Text(verbatim: "0123456789").overlay(alignment: .trailing) { reader(told, in: .named("s")) }),
                CellRect(x: 6, y: 0, width: 4, height: 1)
            ),
            (
                "background",
                AnyView(
                    Text(verbatim: "0123456789").background(alignment: .center) { reader(told, in: .named("s")) }),
                CellRect(x: 3, y: 0, width: 4, height: 1)
            ),
            (
                "ZStack",
                AnyView(
                    ZStack(alignment: .bottomTrailing) {
                        VStack(spacing: 0) {
                            Text(verbatim: "0123456789")
                            Text(verbatim: "x")
                            Text(verbatim: "y")
                        }
                        reader(told, in: .named("s"))
                    }),
                CellRect(x: 6, y: 2, width: 4, height: 1)
            ),
            ("offset", AnyView(reader(told, in: .named("s")).offset(x: 3, y: 2)), CellRect(x: 3, y: 2, width: 4, height: 1)),
            (
                "position", AnyView(reader(told, in: .named("s")).position(x: 10, y: 5)),
                CellRect(x: 8, y: 5, width: 4, height: 1)
            ),
        ]
    }

    @Test("Through the generic composers: padding, borders, frames, overlays, ZStack, offset, position")
    func composersPredict() {
        for index in Self.composers(Told()).indices {
            let told = Told()
            let shape = Self.composers(told)[index]
            let harness = InputChainHarness()
            harness.frame(VStack(alignment: .leading, spacing: 0) { shape.view }.coordinateSpace(.named("s")))
            #expect(told.frames == [shape.frame], "\(shape.name)")
            #expect(harness.geometryCorrections.total == 0, "\(shape.name)")
        }
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
        // A declaration carries one for its content while a reader may be
        // drawn in it — here, before anything has asked.
        harness.frame(
            VStack {
                Text("a")
                OriginProbe { seen = $0 }
            }
            .coordinateSpace(.named("s")))
        #expect(seen == true)
    }

    @Test("Reporters and pointers start no carried origin: only a reader does")
    func onlyReadersCarryAnOrigin() {
        let harness = InputChainHarness()
        var carried: [Bool] = []
        let page = VStack(alignment: .leading, spacing: 0) {
            OriginProbe { carried.append($0) }
            Text("reported")
                .onGeometryChange(for: Int.self) { $0.frame(in: .global).minY } action: { _, _ in }
            Text("dragged")
                .gesture(DragGesture(coordinateSpace: .named("box")).onEnded { _ in })
        }
        harness.frame(page)
        harness.frame(page)
        harness.frame(page)
        // An `onGeometryChange` asking `.global` and a drag located in a name
        // nothing declares are asked again at the end, or at event time:
        // nothing is told a prediction, so the root carries no origin.
        #expect(carried == [false, false, false])

        carried = []
        let told = Told()
        let withReader = VStack(alignment: .leading, spacing: 0) {
            OriginProbe { carried.append($0) }
            GeometryReader { proxy in
                // swiftlint:disable:next redundant_discardable_let
                let _ = told.frames.append(proxy.frame(in: .global))
                Text("R")
            }
            .frame(width: 4, height: 1)
        }
        harness.frame(withReader)
        harness.frame(withReader)
        // A reader does, from the walk after it first asks.
        #expect(carried.last == true)
    }

    @Test("A declaration whose only askers are gestures stops carrying an origin once it knows")
    func declarationForGesturesStopsCarrying() {
        let harness = InputChainHarness()
        var carried: [Bool] = []
        let page = VStack(alignment: .leading, spacing: 0) {
            OriginProbe { carried.append($0) }
            Text("dragged")
                .gesture(DragGesture(coordinateSpace: .named("box")).onEnded { _ in })
        }
        .coordinateSpace(.named("box"))
        harness.frame(page)
        harness.frame(page)
        harness.frame(page)
        // The first frame knows of no asker yet, and carries one in case a
        // reader is drawn; from then on, a drag converting at event time is
        // all there is.
        #expect(carried == [true, false, false])
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
