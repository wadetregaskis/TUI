//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledLocateTests.swift
//
//  SCROLL-FIT's locate by route (design B-SCROLLFIT-15, A-SCROLLFIT-4 (b)):
//  `ScrollViewReader.scrollTo` and a `ScrollPosition` by id find a row inside
//  a pulled container at any depth — a lazy stack under a title, the second
//  of two, in a box, in the rows of an outer lazy stack, rows never built
//  included — and land it exactly where the anchor asks, as the same rows
//  drawn eagerly land it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds {
    var count = 0
}

/// A page whose `j` key scrolls the reader's proxy to `key` at `anchor`.
private struct SeekPage<ID: Hashable, Content: View>: View {
    let key: ID
    let anchor: UnitPoint?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content() }
                .onKeyEvent(.character("j")) { proxy.scrollTo(key, anchor: anchor) }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT pull: scrollTo finds a row inside pulled containers at any depth")
struct PulledLocateTests {
    enum Shape: String, CaseIterable, Sendable {
        case titled, secondOfTwo, boxed, nestedPulled, nestedSmall, hStack
    }

    /// The ids of stack `prefix`'s rows, which are their texts: unique on
    /// the page, as a seek's key must be.
    private static func ids(_ prefix: String, _ count: Int) -> [String] { (0..<count).map { "\(prefix)\($0)" } }

    /// The row `id`: two lines every third row.
    private static func text(_ id: String) -> Text {
        Text(height(id) == 2 ? "\(id)\n  more" : id)
    }

    /// The lines row `id` draws.
    private static func height(_ id: String) -> Int {
        let index = Int(id.drop { !$0.isNumber }.split(separator: "r").last ?? "") ?? 0
        return index.isMultiple(of: 3) ? 2 : 1
    }

    private static func lazyRows(_ prefix: String, _ count: Int, builds: Builds?) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(ids(prefix, count), id: \.self) { id in
                builds?.count += 1
                return text(id)
            }
        }
    }

    private static func eagerRows(_ prefix: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ids(prefix, count), id: \.self) { text($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private static func content(_ shape: Shape, lazy: Bool, builds: Builds?) -> some View {
        let rows: (String, Int) -> AnyView = { prefix, count in
            lazy ? AnyView(lazyRows(prefix, count, builds: builds)) : AnyView(eagerRows(prefix, count))
        }
        switch shape {
        case .titled:
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                rows("a", 400)
            }
        case .secondOfTwo:
            VStack(alignment: .leading, spacing: 0) {
                Text("first")
                rows("a", 400)
                Text("second")
                rows("b", 400)
            }
        case .boxed:
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                GroupBox { rows("a", 400) }
                Text("footer")
            }
        case .hStack:
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                HStack(alignment: .top, spacing: 1) {
                    Text("|")
                    rows("a", 400)
                }
            }
        case .nestedPulled, .nestedSmall:
            // Twelve groups of 300 rows, each stack pulled, or 300 of twenty,
            // the outer stack windowed and its groups drawn whole.
            let (groupCount, inner) = shape == .nestedPulled ? (12, 300) : (300, 20)
            let groups = lazy
                ? AnyView(
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<groupCount, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text("group \(group)")
                                lazyRows("g\(group)r", inner, builds: builds)
                            }
                        }
                    })
                : AnyView(
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<groupCount, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text("group \(group)")
                                eagerRows("g\(group)r", inner)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading))
            groups
        }
    }

    /// The row each shape seeks: deep in its stack, past rows never built.
    private static func target(_ shape: Shape) -> String {
        switch shape {
        case .titled, .boxed, .hStack: "a301"
        case .secondOfTwo: "b250"
        case .nestedPulled: "g9r150"
        case .nestedSmall: "g250r12"
        }
    }

    private static func app(
        _ shape: Shape, lazy: Bool, anchor: UnitPoint?, key: String? = nil, builds: Builds? = nil
    ) -> TestApp {
        let key = key ?? target(shape)
        return TestApp(width: 30, height: 12) {
            SeekPage(key: key, anchor: anchor) { content(shape, lazy: lazy, builds: builds) }
        }
    }

    /// The screen without the scrollbar's column: the lazy stack's thumb reads
    /// its estimated height, the eager one's its exact one.
    private static func lines(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    /// The first screen line showing row `key`'s text, the key alone.
    private static func line(of key: String, in app: TestApp) -> Int? {
        app.screen.lines.firstIndex {
            $0.range(of: "(^|[^a-z0-9])\(key)([^0-9]|$)", options: .regularExpression) != nil
        }
    }

    /// The line `anchor` puts a row `height` lines tall on, in a viewport
    /// `viewport` lines tall.
    private static func expectedLine(_ anchor: UnitPoint, height: Int, viewport: Int = 12) -> Int {
        Int((Double(viewport - height) * anchor.y).rounded())
    }

    @Test("A seek lands its row exactly where the anchor asks: top, centre and bottom", arguments: Shape.allCases)
    func seekLandsWhereTheAnchorAsks(_ shape: Shape) {
        let key = Self.target(shape)
        for anchor in [UnitPoint.top, .center, .bottom] {
            let app = Self.app(shape, lazy: true, anchor: anchor)
            _ = app.screen
            _ = app.press(.character("j"))
            #expect(
                Self.line(of: key, in: app) == Self.expectedLine(anchor, height: Self.height(key)),
                "\(shape) \(anchor):\n\(app.screen)")
        }
    }

    /// Twin: the same rows drawn eagerly, whose seek finds the key below a row
    /// by the same search and places it from the rows' exact places.
    @Test("A seek draws what the same seek over the eager rows draws", arguments: Shape.allCases)
    func seekDrawsWhatTheEagerOneDraws(_ shape: Shape) {
        for anchor in [UnitPoint.top, .center, .bottom, nil] {
            let lazy = Self.app(shape, lazy: true, anchor: anchor)
            let eager = Self.app(shape, lazy: false, anchor: anchor)
            _ = lazy.screen
            _ = eager.screen
            _ = lazy.press(.character("j"))
            _ = eager.press(.character("j"))
            #expect(
                Self.lines(lazy) == Self.lines(eager),
                "\(shape) \(String(describing: anchor)):\n\(lazy.screen)\n---\n\(eager.screen)")
            // And it stays put on the frame after.
            _ = lazy.press(.character("x"))
            _ = eager.press(.character("x"))
            #expect(Self.lines(lazy) == Self.lines(eager), "\(shape) \(String(describing: anchor)), after")
        }
    }

    /// From where a seek lands, the page scrolls on as it would from there:
    /// paging up and down again draws what the eager twin draws, and Home
    /// brings the top back.
    @Test("After a seek, paging and Home draw what the eager rows draw", arguments: Shape.allCases)
    func scrollingOnAfterASeek(_ shape: Shape) {
        let lazy = Self.app(shape, lazy: true, anchor: .center)
        let eager = Self.app(shape, lazy: false, anchor: .center)
        _ = lazy.press(.character("j"))
        _ = eager.press(.character("j"))
        for key in [Key.pageUp, .pageDown, .pageDown] {
            _ = lazy.press(key)
            _ = eager.press(key)
            #expect(Self.lines(lazy) == Self.lines(eager), "\(shape) \(key):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
        _ = lazy.press(.home)
        _ = eager.press(.home)
        #expect(Self.lines(lazy) == Self.lines(eager), "\(shape) home:\n\(lazy.screen)\n---\n\(eager.screen)")
    }

    /// A minimal-movement seek to a row below the screen brings it up to the
    /// bottom line; sought again, on screen now, it moves nothing.
    @Test("A minimal-movement seek moves the row just on screen, then nothing", arguments: Shape.allCases)
    func minimalSeek(_ shape: Shape) {
        let key = Self.target(shape)
        let app = Self.app(shape, lazy: true, anchor: nil)
        _ = app.press(.character("j"))
        #expect(
            Self.line(of: key, in: app) == Self.expectedLine(.bottom, height: Self.height(key)),
            "\(shape):\n\(app.screen)")
        let landed = Self.lines(app)
        _ = app.press(.character("j"))
        #expect(Self.lines(app) == landed, "\(shape): a second seek moved:\n\(app.screen)")
    }

    @Test("A key nothing holds moves nothing")
    func unknownKeyIsANoOp() {
        let app = Self.app(.nestedSmall, lazy: true, anchor: .top, key: "nowhere")
        let before = Self.lines(app)
        _ = app.press(.character("j"))
        #expect(Self.lines(app) == before)
    }

    /// The search measures the rows above the stack's; the stack's own rows
    /// are found by their keys, so the rows built for the seek's frame do not
    /// grow with the stack.
    @Test("A seek into a stack under a title builds the same rows at 1,000 and 10,000 rows")
    func seekBuildsAScreenful() {
        func built(rows: Int) -> Int {
            let builds = Builds()
            let app = TestApp(width: 30, height: 12) {
                SeekPage(key: rows / 2, anchor: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("title")
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<rows, id: \.self) { index in
                                builds.count += 1
                                return Text(verbatim: index.isMultiple(of: 3) ? "a\(index)\n  more" : "a\(index)")
                            }
                        }
                    }
                }
            }
            _ = app.screen
            builds.count = 0
            _ = app.press(.character("j"))
            #expect(app.screen.contains("a\(rows / 2)"), "\(app.screen)")
            return builds.count
        }
        let small = built(rows: 1_000)
        #expect(small < 100, "\(small)")
        #expect(built(rows: 10_000) == small)
    }

    /// `ScrollPosition.scrollTo(id:)` takes the same route.
    @Test("A bound ScrollPosition finds a row inside the rows of an outer lazy stack")
    func scrollPositionFindsANestedRow() {
        let box = PositionBox()
        let app = TestApp(width: 30, height: 12) { PositionPage(box: box) }
        _ = app.screen
        box.position.scrollTo(id: "g9r150", anchor: .top)
        _ = app.press(.character("x"))
        #expect(app.screen.lines.first?.hasPrefix("g9r150") == true, "\(app.screen)")
    }
}

@MainActor private final class PositionBox {
    var position = ScrollPosition()
}

/// Twelve groups of 300 rows in an outer lazy stack, the scroll view's
/// position bound.
private struct PositionPage: View {
    let box: PositionBox

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<12, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("group \(group)")
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach((0..<300).map { "g\(group)r\($0)" }, id: \.self) { Text($0) }
                        }
                    }
                }
            }
        }
        .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
    }
}
