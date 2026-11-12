//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledColumnTests.swift
//
//  SCROLL-FIT's pull (design P2): a lazy stack that is not its scroll view's
//  direct content — under a title, two stacked, inside a `GroupBox`, in the
//  rows of an outer lazy stack — is pulled by the column that holds it, so it
//  builds only the rows on screen, whatever its row count, and every row is
//  still reached.
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
@Suite("SCROLL-FIT pull: lazy stacks anywhere in scroll content build only what is on screen")
struct PulledColumnTests {
    enum Shape: CaseIterable, Sendable {
        case titled, twoStacked, boxed, paddedTwoStacked
        /// The second stack of `twoStacked` in an `if` among the column's
        /// children, and in the first branch of an `if`/`else`.
        case conditional, ifElse
    }

    /// What the `if`s test, read at run time so the compiler keeps both
    /// branches.
    private static let shows = !CommandLine.arguments.isEmpty

    private static func rows(_ prefix: String, _ count: Int, builds: Builds) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                builds.count += 1
                return Text(index.isMultiple(of: 3) ? "\(prefix)\(index)\n  more" : "\(prefix)\(index)")
            }
        }
    }

    private static func app(_ shape: Shape, rows count: Int, builds: Builds) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                switch shape {
                case .titled:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("title")
                        rows("a", count, builds: builds)
                    }
                case .twoStacked:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("first")
                        rows("a", count, builds: builds)
                        Text("second")
                        rows("b", count, builds: builds)
                    }
                case .paddedTwoStacked:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("first")
                        rows("a", count, builds: builds).padding(.vertical, 1)
                        Text("second")
                        rows("b", count, builds: builds)
                    }
                case .boxed:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("title")
                        GroupBox { rows("a", count, builds: builds) }
                    }
                case .conditional:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("first")
                        rows("a", count, builds: builds)
                        Text("second")
                        if shows { rows("b", count, builds: builds) }
                    }
                case .ifElse:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("first")
                        rows("a", count, builds: builds)
                        Text("second")
                        if shows { rows("b", count, builds: builds) } else { Text("none") }
                    }
                }
            }
        }
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

    @Test("The rows built for a first frame and each page are the same at 1,000, 10,000 and 100,000 rows",
          arguments: [Shape.titled, .twoStacked, .conditional, .ifElse])
    func builtRowsIndependentOfRowCount(_ shape: Shape) {
        let small = Self.builtPerStep(shape, rows: 1_000)
        #expect(small.allSatisfy { $0 < 200 }, "\(shape): \(small)")
        #expect(Self.builtPerStep(shape, rows: 10_000) == small, "\(shape)")
        #expect(Self.builtPerStep(shape, rows: 100_000) == small, "\(shape)")
    }

    /// `count` rows as `rows` draws them, in an eager stack as wide as the
    /// lazy one: what the lazy one must draw.
    private static func eagerRows(_ prefix: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Text(index.isMultiple(of: 3) ? "\(prefix)\(index)\n  more" : "\(prefix)\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The `if` shapes drawn whole: both stacks eager.
    private static func eagerConditional(_ shape: Shape) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("first")
                    eagerRows("a", 400)
                    Text("second")
                    if shape == .twoStacked {
                        eagerRows("b", 400)
                    } else if shape == .conditional {
                        if shows { eagerRows("b", 400) }
                    } else {
                        if shows { eagerRows("b", 400) } else { Text("none") }
                    }
                }
            }
        }
    }

    /// A lazy stack in an `if` is reached from the column through the `if`'s
    /// branch, a step of the `if`'s own: pulled as the column's other
    /// children are, it draws what the same rows drawn whole draw.
    @Test("A lazy stack in an `if` among a column's children draws what the eager one draws",
          arguments: [Shape.twoStacked, .conditional, .ifElse])
    func conditionalDrawsWhatTheEagerOneDraws(_ shape: Shape) {
        let lazy = Self.app(shape, rows: 400, builds: Builds())
        let eager = Self.eagerConditional(shape)
        func content(_ app: TestApp) -> [String] {
            app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
        }
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
        for step in 1...30 {
            lazy.scroll(.up, at: CellPoint(x: 5, y: 5))
            eager.scroll(.up, at: CellPoint(x: 5, y: 5))
            check("up \(step)")
        }
    }

    @Test("Paging reaches every row of a stack under a title, in order, and Home brings the title back")
    func pagingUnderATitleReachesEveryRow() {
        let builds = Builds()
        let app = Self.app(.titled, rows: 400, builds: builds)
        var seen = Set<Int>()
        func collect() {
            for line in app.screen.lines {
                for match in line.matches(of: /a(\d+)/) { if let row = Int(match.1) { seen.insert(row) } }
            }
        }
        collect()
        for _ in 0..<80 {
            _ = app.press(.pageDown)
            collect()
        }
        let missing = (0..<400).filter { !seen.contains($0) }
        #expect(missing.isEmpty, "\(missing.count) rows never drawn: \(missing.prefix(10))")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(app.screen)")
    }

    @Test("Two stacked: End shows the second stack's last row, and the first's last row sits right above the second heading",
          arguments: [Shape.twoStacked, .conditional, .ifElse])
    func twoStackedMeetEdgeToEdge(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 400, builds: builds)
        _ = app.press(.end)
        #expect(app.screen.contains("b399"), "\(app.screen)")
        var met = false
        for _ in 0..<400 where !met {
            app.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            let lines = app.screen.lines
            if let heading = lines.firstIndex(where: { $0.hasPrefix("second") }), heading >= 2 {
                // a399 is a two-line row (399 is a multiple of 3): its second
                // line, then the heading.
                #expect(lines[heading - 2].hasPrefix("a399") && lines[heading - 1].contains("more"), "\(app.screen)")
                met = true
            }
        }
        #expect(met, "the second heading never came on screen above the second stack: \(app.screen)")
    }

    /// A padded stack is handed its request below the padding's top line,
    /// whatever the request counts from: entered from its end, as the fill
    /// comes up from the second heading, it counts from the end of the
    /// padding below the stack, not from the stack's own.
    @Test("A padded stack entered from below ends a padding line above the heading under it")
    func paddedStackEnteredFromBelow() {
        let builds = Builds()
        let app = Self.app(.paddedTwoStacked, rows: 400, builds: builds)
        _ = app.press(.end)
        var met = false
        for _ in 0..<400 where !met {
            app.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            let lines = app.screen.lines
            if let heading = lines.firstIndex(where: { $0.hasPrefix("second") }), heading >= 3 {
                #expect(
                    lines[heading - 3].hasPrefix("a399") && lines[heading - 2].contains("more")
                        && lines[heading - 1].allSatisfy { $0 == " " },
                    "\(app.screen)")
                met = true
            }
        }
        #expect(met, "the second heading never came on screen below the padded stack: \(app.screen)")
    }

    /// The padding above a pulled stack is drawn only while the stack's first
    /// row is: in the middle of the stack every line is a row.
    @Test("A padded stack paged into its middle draws no padding line among its rows")
    func paddedStackMiddleHasNoPaddingLine() {
        let builds = Builds()
        let app = Self.app(.paddedTwoStacked, rows: 400, builds: builds)
        for _ in 0..<6 { _ = app.press(.pageDown) }
        let lines = app.screen.lines
        let blank = lines.indices.filter { lines[$0].allSatisfy { $0 == " " } }
        #expect(blank.isEmpty, "blank lines at \(blank): \(app.screen)")
        #expect(lines.contains { $0.hasPrefix("a") }, "\(app.screen)")
    }

    /// A box hands its body the request below its top line
    /// (`ContainerViewCore+Pulled.swift`), so End reaches the stack's last
    /// row in it (`PulledContainersTests` counts the rows it builds).
    @Test("A lazy stack in a GroupBox is pulled through it: End shows its last row")
    func boxedStackReachesItsLastRow() {
        let builds = Builds()
        let app = Self.app(.boxed, rows: 400, builds: builds)
        _ = app.press(.end)
        #expect(app.screen.contains("a399"), "\(app.screen)")
    }

    /// Each section is priced by a sample of its stack, never walked: 506 or
    /// 746 rows a write frame (a rung of the scroll view's natural-extent
    /// ladder whose sample a pass's memo serves or not, by what ran before in
    /// the process), against 27,932 when nested stacks were drawn whole
    /// (design D). However tall: the outer stack answers the ladder with its
    /// whole estimate, which the ladder steps past in one rung, so no more
    /// than two rungs' samples at 320 sections or at 2,560. Capped at each
    /// rung, a taller estimate took a rung more and a sample more a step of
    /// eight: 986 rows at 320 sections.
    @Test("Lazy stacks in the rows of an outer one build no more a write frame at 320 and 2,560 sections than two rungs' samples")
    func groupedSectionsBuildAScreenful() {
        func builtOnWrite(sections: Int) -> Int {
            let builds = Builds()
            let app = TestApp(width: 30, height: 12) { GroupedSections(sections: sections, builds: builds) }
            _ = app.screen
            _ = app.press(.pageDown)
            builds.count = 0
            _ = app.press(.character("t"))
            #expect(app.screen.lines[0].hasPrefix("tick 1"), "precondition: the write landed: \(app.screen)")
            return builds.count
        }
        for sections in [40, 320, 2_560] {
            let built = builtOnWrite(sections: sections)
            #expect(built <= 760, "\(sections) sections: a write frame built \(built) rows")
        }
    }
}

/// Sections, each a heading over its own lazy stack, in an outer lazy stack
/// under a line that a key rewrites: a write above the scroll view every frame
/// the key is pressed, as `grouped-feed`'s clock is.
private struct GroupedSections: View {
    let sections: Int
    let builds: Builds
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("section \(section)")
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(0..<(300 + section), id: \.self) { index in
                                    builds.count += 1
                                    return Text("s\(section) r\(index)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onKeyEvent(.character("t")) { tick += 1 }
    }
}
