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

    @Test("A glued scroll view's offset tracker reads where the frame settles, through a name on the scroll view")
    func gluedOffsetTrackerThroughName() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = { (count: Int) in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { Text("line \($0)") }
                    reader(seen, in: .named("scroll"), width: 10, height: 1)
                }
            }
            .coordinateSpace(.named("scroll"))
            .scrollIndicators(.never)
            .defaultScrollAnchor(.bottom)
            .frame(width: 20, height: 6)
        }
        harness.frame(page(20))
        harness.frame(page(20))
        #expect(seen.frame?.y == 5)
        for count in 21...23 {
            // The reader is the last row, on the viewport's last line, after
            // every append: the glue moves the offset after the content drew.
            harness.frame(page(count))
            #expect(seen.frame?.y == 5, "\(count) lines")
        }
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A two-axis scroll view scrolled across draws a corrected reader at its horizontal offset too")
    func correctedReaderKeepsHorizontalOffset() {
        let harness = InputChainHarness()
        let seen = Seen()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let page = { (count: Int) in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { Text("line \($0) " + String(repeating: "-", count: 40)) }
                    reader(seen, in: .scrollView, width: 10, height: 1)
                }
            }
            .scrollPosition(binding)
            .scrollIndicators(.never)
            .defaultScrollAnchor(.bottom)
            .frame(width: 20, height: 6)
        }
        harness.frame(page(20))
        position.scrollTo(x: 5)
        harness.frame(page(20))
        harness.frame(page(20))
        #expect(seen.frame?.x == -5)
        // A line arriving moves the vertical offset after the content drew,
        // and the scroll view draws the reader again: at the horizontal offset
        // it is shown at, not at the left edge.
        harness.frame(page(21))
        #expect(seen.frame == CellRect(x: -5, y: 5, width: 10, height: 1))
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A scroll view whose correction refutes its content's measure puts the walk back before drawing it again")
    func correctionRedrawKeepsMarkers() {
        let harness = InputChainHarness()
        let seen = Seen()
        let drawings = Drawings()
        var shown: [Int: Bool] = [:]
        let page = {
            ScrollView {
                RefutingMeasure(drawings: drawings) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            // An `onChange` keeps the row out of the memos, so
                            // every drawing of it claims its marker anew.
                            Text("row \(index)")
                                .onScrollVisibilityChange { shown[index] = $0 }
                                .onChange(of: index) {}
                        }
                        reader(seen, in: .scrollView, width: 10, height: 1)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(width: 20, height: 6)
        }
        // The reader's first frame, with nothing to predict it from: the
        // scroll view draws its content again, and that second drawing
        // refutes the content's measure, so it is drawn a third time.
        drawings.refuting = 2
        harness.frame(page())
        #expect(drawings.count == 3)
        #expect(harness.geometryCorrections.scrollView == 1)
        #expect(seen.frame?.y == 3)
        // The third drawing took the ids the others did: the rows on screen
        // keep the markers they were reported under, and stay shown.
        harness.frame(page())
        #expect(shown == [0: true, 1: true, 2: true])
        #expect(seen.frame?.y == 3)
    }

    @Test("A push past the scroll view's edge is predicted: the reader moves with the content, uncorrected")
    func overscrollPushIsPredicted() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    reader(seen, in: .scrollView, width: 10, height: 1)
                    ForEach(0..<30, id: \.self) { Text("line \($0)") }
                }
            }
            .scrollOverscroll(top: .rows(6))
            .scrollIndicators(.never)
            .frame(width: 20, height: 8)
        }
        harness.frame(page())
        harness.frame(page())
        #expect(seen.frame?.y == 0)
        let settled = harness.geometryCorrections
        // At the top already: each tick up opens the allowance a wheel step
        // more, sliding the content — and the reader — down the viewport, and
        // a tick down closes it again.
        let ticks: [(MouseButton, Int)] = [(.scrollUp, 3), (.scrollUp, 6), (.scrollDown, 3), (.scrollDown, 0)]
        for (button, slid) in ticks {
            harness.mouse(MouseEvent(button: button, phase: .scrolled, x: 2, y: 2))
            harness.frame(page())
            #expect(seen.frame?.y == slid)
        }
        #expect(harness.geometryCorrections == settled)
    }

    @Test("A scroll view places its content by its slide only for a carried origin, which alone reads it")
    func slideIsReadOnlyForACarriedOrigin() {
        let core = _ScrollViewCore(axes: .vertical, content: Text("x"), explicitFocusID: nil, isDisabled: false)
        let handler = ScrollViewHandler(focusID: "sv")
        // Three rows at the bottom of a viewport of ten: the window is slid
        // seven rows down over them.
        handler.contentHeight = 3
        var environment = EnvironmentValues()
        environment.defaultScrollAnchor = .bottom
        let context = RenderContext(availableWidth: 20, availableHeight: 10, environment: environment)
        #expect(core.contentSlide(handler: handler, viewportHeight: 10, context: context.carryingGeometryOrigin()) == -7)
        // With no origin carried, the placement moves nothing, and no
        // alignment anchor is read for it.
        #expect(core.contentSlide(handler: handler, viewportHeight: 10, context: context) == 0)
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
        let view = { (top: Int) in UnconvertedContainer(rows: top) { reader(seen, in: .global) } }
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

    @Test("onGeometryChange asking another space in a Table cell reports where its row is drawn")
    func onGeometryChangeInTableCell() {
        struct Row: Identifiable {
            let id: Int
        }
        let harness = InputChainHarness()
        var reports: [String] = []
        let table = Table([Row(id: 0), Row(id: 1)]) {
            TableColumn("Name") { (row: Row) in
                Text("row \(row.id)")
                    .onGeometryChange(for: Int.self) { $0.frame(in: .global).minY } action: { old, new in
                        reports.append("\(row.id): \(old)→\(new)")
                    }
            }
            .width(12)
        }
        harness.frame(table)
        // A table carries the markers its view cells drew up with their
        // regions (decisions D5G, B-D5G-2), so the frame finds each where its
        // row is drawn — below the header and its rule — and the initial
        // report is that place. Until 2026-10-06 they were left behind, and
        // each was told the origin.
        #expect(reports == ["0: 2→2", "1: 3→3"])
        harness.frame(table)
        #expect(reports == ["0: 2→2", "1: 3→3"])
    }

    @Test("A reader in a Table cell is told where it is drawn: one correction on its first frame, exact after")
    func readerInTableCell() {
        struct Row: Identifiable {
            let id: Int
        }
        let harness = InputChainHarness()
        var drawn: [Int: Int] = [:]
        let page = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            Text("b")
            Table([Row(id: 0), Row(id: 1)]) {
                TableColumn("Y") { (row: Row) in
                    GeometryReader { proxy in
                        Text("y \(Self.note(proxy.frame(in: .global).minY, as: row.id, in: &drawn))")
                    }
                }
                .width(12)
                TableColumn("X") { (row: Row) in
                    GeometryReader { proxy in
                        Text("x \(Self.note(proxy.frame(in: .named("cell")).minX, as: 10 + row.id, in: &drawn))")
                    }
                    .padding(.leading, 2)
                    .coordinateSpace(.named("cell"))
                }
                .width(12)
            }
        }
        // A table carries the markers its view cells drew up with their
        // regions (decisions D5G, B-D5G-2), so the root finds a reader in a
        // cell where its row is drawn: two text rows, the header and its rule
        // above the first. A cell carries no geometry origin, so the reader's
        // first frame predicts wrong and the root draws the frame again,
        // exact — and every frame after reads what was found, with no
        // correction. A space declared inside the cell answers its reader
        // exactly, as before.
        for frame in 1...3 {
            drawn = [:]
            harness.frame(page)
            #expect(drawn == [0: 4, 1: 5, 10: 2, 11: 2], "frame \(frame)")
            #expect(harness.geometryCorrections.total == 1, "frame \(frame)")
            #expect(harness.geometryCorrections.residual == 0, "frame \(frame)")
        }
    }

    private static func note(_ value: Int, as row: Int, in drawn: inout [Int: Int]) -> Int {
        drawn[row] = value
        return value
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

    @Test("A pointer in a named space no owner finds the view in is in the global space, for hover as for a drag")
    func unfoundNameIsGlobalForEveryPointer() {
        let harness = InputChainHarness()
        var hovered: [HoverPhase] = []
        var dragged: [CellPoint] = []
        let page = {
            VStack(alignment: .leading, spacing: 0) {
                Text("top")
                DroppingMarkers {
                    Text("point here")
                        .onContinuousHover(coordinateSpace: .named("box")) { hovered.append($0) }
                        .gesture(DragGesture(coordinateSpace: .named("box")).onEnded { dragged.append($0.location) })
                        .padding(.leading, 3)
                }
            }
            .coordinateSpace(.named("box"))
        }
        harness.hover([(x: 5, y: 1)], page)
        // (5, 1) on screen, two cells into the view: the box is the screen
        // here, and nothing found the view in it.
        #expect(hovered.last == .active(CellPoint(x: 5, y: 1)))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 5, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 8, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 8, y: 1))
        #expect(dragged.last == CellPoint(x: 8, y: 1))
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

/// Draws its content and drops the geometry markers in it, keeping every hit
/// target — a view whose handlers reach the dispatcher while its marker
/// reaches no owner of a space.
private struct DroppingMarkers<Content: View>: View, Renderable, Layoutable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: Never { fatalError("DroppingMarkers renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        buffer.hitTestRegions.removeAll(where: \.isGeometryMarker)
        return buffer
    }
}

/// How many times a ``RefutingMeasure`` drew in a render pass, and which
/// drawing refutes its scroll view's measure.
@MainActor
private final class Drawings {
    var count = 0
    var refuting: Int?
}

/// Draws its content, telling its scroll view on the drawing
/// ``Drawings/refuting`` names that the drawing refuted the measure the canvas
/// was sized by — as a uniform lazy stack does on reaching a row of another
/// height (`ScrollContentReply.measureWentStale`) — so the scroll view
/// measures again and draws the content once more.
private struct RefutingMeasure<Content: View>: View, Renderable, Layoutable {
    let drawings: Drawings
    let content: Content

    init(drawings: Drawings, @ViewBuilder content: () -> Content) {
        self.drawings = drawings
        self.content = content()
    }

    var body: Never { fatalError("RefutingMeasure renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            drawings.count += 1
            if drawings.count == drawings.refuting {
                context.environment.scrollContentWindow?.reply?.measureWentStale = true
            }
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
}
