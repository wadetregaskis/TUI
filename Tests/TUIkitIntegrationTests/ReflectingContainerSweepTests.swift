//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReflectingContainerSweepTests.swift
//
//  The semantic audit's root cause 5 (owner ruling RC5, 2026-10-23): the
//  containers that still sort their content by asking each child's type — a
//  `List`'s rows and sections, a `Grid`'s rows, a `Form`'s rows — find what
//  they recognise behind a modifier, behind `AnyView` and inside a view of the
//  app's own, as SwiftUI does, and drop nothing they do not recognise.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitTestSupport

/// A view of the app's own whose body is `content`.
private struct Own<Content: View>: View {
    let content: Content
    var body: some View { content }
}

/// The three ways content reaches a container hidden from its type: behind a
/// modifier, erased, and as the body of a view of the app's own.
enum Hiding: String, CaseIterable, Sendable {
    case modified, erased, appOwn

    @MainActor @ViewBuilder
    func hide(_ view: some View) -> some View {
        switch self {
        case .modified: view.padding(0)
        case .erased: AnyView(view)
        case .appOwn: Own(content: view)
        }
    }
}

@MainActor
@Suite("Reflecting containers find hidden content (RC5)")
struct ReflectingContainerSweepTests {
    private func lines(_ view: some View, width: Int = 40, height: Int = 14) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
    }

    // MARK: - List rows (ListRowExtractor)

    @Test("A list row hidden from its type is a row of its own", arguments: Hiding.allCases)
    func listRow(hiding: Hiding) {
        let drawn = lines(
            List {
                Text("first")
                hiding.hide(Text("hidden"))
                Text("last")
            })
        let first = drawn.firstIndex { $0.contains("first") }
        let hidden = drawn.firstIndex { $0.contains("hidden") }
        let last = drawn.firstIndex { $0.contains("last") }
        #expect(first != nil && hidden == first.map { $0 + 1 } && last == hidden.map { $0 + 1 }, "\(drawn)")
    }

    // MARK: - List sections (SectionRowExtractor)

    @Test("A list section hidden from its type keeps its header and its rows", arguments: Hiding.allCases)
    func listSection(hiding: Hiding) {
        let drawn = lines(
            List {
                hiding.hide(
                    Section("Header") {
                        Text("alpha")
                        Text("beta")
                    })
                Section("Other") { Text("gamma") }
            })
        let header = drawn.firstIndex { $0.contains("Header") }
        #expect(header != nil, "\(drawn)")
        #expect(drawn.firstIndex { $0.contains("alpha") } == header.map { $0 + 1 }, "a row of its own: \(drawn)")
        #expect(drawn.contains { $0.contains("beta") && !$0.contains("alpha") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("gamma") }, "\(drawn)")
    }

    // MARK: - Grid rows (GridRowProviding)

    @Test("A grid row hidden from its type lays its cells in the grid's columns", arguments: Hiding.allCases)
    func gridRow(hiding: Hiding) {
        let drawn = lines(
            Grid(horizontalSpacing: 1) {
                GridRow {
                    Text("wide-cell")
                    Text("x")
                }
                hiding.hide(
                    GridRow {
                        Text("a")
                        Text("y")
                    })
            })
        guard let top = drawn.first(where: { $0.contains("wide-cell") }),
            let row = drawn.first(where: { $0.contains("y") && !$0.contains("wide") }),
            let x = top.firstIndex(of: "x"), let y = row.firstIndex(of: "y")
        else {
            Issue.record("\(drawn)")
            return
        }
        #expect(top.distance(from: top.startIndex, to: x) == row.distance(from: row.startIndex, to: y), "\(drawn)")
    }

    @Test("A loop of hidden grid rows lays each in the grid's columns", arguments: Hiding.allCases)
    func gridLoopRows(hiding: Hiding) {
        let drawn = lines(
            Grid(horizontalSpacing: 1) {
                GridRow {
                    Text("wide-cell")
                    Text("x")
                }
                ForEach(["a", "b"], id: \.self) { name in
                    hiding.hide(
                        GridRow {
                            Text(name)
                            Text("y")
                        })
                }
            })
        guard let top = drawn.first(where: { $0.contains("wide-cell") }), let x = top.firstIndex(of: "x") else {
            Issue.record("\(drawn)")
            return
        }
        let rows = drawn.filter { $0.contains("y") }
        #expect(rows.count == 2, "\(drawn)")
        for row in rows {
            let y = row.firstIndex(of: "y").map { row.distance(from: row.startIndex, to: $0) }
            #expect(y == top.distance(from: top.startIndex, to: x), "\(drawn)")
        }
    }

    // MARK: - Form rows

    @Test("A form section hidden from its type keeps its header and its rows", arguments: Hiding.allCases)
    func formSection(hiding: Hiding) {
        let drawn = lines(
            Form {
                hiding.hide(
                    Section("Header") {
                        Text("alpha")
                        Text("beta")
                    })
            },
            height: 12)
        #expect(drawn.contains { $0.contains("Header") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("alpha") } && drawn.contains { $0.contains("beta") }, "\(drawn)")
        #expect(!drawn.contains { $0.contains("alpha") && $0.contains("beta") }, "rows of their own: \(drawn)")
    }

    @Test("A form row hidden from its type is drawn", arguments: Hiding.allCases)
    func formRow(hiding: Hiding) {
        let drawn = lines(
            Form {
                Toggle("first", isOn: .constant(true))
                hiding.hide(Toggle("hidden", isOn: .constant(false)))
                LabeledContent("last", value: "v")
            },
            height: 12)
        #expect(drawn.contains { $0.contains("first") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("hidden") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("last") }, "\(drawn)")
    }
}
