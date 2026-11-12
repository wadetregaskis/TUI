//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollFitBaselineSupport.swift
//
//  The views and situations `ScrollFitBaselineTests` measures: every view
//  whose height (or width) depends on its content, and the space-fillers,
//  each placed where its parent leaves an axis unbounded.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUI
import TUITesting
@testable import TUITestSupport

/// Counts row bodies built and records the size each tagged view came out at.
@MainActor final class ScrollFitProbe {
    var sizes: [String: CellSize] = [:]
    var built = 0
}

struct ScrollFitItem: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    var children: [Self]? { nil }
}

/// The views measured. Their content is `rows` items labelled `"<prefix><n>"`.
enum ScrollFitSubject: String, CaseIterable, Sendable {
    case table, listPlain, listSectioned, listOutline, formGrouped, formColumns, textEditor
    case scrollSameAxis, scrollCrossAxis, lazyVStack, lazyHStack, tabView, navigationStack
    case navigationSplitView, hSplitView, vSplitView, groupBox, disclosureGroup, grid, flowLayout
    case imageResizable, imageAspectFit, spacer, color, rectangle, geometryReader, divider, maxHeightText

    /// The space-fillers and pictures: no rows of their own.
    var hasRows: Bool {
        switch self {
        case .imageResizable, .imageAspectFit, .spacer, .color, .rectangle, .geometryReader, .divider,
            .maxHeightText:
            false
        default: true
        }
    }
}

enum ScrollFitSituation: String, CaseIterable, Sendable {
    /// `ScrollView { view }`
    case alone
    /// `ScrollView { VStack { Text("title"); view } }`
    case underTitle
    /// `ScrollView { VStack { view; view } }`
    case twoStacked
    /// `VStack { Text("title"); view }.fixedSize(horizontal: false, vertical: true)`
    case fixedSize
    /// `ScrollView(.horizontal) { view }`
    case horizontal
}

@MainActor
enum ScrollFitCatalogue {
    static func items(_ prefix: String, _ rows: Int) -> [ScrollFitItem] {
        (1...max(1, rows)).map { ScrollFitItem(id: $0, label: "\(prefix)\($0)") }
    }

    /// One picture for every image case, 40 × 20 pixels.
    static let picture: BitmapFixture? = try? BitmapFixture(width: 40, height: 20)

    static func subject(
        _ subject: ScrollFitSubject, prefix: String, rows: Int, probe: ScrollFitProbe, tag: String
    ) -> some View {
        content(subject, prefix: prefix, rows: rows, probe: probe)
            .onGeometryChange(for: CellSize.self, of: { $0.size }, action: { probe.sizes[tag] = $0 })
    }

    static func root(
        _ subject: ScrollFitSubject, _ situation: ScrollFitSituation, rows: Int, probe: ScrollFitProbe
    ) -> AnyView {
        let first = Self.subject(subject, prefix: "Row ", rows: rows, probe: probe, tag: "a")
        switch situation {
        case .alone:
            return AnyView(ScrollView { first })
        case .underTitle:
            return AnyView(ScrollView { VStack { Text("title"); first } })
        case .twoStacked:
            let second = Self.subject(subject, prefix: "Alt ", rows: rows, probe: probe, tag: "b")
            return AnyView(ScrollView { VStack { first; second } })
        case .fixedSize:
            return AnyView(VStack { Text("title"); first }.fixedSize(horizontal: false, vertical: true))
        case .horizontal:
            return AnyView(ScrollView(.horizontal) { first })
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func content(
        _ subject: ScrollFitSubject, prefix: String, rows: Int, probe: ScrollFitProbe
    ) -> AnyView {
        let data = items(prefix, rows)
        let row = { (item: ScrollFitItem) -> Text in
            probe.built += 1
            return Text(item.label)
        }
        let column = VStack(alignment: .leading, spacing: 0) { ForEach(data) { row($0) } }
        switch subject {
        case .table:
            return AnyView(Table(data) { TableColumn("Name") { (item: ScrollFitItem) in row(item) } })
        case .listPlain:
            return AnyView(List { ForEach(data) { row($0) } })
        case .listSectioned:
            let half = data.count / 2
            return AnyView(
                List {
                    Section("First") { ForEach(data[..<half]) { row($0) } }
                    Section("Second") { ForEach(data[half...]) { row($0) } }
                })
        case .listOutline:
            return AnyView(List(data, children: \.children) { row($0) })
        case .formGrouped:
            return AnyView(Form { ForEach(data) { row($0) } }.formStyle(.grouped))
        case .formColumns:
            return AnyView(Form { ForEach(data) { row($0) } }.formStyle(.columns))
        case .textEditor:
            return AnyView(TextEditor(text: .constant(data.map(\.label).joined(separator: "\n"))))
        case .scrollSameAxis:
            return AnyView(ScrollView { column })
        case .scrollCrossAxis:
            return AnyView(ScrollView(.horizontal) { column })
        case .lazyVStack:
            return AnyView(LazyVStack(alignment: .leading, spacing: 0) { ForEach(data) { row($0) } })
        case .lazyHStack:
            return AnyView(LazyHStack(spacing: 1) { ForEach(data) { row($0) } })
        case .tabView:
            return AnyView(TabView { Tab("One", systemImage: "a.circle") { column } })
        case .navigationStack:
            return AnyView(NavigationStack { column })
        case .navigationSplitView:
            return AnyView(NavigationSplitView { column } detail: { Text("detail") })
        case .hSplitView:
            return AnyView(HSplitView { column; Text("right") })
        case .vSplitView:
            return AnyView(VSplitView { column; Text("bottom") })
        case .groupBox:
            return AnyView(GroupBox("Box") { column })
        case .disclosureGroup:
            return AnyView(DisclosureGroup("More", isExpanded: .constant(true)) { column })
        case .grid:
            return AnyView(Grid { ForEach(data) { item in GridRow { row(item); Text("cell") } } })
        case .flowLayout:
            return AnyView(FlowLayout(spacing: 1) { ForEach(data) { row($0) } })
        case .imageResizable:
            return AnyView(Image(.file(picture?.path ?? "/missing.bmp")).resizable())
        case .imageAspectFit:
            return AnyView(Image(.file(picture?.path ?? "/missing.bmp")).resizable().scaledToFit())
        case .spacer:
            return AnyView(Spacer())
        case .color:
            return AnyView(Color.blue)
        case .rectangle:
            return AnyView(Rectangle())
        case .geometryReader:
            return AnyView(GeometryReader { proxy in Text("geo \(proxy.size.width)x\(proxy.size.height)") })
        case .divider:
            return AnyView(Divider())
        case .maxHeightText:
            return AnyView(Text("tall").frame(maxHeight: .infinity))
        }
    }
}

/// One measurement: what a view got and showed in one situation.
struct ScrollFitResult: CustomStringConvertible {
    var sizeA: CellSize?
    var sizeB: CellSize?
    /// Row bodies built for the first frame.
    var builtFirst: Int
    /// Row bodies built for a one-tick wheel step.
    var builtStep: Int
    /// The last row of each copy came on screen while the wheel turned, five ticks at a time.
    var reachedA: Bool
    var reachedB: Bool
    /// The first wheel tick moved the screen's first line.
    var firstTickMovedPage: Bool
    /// Lines of the first screen showing no letter or digit.
    var blankLines: Int
    /// An indicator glyph (▲ ▼) drawn left of the screen's last column: a bar of the view's own.
    var innerIndicator: Bool
    var screen: String

    var description: String {
        func size(_ s: CellSize?) -> String { s.map { "\($0.width)x\($0.height)" } ?? "-" }
        return "a=\(size(sizeA)) b=\(size(sizeB)) built=\(builtFirst)/\(builtStep) "
            + "reach=\(reachedA ? "Y" : "n")\(reachedB ? "Y" : "n") pageMoved=\(firstTickMovedPage ? "Y" : "n") "
            + "blank=\(blankLines) innerBar=\(innerIndicator ? "Y" : "n")"
    }
}

@MainActor
enum ScrollFitMeasure {
    static func measure(
        _ subject: ScrollFitSubject, _ situation: ScrollFitSituation, rows: Int,
        width: Int = 60, height: Int = 24, walk: Bool = true, burst: Int = 5
    ) -> ScrollFitResult {
        let probe = ScrollFitProbe()
        let app = TestApp(width: width, height: height) {
            ScrollFitCatalogue.root(subject, situation, rows: rows, probe: probe)
                .environment(\.scrollChainingDelay, .zero)
        }
        let first = app.screen
        let builtFirst = probe.built
        let lastA = "Row \(rows)"
        let lastB = "Alt \(rows)"
        var reachedA = first.contains(lastA)
        var reachedB = first.contains(lastB)
        let blankLines = first.lines.count { line in !line.contains { $0.isLetter || $0.isNumber } }
        let innerIndicator = first.lines.contains { line in
            line.dropLast().contains { $0 == "▲" || $0 == "▼" }
        }
        let centre = CellPoint(x: width / 2, y: height / 2)
        probe.built = 0
        app.scroll(.down, by: 1, at: centre)
        let builtStep = probe.built
        let stepped = app.screen
        let firstTickMovedPage = stepped.lines.first != first.lines.first
        reachedA = reachedA || stepped.contains(lastA)
        reachedB = reachedB || stepped.contains(lastB)
        var previous = stepped.text
        var unchanged = 0
        for _ in 0..<(walk ? 3_000 : 0) where !(reachedA && (reachedB || situation != .twoStacked)) {
            app.scroll(.down, by: burst, at: centre)
            let screen = app.screen
            reachedA = reachedA || screen.contains(lastA)
            reachedB = reachedB || screen.contains(lastB)
            unchanged = screen.text == previous ? unchanged + 1 : 0
            if unchanged >= 2 { break }
            previous = screen.text
        }
        return ScrollFitResult(
            sizeA: probe.sizes["a"], sizeB: probe.sizes["b"], builtFirst: builtFirst, builtStep: builtStep,
            reachedA: reachedA, reachedB: reachedB, firstTickMovedPage: firstTickMovedPage,
            blankLines: blankLines, innerIndicator: innerIndicator, screen: first.text)
    }
}

/// A selection the key tests can read back.
@MainActor final class ScrollFitSelection { var value: Int? }
