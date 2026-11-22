//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersLayoutTests.swift
//
//  Frames, padding, offsets, stacks, spacers and every other modifier that
//  takes a length in cells, handed negative and enormous lengths: each must
//  draw without trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Hostile numbers: layout")
struct HostileNumbersLayoutTests {

    @Test("A fixed frame of any length draws", arguments: Hostile.ints)
    func fixedFrame(length: Int) {
        drawHostile(Text("frame").frame(width: length, height: 3))
        drawHostile(Text("frame").frame(width: 7, height: length))
        drawHostile(Text("frame").frame(width: length))
        drawHostile(Text("frame").frame(height: length))
    }

    @Test("A flexible frame of any bounds draws", arguments: Hostile.ints)
    func flexibleFrame(length: Int) {
        drawHostile(Text("frame").frame(minWidth: length))
        drawHostile(Text("frame").frame(minHeight: length))
        drawHostile(Text("frame").frame(idealWidth: length, idealHeight: 2).fixedSize())
        drawHostile(Text("frame").frame(idealWidth: 2, idealHeight: length).fixedSize())
        drawHostile(Text("frame").frame(maxWidth: .fixed(length), maxHeight: .fixed(length)))
        drawHostile(Text("frame").frame(minWidth: length, idealWidth: length, maxWidth: .infinity))
        drawHostile(Text("frame").frame(minHeight: length, idealHeight: length, maxHeight: .infinity))
        drawHostile(Text("frame").frame(minWidth: 5, maxWidth: .fixed(length)))
    }

    @Test("Padding of any length draws", arguments: Hostile.ints)
    func padding(length: Int) {
        drawHostile(Text("pad").padding(.horizontal, length))
        drawHostile(Text("pad").padding(.vertical, length))
        drawHostile(Text("pad").padding(EdgeInsets(top: 1, leading: length, bottom: 1, trailing: length)))
        drawHostile(Text("pad").padding(EdgeInsets(top: length, leading: 1, bottom: length, trailing: 1)))
        drawHostile(Text("pad").safeAreaPadding(.horizontal, length))
        drawHostile(Text("pad").safeAreaPadding(.top, length))
    }

    @Test("An offset or a position of any distance draws", arguments: Hostile.ints)
    func offsetAndPosition(distance: Int) {
        drawHostile(Text("offset").offset(x: distance, y: distance))
        drawHostile(Text("position").position(x: distance, y: distance))
        drawHostile(VStack { Text("a"); Text("b").offset(x: distance) })
    }

    @Test("Stacks and spacers of any spacing draw", arguments: Hostile.ints)
    func stacks(spacing: Int) {
        drawHostile(VStack(spacing: spacing) { Text("a"); Text("b") })
        drawHostile(HStack(spacing: spacing) { Text("a"); Text("b") })
        drawHostile(HStack { Text("a"); Spacer(minLength: spacing); Text("b") })
        drawHostile(VStack { Text("a"); Spacer(minLength: spacing); Text("b") })
        drawHostile(ZStack { Text("a"); Text("b") }.padding(.vertical, spacing))
    }

    @Test("Line limits and line spacing of any count draw", arguments: Hostile.ints)
    func lines(count: Int) {
        let text = Text("one two three four five six seven eight nine ten")
        drawHostile(text.lineLimit(count))
        drawHostile(text.lineLimit(count, reservesSpace: true))
        drawHostile(text.lineSpacing(count))
        if count >= 0 {
            drawHostile(text.lineLimit(count...))
            drawHostile(text.lineLimit(...count))
        }
    }

    @Test("Layout priority, z-index and aspect ratio of any value draw", arguments: Hostile.doubles)
    func priorities(value: Double) {
        drawHostile(HStack { Text("a").layoutPriority(value); Text("b") })
        drawHostile(ZStack { Text("a").zIndex(value); Text("b") })
        drawHostile(HStack { Text("a").zIndex(value); Text("b").offset(x: -1) })
        drawHostile(VStack { Text("a").zIndex(value); Text("b").offset(y: -1) })
        drawHostile(Color.red.aspectRatio(value, contentMode: .fit))
        drawHostile(Color.red.aspectRatio(value, contentMode: .fill))
    }

    @Test("A container-relative frame of any division draws", arguments: Hostile.ints)
    func containerRelative(value: Int) {
        drawHostile(Text("c").containerRelativeFrame(.horizontal, count: value, span: 1, spacing: 0))
        drawHostile(Text("c").containerRelativeFrame(.horizontal, count: 3, span: value, spacing: 0))
        drawHostile(Text("c").containerRelativeFrame([.horizontal, .vertical], count: 3, span: 1, spacing: value))
        drawHostile(Text("c").containerRelativeFrame(.horizontal) { _, _ in value })
    }

    @Test("A shadow of any radius or offset draws", arguments: Hostile.ints)
    func shadow(value: Int) {
        drawHostile(Text("shadow").shadow(radius: value))
        drawHostile(Text("shadow").shadow(radius: 1, x: value, y: value))
    }

    @Test("Label and scrollbar spacing of any width draw", arguments: Hostile.ints)
    func labelAndScrollbar(value: Int) {
        drawHostile(Label("Title", systemImage: "star").labelIconToTitleSpacing(value))
        drawHostile(Label("Title", systemImage: "star").labelReservedIconWidth(value))
        drawHostile(
            ScrollView { VStack { ForEach(0..<20, id: \.self) { Text("row \($0)") } } }
                .scrollbarWidth(value))
        drawHostile(
            ScrollView { VStack { ForEach(0..<20, id: \.self) { Text("row \($0)") } } }
                .scrollbarSpacing(value))
    }

    @Test("A badge of any count draws", arguments: Hostile.ints)
    func badge(count: Int) {
        drawHostile(List { Text("row").badge(count) })
    }

    // MARK: Anchors, guides, offsets and blank sizes (hunt 11-20)
    //
    // Each of these trapped before its fix, which ends the whole run; so each
    // runs in a child process, where a trap is this test's recorded failure.
    // The checks are `LayoutTraps`' (below), as an exit test's body may
    // capture nothing.

    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        @Test("A scroll anchor of any value scrolls, reports and settles (LAYOUT-4, CONC-5, SCROLL-14)")
        func scrollAnchors() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.scrollAnchors() } }
        }

        @Test("A placement, grid cell, popover, matched geometry or preference anchor of any value draws (LAYOUT-4, TABLES-4, CONC-5)")
        func placementAnchors() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.placementAnchors() } }
        }

        @Test("A list row separator guide of any value draws (CONC-2)")
        func separatorGuides() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.separatorGuides() } }
        }

        @Test("A visual-effect offset and an offset or scale transition of any value draw (CONC-3, CONC-9, STYLE-11)")
        func effectOffsets() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.effectOffsets() } }
        }

        @Test("A spacer, a safe-area inset and a layout's spacing of any length draw (CORE1-1, FMOD-2, LAYOUT-5, SCROLL-10)")
        func blankLengths() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.blankLengths() } }
        }

        @Test("A canvas shadow of any offset draws (LEAF-11)")
        func canvasShadow() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.canvasShadow() } }
        }

        @Test("A lazy stack of `Int.max` rows of several lines measures, draws and scrolls to its end (SCROLL-13)")
        func endlessLazyStack() async {
            await #expect(processExitsWith: .success) { await MainActor.run { LayoutTraps.endlessLazyStack() } }
        }
    #endif

    @Test("A blank buffer of a negative size is empty (CORE1-1)")
    func negativeBlankBuffers() {
        let both = FrameBuffer(emptyWithWidth: -3, height: -2)
        #expect(both.width == 0 && both.height == 0)
        #expect(FrameBuffer(emptyWithWidth: 4, height: -1).height == 0)
        #expect(FrameBuffer(emptyWithWidth: -4, height: 2).lines == ["", ""])
        #expect(FrameBuffer(emptyWithHeight: -1).height == 0)
    }

    @Test("An anchor's place in a view is held: NaN is the origin, an infinity is far, not a trap (SCROLL-23)")
    func anchorGeometry() {
        let origin = CellPoint(x: 5, y: 5)
        let size = CellSize(width: 10, height: 4)
        func point(_ geometry: AnchorGeometry) -> CellPoint? { geometry.resolve(origin: origin, size: size) as? CellPoint }
        #expect(point(.unitPoint(UnitPoint(x: .nan, y: .nan))) == origin)
        #expect(point(.unitPoint(UnitPoint(x: .infinity, y: -.infinity))) == CellPoint(x: 5 + (1 << 30), y: 5 - (1 << 30)))
        #expect(point(.unitPoint(UnitPoint(x: 1e19, y: 0.5))) == CellPoint(x: 5 + (1 << 30), y: 7))
        #expect(point(.point(CellPoint(x: .max, y: .min))) == CellPoint(x: 5 + 65_536, y: 5 - 65_536))
        let rect = AnchorGeometry.rect(CellRect(x: .max, y: 0, width: 1, height: 1)).resolve(origin: origin, size: size)
        #expect((rect as? CellRect)?.x == 5 + 65_536)
    }

    @Test("A placement an animation overshoots to anything is held (sweep: PlacementStore, MatchedGeometryRegistry)")
    func animatedPlacements() {
        #expect(ChildPlacement(AnimatablePair(.nan, .infinity)) == ChildPlacement(x: 0, y: 65_536))
        #expect(ChildPlacement(AnimatablePair(-1e300, 2.4)) == ChildPlacement(x: -65_536, y: 2))
    }
}

/// The hostile-number checks the layout suite runs in child processes.
@MainActor
private enum LayoutTraps {
    /// The anchors the checks hand an API: NaN, the infinities and 1e19 (each
    /// past `Int`), on both axes and on one, and one outside the unit square
    /// (legal SwiftUI). Few, as a far placement is drawn at its 2^16 cells.
    static let anchors: [UnitPoint] = [
        UnitPoint(x: .nan, y: .nan), UnitPoint(x: .infinity, y: .infinity), UnitPoint(x: -.infinity, y: -.infinity),
        UnitPoint(x: 1e19, y: -1e19), UnitPoint(x: 0.5, y: .nan), UnitPoint(x: 3, y: -2),
    ]

    /// The proxy a reader hands its content.
    final class ProxyBox {
        var proxy: ScrollViewProxy?
    }

    /// Frames `page` at every hostile size: once, after `act`, and once more.
    static func frames(_ page: () -> some View, configure: (inout EnvironmentValues) -> Void = { _ in }, act: (InputChainHarness) -> Void) {
        for size in Hostile.sizes {
            let harness = InputChainHarness(width: size.width, height: size.height, configure: configure)
            harness.frame(page())
            act(harness)
            harness.frame(page())
            harness.frame(page())
        }
    }

    static func scrollAnchors() {
        for anchor in anchors {
            // `scrollTo(_:anchor:)`, vertical and horizontal.
            let box = ProxyBox()
            frames({
                ScrollViewReader { proxy in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = box.proxy = proxy
                    ScrollView { LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)").id($0) } } }
                }
            }, act: { _ in box.proxy?.scrollTo(20, anchor: anchor) })
            frames({
                ScrollViewReader { proxy in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = box.proxy = proxy
                    ScrollView(.horizontal) { LazyHStack { ForEach(0..<40, id: \.self) { Text("col \($0)").id($0) } } }
                }
            }, act: { _ in box.proxy?.scrollTo(20, anchor: anchor) })
            // `.scrollPosition(id:anchor:)`: the row and the column it reports.
            drawHostile(
                ScrollView { LazyVStack { ForEach(0..<40, id: \.self) { Text("row \($0)") } }.scrollTargetLayout() }
                    .scrollPosition(id: .constant(Int?.some(20)), anchor: anchor))
            drawHostile(
                ScrollView(.horizontal) { LazyHStack { ForEach(0..<40, id: \.self) { Text("c\($0)") } }.scrollTargetLayout() }
                    .scrollPosition(id: .constant(Int?.some(20)), anchor: anchor))
            // A `List` under `.scrollPosition(_:anchor:)`, read every render.
            drawHostile(List(0..<40, id: \.self) { Text("row \($0)") }.scrollPosition(.constant(ScrollPosition()), anchor: anchor))
            // `.defaultScrollAnchor` over content shorter than its viewport,
            // and longer.
            drawHostile(ScrollView { Text("short") }.defaultScrollAnchor(anchor))
            drawHostile(ScrollView(.horizontal) { Text("short") }.defaultScrollAnchor(anchor))
            drawHostile(ScrollView { VStack { ForEach(0..<40, id: \.self) { Text("row \($0)") } } }.defaultScrollAnchor(anchor))
            // `.viewAligned(anchor:)` and a custom behaviour's target anchor,
            // settled by a key.
            for behavior in [AnyScrollTargetBehavior(.viewAligned(anchor: anchor)), AnyScrollTargetBehavior(Anchoring(anchor: anchor))] {
                frames({
                    ScrollView { LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }.scrollTargetLayout() }
                        .scrollTargetBehavior(behavior)
                }, act: { harness in
                    harness.press(KeyEvent(key: .pageDown))
                    harness.press(KeyEvent(key: .down))
                })
            }
        }
    }

    /// A behaviour that aims every target's anchor at `anchor`.
    struct Anchoring: ScrollTargetBehavior {
        let anchor: UnitPoint

        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            target.anchor = anchor
        }
    }

    /// Places its one subview at the middle of its bounds by `anchor`, and
    /// again within them.
    struct AnchorPlacing: Layout {
        let anchor: UnitPoint
        let within: Bool

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
            ViewSize(width: proposal.width ?? 10, height: proposal.height ?? 3)
        }

        func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            for subview in subviews {
                if within {
                    subview.place(in: bounds, anchor: anchor, proposal: .unspecified)
                } else {
                    subview.place(at: CellPoint(x: bounds.x + bounds.width / 2, y: bounds.y), anchor: anchor, proposal: .unspecified)
                }
            }
        }
    }

    /// A source and a follower, matched by `anchor`.
    struct Matched: View {
        let anchor: UnitPoint
        @Namespace private var namespace

        var body: some View {
            VStack {
                Text("source").matchedGeometryEffect(id: 1, in: namespace, anchor: anchor)
                Text("follower is wider").matchedGeometryEffect(id: 1, in: namespace, anchor: anchor, isSource: false)
            }
        }
    }

    static func placementAnchors() {
        for anchor in anchors {
            drawHostile(AnchorPlacing(anchor: anchor, within: false) { Text("placed") })
            drawHostile(AnchorPlacing(anchor: anchor, within: true) { Text("placed") })
            drawHostile(
                Grid {
                    GridRow { Text("a").gridCellAnchor(anchor); Text("a wide cell") }
                    GridRow { Text("a long cell"); Text("b").gridCellAnchor(anchor) }
                })
            drawHostile(Text("anchor").popover(isPresented: .constant(true), attachmentAnchor: .point(anchor)) { Text("pop") })
            drawHostile(Matched(anchor: anchor))
        }
    }

    static func separatorGuides() {
        for value in Hostile.doubles + [.greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            drawHostile(
                List {
                    Text("a").alignmentGuide(.listRowSeparatorLeading) { _ in value }
                    Text("b").alignmentGuide(.listRowSeparatorTrailing) { _ in value }
                    // A ratio guide, +infinity on a row squeezed to no height.
                    Text("c").alignmentGuide(.listRowSeparatorLeading) { d in Double(d.width) / Double(d.height) * value }
                    HStack {
                        Text("d").alignmentGuide(.listRowSeparatorLeading) { _ in value }
                        Text("e").alignmentGuide(.listRowSeparatorTrailing) { _ in -value }
                    }
                })
        }
    }

    /// A view that appears between its first two frames.
    struct Arriving<Inserted: View>: View {
        let shown: Bool
        let inserted: Inserted

        var body: some View {
            VStack {
                Text("above")
                if shown { inserted }
            }
        }
    }

    /// A root environment whose frames may animate.
    static func animating(_ environment: inout EnvironmentValues) {
        environment.canAnimate = true
    }

    static func effectOffsets() {
        for distance in Hostile.ints {
            drawHostile(Text("effect").visualEffect { effect, _ in effect.offset(x: distance, y: distance) })
            drawHostile(Text("effect").visualEffect { effect, _ in effect.offset(CellSize(width: distance, height: distance == .min ? .max : -distance)) })
        }
        let nows: [Int64] = [0, 0, 16_666_667, 500_000_000, 2_000_000_000]
        let transaction = Transaction(animation: .linear(duration: 1))
        for distance in Hostile.ints {
            drawHostile(configure: animating, transaction: transaction, nows: nows) { index in
                Arriving(shown: index > 0, inserted: Text("offset").transition(.offset(x: distance, y: distance)))
            }
            drawHostile(configure: animating, transaction: transaction, nows: nows) { index in
                Arriving(shown: index > 0, inserted: Text("both").transition(.offset(x: distance).combined(with: .offset(y: distance))))
            }
        }
        for anchor in anchors {
            drawHostile(configure: animating, transaction: transaction, nows: nows) { index in
                Arriving(shown: index > 0, inserted: Text("a scaled line").transition(.scale(scale: 0.5, anchor: anchor)))
            }
        }
        // STYLE-11: an anchor outside the unit square draws no row wider than
        // the buffer says it is, at every frame of the arrival.
        let harness = InputChainHarness(width: 30, height: 4) { $0.canAnimate = true }
        harness.transaction = transaction
        for (index, now) in nows.enumerated() {
            harness.now = now
            let buffer = harness.frame(
                Arriving(shown: index > 0, inserted: Text("twenty cells of text").transition(.scale(scale: 0.5, anchor: UnitPoint(x: 3, y: 0.5)))))
            precondition(buffer.lines.allSatisfy { $0.strippedLength <= buffer.width }, "a row wider than its buffer at \(now)")
        }
    }

    static func blankLengths() {
        for length in Hostile.ints + [-3] {
            // CORE1-1: a spacer outside a stack, and one changed after `init`.
            drawHostile(Spacer(minLength: length))
            drawHostile(Text("a").overlay { Spacer(minLength: length) })
            var spacer = Spacer()
            spacer.minLength = length
            drawHostile(spacer)
            drawHostile(HStack { Text("a"); spacer; spacer; Text("b") })
            drawHostile(VStack { Text("a"); spacer; spacer; Text("b") })
            // FMOD-2: a bar's spacing, on each edge.
            drawHostile(Text("A").safeAreaInset(edge: .bottom, spacing: length) { Text("B") })
            drawHostile(Text("A").safeAreaInset(edge: .top, spacing: length) { Text("B") })
            drawHostile(Text("A").safeAreaInset(edge: .leading, spacing: length) { Text("B") })
            drawHostile(Text("A").safeAreaInset(edge: .trailing, spacing: length) { Text("B") })
            drawHostile(Text("A").safeAreaBar(edge: .bottom, spacing: length) { Text("B") })
            drawHostile(
                ScrollView { VStack { ForEach(0..<10, id: \.self) { Text("row \($0)") } } }
                    .safeAreaPadding(.vertical, length).safeAreaPadding(.vertical, length))
            // LAYOUT-5: the Layout-value stacks and `FlowLayout`, stated and set.
            drawHostile(VStackLayout(spacing: length) { Text("a"); Text("b") })
            drawHostile(HStackLayout(spacing: length) { Text("a"); Text("b") })
            var column = VStackLayout()
            column.spacing = length
            drawHostile(column { Text("a"); Text("b"); Text("c") })
            drawHostile(FlowLayout(spacing: length) { ForEach(0..<6, id: \.self) { Text("item \($0)") } })
            drawHostile(FlowLayout(lineSpacing: length) { ForEach(0..<6, id: \.self) { Text("item \($0)") } })
            // SCROLL-10: a grid track changed after `init`.
            var track = GridItem()
            track.size = .fixed(length)
            track.spacing = length
            drawHostile(LazyVGrid(columns: [track, GridItem()]) { ForEach(0..<6, id: \.self) { Text("\($0)") } })
        }
        // FMOD-2: a negative spacing past both views' extent overlaps them to
        // nothing, not below.
        let harness = InputChainHarness(width: 20, height: 6)
        let overlapped = harness.frame(Text("A").safeAreaInset(edge: .bottom, spacing: -3) { Text("B") }.fixedSize())
        precondition(overlapped.height >= 0)
    }

    /// SwiftUI's endless-list idiom, `ForEach(0..<Int.max)`, of rows whose
    /// lines (two each, one with a line between, or one to three) are more
    /// than `Int` counts: priced at the pitch, the stack's measure and total
    /// trapped before the first frame. Drawn through a scroll view's window
    /// and reply, as its content: at the top, at the end, and a step up from
    /// it, the end being the offset the reply's total puts it at.
    static func endlessLazyStack() {
        func scroll<V: View>(_ stack: V) {
            let context = makeBareRenderContext(width: 20, height: 10)
            _ = measureChild(stack, proposal: ProposedViewSize(width: 20, height: nil), context: context)
            var offset = 0
            for step in 0..<4 {
                let reply = ScrollContentReply()
                var frame = context
                frame.environment.scrollContentWindow = ScrollContentWindow(
                    offset: offset, viewportHeight: 10, contentIdentity: nil, reply: reply)
                _ = renderToBuffer(stack, context: frame)
                let end = max(0, (reply.sliceTotalHeight ?? 0) - 10)
                offset = step < 2 ? end : max(0, end - 10)
            }
        }
        scroll(LazyVStack { ForEach(0..<Int.max, id: \.self) { Text(verbatim: "row \($0)\nsecond") } })
        scroll(LazyVStack(spacing: 1) { ForEach(0..<Int.max, id: \.self) { Text(verbatim: "row \($0)") } })
        scroll(
            LazyVStack {
                ForEach(0..<Int.max, id: \.self) { Text(verbatim: "row \($0)").frame(height: $0 % 3 + 1) }
            })
    }

    static func canvasShadow() {
        for value in Hostile.doubles + [1e19, -1e19] {
            drawHostile(
                Canvas { context, size in
                    context.addFilter(.shadow(color: .red, radius: 1, x: value, y: value))
                    context.fill(Path(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2)), with: .color(.blue))
                })
        }
    }
}
