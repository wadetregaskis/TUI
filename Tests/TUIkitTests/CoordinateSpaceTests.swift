//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CoordinateSpaceTests.swift
//
//  Named coordinate spaces, `.scrollView`, an exact `.global`, and the
//  correction that keeps what a reader draws right on the frame it moves
//  (design study A2, §10 step 3). The SwiftUI readings are probes M1–M3 of
//  the W05 brief, re-measured off the origin on macOS 15 (D5G): an unknown
//  name answers in the GLOBAL space, and `.scrollView` is the viewport.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What a reader's closure saw, the last time it ran: the drawing that
/// reached the screen.
@MainActor
private final class Seen {
    var frame: CellRect?
    var bounds: CellRect??
    var builds = 0
    var changes: [String] = []
}

/// A reader `width` × `height`, recording `frame(in: space)` and
/// `bounds(of: named)` each time its content is built.
@MainActor
private func reader(
    _ seen: Seen, in space: some CoordinateSpaceProtocol, bounds named: NamedCoordinateSpace? = nil,
    width: Int = 10, height: Int = 2
) -> some View {
    GeometryReader { proxy in
        // swiftlint:disable:next redundant_discardable_let
        let _ = record(proxy, seen, space.coordinateSpace, named)
        Text("R")
    }
    .frame(width: width, height: height)
}

@MainActor
private func record(_ proxy: GeometryProxy, _ seen: Seen, _ space: CoordinateSpace, _ named: NamedCoordinateSpace?) {
    seen.builds += 1
    seen.frame = proxy.frame(in: space)
    if let named { seen.bounds = .some(proxy.bounds(of: named)) }
}

@MainActor
@Suite("Coordinate spaces")
struct CoordinateSpaceTests {

    // MARK: - Probe M1: a named space

    @Test("frame(in: .named) and bounds(of:) answer in the named view's space, as probe M1 measured")
    func namedSpace() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            Text("b")
            Text("c")
            reader(seen, in: .named("s"), bounds: .named("s")).padding(.leading, 4)
        }
        .coordinateSpace(.named("s"))
        harness.frame(view)
        #expect(seen.frame == CellRect(x: 4, y: 3, width: 10, height: 2))
        // The named view's rectangle, from the reader's origin: SwiftUI's
        // (-4, -30, 54, 50) for a reader at (4, 30).
        #expect(seen.bounds == .some(CellRect(x: -4, y: -3, width: 14, height: 5)))
    }

    // MARK: - Probe M2: an unknown name

    @Test("An unknown name answers in the global space and bounds(of:) is nil")
    func unknownName() {
        let seen = Seen()
        let harness = InputChainHarness()
        harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("a")
                reader(seen, in: .named("nope"), bounds: .named("nope")).padding(.leading, 3)
            })
        // Measured off the origin (the W05 brief's M2 had the reader AT it):
        // SwiftUI gives the global frame, not the local one.
        #expect(seen.frame == CellRect(x: 3, y: 1, width: 10, height: 2))
        #expect(seen.bounds == .some(nil))
    }

    // MARK: - .global

    @Test("frame(in: .global) is exact: the screen's cells")
    func globalIsExact() {
        let seen = Seen()
        let harness = InputChainHarness()
        harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("one")
                HStack(spacing: 0) {
                    Text("two:")
                    reader(seen, in: .global).border()
                }
            }
            .padding(1))
        // Padding 1, the second row, past "two:" and the border's rule and
        // the space it pads with.
        #expect(seen.frame == CellRect(x: 1 + 4 + 2, y: 1 + 1 + 1, width: 10, height: 2))
    }

    // MARK: - Probe M3: .scrollView

    @Test("frame(in: .scrollView) is the viewport's: a reader forty rows down, scrolled forty, is at the top")
    func scrollViewSpaceIsTheViewport() {
        let seen = Seen()
        let wrongAxis = Seen()
        let harness = InputChainHarness()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<4, id: \.self) { Text("row \($0)") }
                    ZStack {
                        reader(seen, in: .scrollView(axis: .vertical), bounds: .scrollView)
                        reader(wrongAxis, in: .scrollView(axis: .horizontal), bounds: .scrollView(axis: .horizontal))
                    }
                    ForEach(6..<30, id: \.self) { Text("row \($0)") }
                }
            }
            .scrollPosition(binding)
            .frame(height: 6)
            .padding(.top, 2)
        }
        harness.frame(view())
        // At offset 0 the reader is four rows down the viewport.
        #expect(seen.frame?.y == 4)
        position.scrollTo(y: 4)
        harness.frame(view())
        #expect(seen.frame?.y == 0)
        // The viewport — the content window, less the scrollbar's column —
        // from the reader's origin.
        #expect(seen.bounds == .some(CellRect(x: 0, y: 0, width: 39, height: 6)))
        // No scroll view scrolls sideways: the global space, and no bounds.
        #expect(wrongAxis.frame?.y == 2)
        #expect(wrongAxis.bounds == .some(nil))
    }

    @Test(".scrollView is the innermost scroll view; .scrollView(axis:) the innermost along that axis")
    func nestedScrollViews() {
        let inner = Seen()
        let outer = Seen()
        let harness = InputChainHarness()
        harness.frame(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("top")
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            Text("abc")
                            ZStack {
                                reader(inner, in: .scrollView, width: 5, height: 1)
                                reader(outer, in: .scrollView(axis: .vertical), width: 5, height: 1)
                            }
                        }
                    }
                    .frame(width: 20, height: 1)
                    .padding(.leading, 2)
                }
            })
        #expect(inner.frame == CellRect(x: 3, y: 0, width: 5, height: 1))
        #expect(outer.frame == CellRect(x: 5, y: 1, width: 5, height: 1))
    }

    // MARK: - The correction

    @Test("A reader predicted wrong is drawn right on its first frame — one correction — and the frames after need none")
    func correctsOnceThenSteady() {
        let seen = Seen()
        let harness = InputChainHarness()
        // The stack says where it puts the reader's container; the container
        // does not say it draws the reader a row further down.
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            UnconvertedContainer { reader(seen, in: .named("s")) }
        }
        .coordinateSpace(.named("s"))
        let drawn = harness.frame(view)
        // The reader's content is what it was told: drawn with the answer
        // found, not with the prediction that missed.
        #expect(seen.frame?.y == 2)
        #expect(harness.geometryCorrections.named == 1)
        #expect(drawn.lines.count >= 3)
        // The miss is a constant the residual carries from here on.
        harness.frame(view)
        harness.frame(view)
        #expect(seen.frame?.y == 2)
        #expect(harness.geometryCorrections.named == 1)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A reader the stacks place is predicted exactly: drawn right on its first frame, no correction")
    func stackPlacedReaderIsPredicted() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            HStack(spacing: 1) {
                Text("bc")
                reader(seen, in: .named("s"))
            }
        }
        .coordinateSpace(.named("s"))
        harness.frame(view)
        #expect(seen.frame == CellRect(x: 3, y: 1, width: 10, height: 2))
        #expect(seen.builds == 1)
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("A row inserted above a reader moves it, and the stack's prediction follows: no correction")
    func insertionAboveIsPredicted() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = { (rows: Int) in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { Text("row \($0)") }
                reader(seen, in: .named("s"))
            }
            .coordinateSpace(.named("s"))
        }
        harness.frame(view(1))
        harness.frame(view(1))
        harness.frame(view(3))
        #expect(seen.frame?.y == 3)
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("A row inserted inside a container the prediction does not follow: one correction, the same frame")
    func insertionInsideUnconvertedCorrects() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = { (rows: Int) in
            UnconvertedContainer(rows: rows) { reader(seen, in: .named("s")) }
                .coordinateSpace(.named("s"))
        }
        harness.frame(view(1))
        harness.frame(view(1))
        let before = harness.geometryCorrections.named
        harness.frame(view(3))
        #expect(seen.frame?.y == 3)
        #expect(harness.geometryCorrections.named == before + 1)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A .global reader moved under the root is corrected at the root")
    func rootCorrection() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = { (top: Int) in reader(seen, in: .global).padding(.top, top) }
        harness.frame(view(1))
        #expect(seen.frame?.y == 1)
        #expect(harness.geometryCorrections.root == 1)
        harness.frame(view(1))
        #expect(harness.geometryCorrections.root == 1)
        harness.frame(view(2))
        #expect(seen.frame?.y == 2)
        #expect(harness.geometryCorrections.root == 2)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A reader that only reads its size costs no marker and no correction")
    func localReaderStampsNothing() {
        let harness = InputChainHarness()
        var width = 0
        let buffer = harness.frame(
            GeometryReader { proxy in
                width = proxy.size.width
                return Text("w")
            }
            .coordinateSpace(.named("s")))
        #expect(width == 40)
        #expect(!buffer.carriesGeometryMarkers)
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("A correction rolls back what the first drawing registered: key handlers and preferences once")
    func correctionRollsBackRegistrations() {
        struct Count: PreferenceKey {
            static var defaultValue: Int { 0 }
            static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
        }
        let seen = Seen()
        let harness = InputChainHarness()
        var counted: [Int] = []
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            UnconvertedContainer {
                reader(seen, in: .named("s"))
                    .onKeyEvent { _ in false }
                    .preference(key: Count.self, value: 1)
            }
        }
        .coordinateSpace(.named("s"))
        .onPreferenceChange(Count.self) { counted.append($0) }
        harness.frame(view)
        #expect(harness.geometryCorrections.named == 1)
        #expect(harness.tui.keyEventDispatcher.handlerCount == 1)
        #expect(counted.last == 1)
    }

    @Test("Known issue: an onChange inside a corrected subtree hears the first drawing's answer too")
    func correctedSubtreeSideEffects() {
        let seen = Seen()
        let harness = InputChainHarness()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            UnconvertedContainer {
                GeometryReader { proxy in
                    let y = proxy.frame(in: .named("s")).minY
                    Text("R").onChange(of: y) { old, new in seen.changes.append("\(old)→\(new)") }
                }
                .frame(width: 4, height: 1)
            }
        }
        .coordinateSpace(.named("s"))
        harness.frame(view)
        // SwiftUI fires nothing on a first appearance. The corrected frame's
        // first drawing stored the prediction, which the second drawing's value
        // differs from — the known issue the app header's correction had
        // (`RenderWalkCheckpoint`), scoped to the subtree.
        withKnownIssue("a correction re-runs the subtree's onChange against the first drawing") {
            #expect(seen.changes.isEmpty)
        }
    }

    // MARK: - onGeometryChange

    @Test("onGeometryChange asking a named space fires once the frame is done, with where the view is")
    func onGeometryChangeNamed() {
        let harness = InputChainHarness()
        var reports: [String] = []
        let view = { (rows: Int) in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { Text("row \($0)") }
                Text("watched")
                    .onGeometryChange(for: Int.self) { $0.frame(in: .named("s")).minY } action: { old, new in
                        reports.append("\(old)→\(new)")
                    }
            }
            .coordinateSpace(.named("s"))
        }
        harness.frame(view(2))
        #expect(reports == ["2→2"])
        harness.frame(view(2))
        #expect(reports == ["2→2"])
        harness.frame(view(4))
        #expect(reports == ["2→2", "2→4"])
        // A reporter is never corrected: it asks again at the end.
        #expect(harness.geometryCorrections.total == 0)
    }

    @Test("onGeometryChange asking .global reports the view's global origin")
    func onGeometryChangeGlobal() {
        let harness = InputChainHarness()
        var origins: [CellPoint] = []
        harness.frame(
            Text("x")
                .onGeometryChange(for: CellPoint.self) {
                    let frame = $0.frame(in: .global)
                    return CellPoint(x: frame.x, y: frame.y)
                } action: { origins.append($0) }
                .padding(.leading, 5)
                .padding(.top, 2))
        #expect(origins == [CellPoint(x: 5, y: 2)])
    }

    // MARK: - Pointer locations

    @Test("A tap located in a named space reports the cell in that space")
    func tapInNamedSpace() {
        let harness = InputChainHarness()
        var taps: [CellPoint] = []
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("0123")
            HStack(spacing: 0) {
                Text("ab")
                Text("XYZ").onTapGesture(coordinateSpace: .named("page")) { taps.append($0) }
            }
        }
        .padding(.leading, 3)
        .coordinateSpace(.named("page"))
        harness.frame(view)
        harness.frame(view)
        // Column 3 + 2 + 1 on screen is column 2 + 1 of the named view.
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 6, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 6, y: 1))
        #expect(taps == [CellPoint(x: 6, y: 1)])
    }

    @Test("A drag located in a named space, and a name nothing declared answering in the global space")
    func dragInNamedSpace() {
        let harness = InputChainHarness()
        var named: [CellPoint] = []
        var unknown: [CellPoint] = []
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("top")
            Text("drag me")
                .gesture(DragGesture(coordinateSpace: .named("box")).onEnded { named.append($0.location) })
                .simultaneousGesture(DragGesture(coordinateSpace: .named("missing")).onEnded { unknown.append($0.location) })
                .padding(.leading, 2)
        }
        .coordinateSpace(.named("box"))
        .padding(.top, 1)
        harness.frame(view)
        harness.frame(view)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 3, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 6, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 6, y: 2))
        // The box starts one row down: (6, 2) on screen is (6, 1) in it.
        #expect(named.last == CellPoint(x: 6, y: 1))
        #expect(unknown.last == CellPoint(x: 6, y: 2))
    }
}
