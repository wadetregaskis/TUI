//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledContainersTests.swift
//
//  SCROLL-FIT's pull through the containers other than a column (design
//  B-SCROLLFIT-12's parallel and forward shapes): a lazy stack under a
//  bordered box, beside a label in an `HStack`, in a `ZStack`, under a
//  background or an overlay, in a `TabView` or a `NavigationStack`, below a
//  title in scroll content, builds only the rows on screen whatever its row
//  count, and every row is still reached.
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

@MainActor
@Suite("SCROLL-FIT pull: lazy stacks below every container build only what is on screen")
struct PulledContainersTests {
    enum Shape: String, CaseIterable, Sendable {
        case border, groupBox, background, overlay, hStack, zStack, tabView, navigationStack
        /// A row whose gutter an explicit guide moves down, a row whose gutter
        /// overlaps the stack and is drawn over it by its z-index, a z-stack
        /// whose badge a guide moves down: what the eager containers draw
        /// differently from their plain layout, which a pulled one must too.
        case hStackGuided, hStackZIndex, zStackGuided
        /// An overlay and a background that are views placed at an edge, laid
        /// out against the whole stack: the badge under its last row, the
        /// mark beside its first.
        case overlayView, backgroundView

        /// The shapes that pull: every one but `TabView`, whose strip the
        /// request is not yet moved below (SCROLL-FIT design, "Still to do").
        static let pulled = allCases.filter { $0 != .tabView }
    }

    private static func rows(_ count: Int, builds: Builds) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                builds.count += 1
                return Text(index.isMultiple(of: 3) ? "a\(index)\n  more" : "a\(index)")
            }
        }
    }

    /// The same rows in an eager `VStack`, filling its width as a
    /// `LazyVStack` does (SwiftUI's is flexible across; an eager one hugs its
    /// widest row): what the lazy stack must draw.
    private static func eagerRows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Text(index.isMultiple(of: 3) ? "a\(index)\n  more" : "a\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func wrapped(_ shape: Shape, rows count: Int, builds: Builds) -> some View {
        wrapped(shape) { rows(count, builds: builds) }
    }

    @ViewBuilder
    private static func wrapped<Rows: View>(_ shape: Shape, _ rows: () -> Rows) -> some View {
        switch shape {
        case .border: rows().border()
        case .groupBox: GroupBox { rows() }
        case .background: rows().background(Color.blue)
        case .overlay: rows().overlay(alignment: .topTrailing) { Text("*") }
        case .overlayView: rows().overlay(alignment: .bottomTrailing) { Text("e*\n n*\n d*") }
        case .backgroundView: rows().background(alignment: .topTrailing) { Text("~t\n o\n p") }
        case .hStack:
            HStack(alignment: .top, spacing: 1) {
                Text("|")
                rows()
            }
        case .zStack:
            ZStack(alignment: .topLeading) {
                Color.clear
                rows()
            }
        case .tabView: TabView { Tab("One", systemImage: "a.circle") { rows() } }
        case .navigationStack: NavigationStack { rows() }
        case .hStackGuided:
            HStack(alignment: .top, spacing: 1) {
                Text("|\n|").alignmentGuide(.top) { _ in -2 }
                rows()
            }
        case .hStackZIndex:
            // The rows' leading padding lies under the badge before them,
            // which its z-index draws over the rows that come after it.
            HStack(alignment: .top, spacing: -1) {
                Text("#").zIndex(1)
                rows().padding(.leading, 1)
            }
        case .zStackGuided:
            ZStack(alignment: .topLeading) {
                rows()
                Text("*").alignmentGuide(.top) { _ in -2 }.alignmentGuide(.leading) { _ in -5 }
            }
        }
    }

    private static func app(_ shape: Shape, rows count: Int, builds: Builds) -> TestApp {
        page { wrapped(shape, rows: count, builds: builds) }
    }

    private static func page<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    content()
                    Text("footer")
                }
            }
        }
    }

    /// The pulled container draws what the same rows drawn eagerly draw,
    /// line for line but the scrollbar's column: the thumb reads the lazy
    /// stack's estimated height (rows of two lines every third, priced by a
    /// sample), the eager stack's exact one.
    @Test("A pulled container draws what the eager one draws, at the top, paged and at the end",
          arguments: Shape.pulled)
    func drawsWhatTheEagerOneDraws(_ shape: Shape) {
        let lazy = Self.app(shape, rows: 300, builds: Builds())
        let eager = Self.page { Self.wrapped(shape) { Self.eagerRows(300) } }
        func content(_ app: TestApp) -> [String] { app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) } }
        func check(_ step: String) {
            #expect(content(lazy) == content(eager), "\(shape) \(step):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
        check("top")
        for page in 1...3 {
            _ = lazy.press(.pageDown)
            _ = eager.press(.pageDown)
            check("page \(page)")
        }
        _ = lazy.press(.end)
        _ = eager.press(.end)
        check("end")
    }

    /// The rows built on the first frame and on each of five page-downs.
    private static func builtPerStep(_ shape: Shape, rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(shape, rows: rows, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<5 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    @Test("The rows built for a first frame and each page are the same at 1,000 and 10,000 rows",
          arguments: Shape.pulled)
    func builtRowsIndependentOfRowCount(_ shape: Shape) {
        let small = Self.builtPerStep(shape, rows: 1_000)
        #expect(small.allSatisfy { $0 < 300 }, "\(shape): \(small)")
        #expect(Self.builtPerStep(shape, rows: 10_000) == small, "\(shape)")
    }

    @Test("End shows the last row and the footer below the container; Home brings the title back",
          arguments: Shape.pulled)
    func endReachesTheLastRow(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 400, builds: builds)
        _ = app.press(.end)
        #expect(app.screen.contains("a399"), "\(shape): \(app.screen)")
        #expect(app.screen.contains("footer"), "\(shape): \(app.screen)")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(shape): \(app.screen)")
    }

    /// A box's band holds its bottom line only with the last row, and the
    /// request reaches the stack counted from the box's end above that line:
    /// at End the last row sits right on the bottom line, the footer right
    /// below; unboxed, right above the footer.
    @Test("At the end, the last row sits right above the footer, or on a box's bottom line", arguments: Shape.pulled)
    func lastRowMeetsTheFooter(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 400, builds: builds)
        _ = app.press(.end)
        let lines = app.screen.lines
        guard let footer = lines.firstIndex(where: { $0.hasPrefix("footer") }), footer >= 3 else {
            Issue.record("\(shape): no footer below the stack: \(app.screen)")
            return
        }
        let boxed = shape == .border || shape == .groupBox
        let last = boxed ? footer - 2 : footer - 1
        if boxed {
            let bottom = lines[footer - 1].trimmingCharacters(in: .whitespaces)
            #expect(bottom.hasPrefix("└") || bottom.hasPrefix("╰"), "\(shape): \(app.screen)")
        }
        #expect(lines[last].contains("more") && lines[last - 1].contains("a399"), "\(shape): \(app.screen)")
    }

    /// A gutter leaving a row under an animation glides out in a pulled row as
    /// in the eager one: mid-way, both draw the same frame.
    @Test("A row's child leaving under an animation is drawn mid-glide as the eager row draws it")
    func glidingGutterMatchesTheEagerRow() {
        let lazy = TestApp(width: 30, height: 12) { GlidingRow(eager: false) }
        let eager = TestApp(width: 30, height: 12) { GlidingRow(eager: true) }
        func content(_ app: TestApp) -> [String] {
            app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
        }
        #expect(content(lazy) == content(eager), "before:\n\(lazy.screen)\n---\n\(eager.screen)")
        _ = lazy.press(.character("g"))
        _ = eager.press(.character("g"))
        for step in 1...3 {
            lazy.advance(by: .milliseconds(100))
            eager.advance(by: .milliseconds(100))
            #expect(content(lazy) == content(eager), "step \(step):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
    }

    /// Entered from below — the fill coming up from a heading under the
    /// container, the stack in it handed a request counted from the
    /// container's end — the last row still sits right above the heading, or
    /// on a box's bottom line above it.
    @Test("A wrapped stack entered from below ends right above the next heading", arguments: Shape.pulled)
    func wrappedStackEnteredFromBelow(_ shape: Shape) {
        let builds = Builds()
        let app = TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("first")
                    Self.wrapped(shape, rows: 400, builds: builds)
                    Text("second")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<400, id: \.self) { Text("b\($0)") }
                    }
                }
            }
        }
        _ = app.press(.end)
        #expect(app.screen.contains("b399"), "\(shape): \(app.screen)")
        let boxed = shape == .border || shape == .groupBox
        var met = false
        for _ in 0..<400 where !met {
            app.scroll(.up, by: 1, at: CellPoint(x: 5, y: 5))
            let lines = app.screen.lines
            if let heading = lines.firstIndex(where: { $0.hasPrefix("second") }), heading >= 3 {
                let last = boxed ? heading - 2 : heading - 1
                if boxed {
                    let bottom = lines[heading - 1].trimmingCharacters(in: .whitespaces)
                    #expect(bottom.hasPrefix("└") || bottom.hasPrefix("╰"), "\(shape): \(app.screen)")
                }
                #expect(lines[last].contains("more") && lines[last - 1].contains("a399"), "\(shape): \(app.screen)")
                met = true
            }
        }
        #expect(met, "\(shape): the second heading never came on screen below the stack: \(app.screen)")
    }

    @Test("Paging reaches every row, in order", arguments: Shape.pulled)
    func pagingReachesEveryRow(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 300, builds: builds)
        var seen = Set<Int>()
        func collect() {
            for line in app.screen.lines {
                for match in line.matches(of: /a(\d+)/) { if let row = Int(match.1) { seen.insert(row) } }
            }
        }
        collect()
        for _ in 0..<60 {
            _ = app.press(.pageDown)
            collect()
        }
        let missing = (0..<300).filter { !seen.contains($0) }
        #expect(missing.isEmpty, "\(shape): \(missing.count) rows never drawn: \(missing.prefix(10))")
    }
}

/// A gutter beside 300 rows that leaves under an animation when `g` is
/// pressed, the rows lazy or eager.
private struct GlidingRow: View {
    let eager: Bool
    @State private var showsGutter = true

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 1) {
                if showsGutter { Text("|\n|") }
                if eager {
                    VStack(alignment: .leading, spacing: 0) { ForEach(0..<300, id: \.self) { Text("a\($0)") } }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<300, id: \.self) { Text("a\($0)") } }
                }
            }
        }
        .onKeyEvent(.character("g")) { withAnimation(.linear(duration: 0.5)) { showsGutter = false } }
    }
}
