//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseCompositionView.swift
//
//  Builds a perf case's page: its composition over its rows, in its
//  container. Every string shown is the rows' own or written here verbatim:
//  a case adds nothing to a translation table (B-PERFCASE-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// A case's whole page: the composition in its container.
struct CasePage: View {
    let composition: CaseComposition
    let container: CaseContainer
    let rows: CaseRows

    var body: some View {
        // `page`: the scene's setting, if any, is `CaseHost`'s, not a view's.
        let content = CaseCompositionView(composition: composition.page, rows: rows)
        switch container {
        case .alone, .none:
            AnyView(content)
        case .title:
            AnyView(ScrollView { VStack(alignment: .leading, spacing: 0) { Text(verbatim: Self.title); content } })
        case .bottom:
            AnyView(ScrollView { content }.defaultScrollAnchor(.bottom))
        case .sheet:
            AnyView(Text(verbatim: Self.title).sheet(isPresented: .constant(true)) { content })
        case .fixed:
            AnyView(
                VStack(alignment: .leading, spacing: 0) { Text(verbatim: Self.title); content }
                    .fixedSize(horizontal: false, vertical: true))
        }
    }

    /// The line of title a container puts over the composition.
    static let title = "perf case"
}

/// A composition over the case's rows.
struct CaseCompositionView: View {
    let composition: CaseComposition
    let rows: CaseRows

    var body: some View {
        switch composition {
        case .leaf(let leaf):
            AnyView(CaseLeafView(leaf: leaf, rows: rows))
        case .tabs(let parts):
            AnyView(
                TabView(selection: Binding(get: { rows.tab }, set: { rows.tab = $0 })) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        Tab(part.description, value: index) { Self(composition: part, rows: rows) }
                    }
                })
        case .split(let first, let second):
            AnyView(
                HSplitView {
                    Self(composition: first, rows: rows)
                    Self(composition: second, rows: rows)
                })
        case .followsPointer(let page):
            // Never reached from `CasePage`, which draws `composition.page`:
            // the setting is the scene's (`CaseHost`).
            AnyView(Self(composition: page, rows: rows))
        case .adopted:
            // Built once by `CasePage.adopted(_:count:seed:)`, never here: a
            // scenario's `make` builds its model, and a body runs every frame.
            AnyView(Text(verbatim: "an adopted scenario cannot be a part"))
        }
    }
}

/// One leaf composition.
private struct CaseLeafView: View {
    let leaf: CaseLeaf
    let rows: CaseRows

    var body: some View {
        switch leaf {
        case .listPlain:
            AnyView(
                List(selection: selection) {
                    ForEach(rows.rows) { row in CaseListRow(title: rows.title(row), status: rows.status(row)) }
                })
        case .listSearch:
            AnyView(
                List(selection: selection) {
                    ForEach(rows.shown) { row in CaseListRow(title: rows.title(row), status: rows.status(row)) }
                }
                .searchable(text: Binding(get: { rows.query }, set: { rows.query = $0 })))
        case .tableFit5:
            AnyView(CaseTableView(rows: rows, wraps: false))
        case .tableWrap5:
            AnyView(CaseTableView(rows: rows, wraps: true))
        case .chatLazy:
            AnyView(
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.rows) { row in CaseMessage(text: rows.message(row), leading: row.id.isMultiple(of: 2)) }
                })
        case .chatEager:
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.rows) { row in CaseMessage(text: rows.message(row), leading: row.id.isMultiple(of: 2)) }
                })
        case .editorWrap:
            AnyView(TextEditor(text: Binding(get: { rows.document }, set: { rows.document = $0 })))
        case .outlineList, .outlineTable:
            // One arm for both, in a view of their own: an arm each nested the
            // switch's content a level deeper for every leaf, and moved the
            // other cases' measure-memo misses.
            AnyView(CaseOutlineView(asTable: leaf == .outlineTable, rows: rows))
        }
    }

    private var selection: Binding<Int?> { Binding(get: { rows.selection }, set: { rows.selection = $0 }) }
}

/// The case's rows as a tree (``CaseRows/tree``), in a selectable `List` or
/// in a `Table` of three columns.
private struct CaseOutlineView: View {
    let asTable: Bool
    let rows: CaseRows

    var body: some View {
        if asTable {
            Table(rows.tree, children: \.children, selection: selection) {
                TableColumn(CaseTableView.titles[4]) { (node: CaseRows.Node) in Text(verbatim: rows.title(node.row)) }
                TableColumn(CaseTableView.titles[2]) { (node: CaseRows.Node) in Text(verbatim: rows.status(node.row)) }
                TableColumn(CaseTableView.titles[3]) { (node: CaseRows.Node) in
                    Text(verbatim: "\(rows.size(node.row))")
                }
            }
        } else {
            List(rows.tree, children: \.children, selection: selection) { node in
                CaseListRow(title: rows.title(node.row), status: rows.status(node.row))
            }
        }
    }

    private var selection: Binding<Int?> { Binding(get: { rows.selection }, set: { rows.selection = $0 }) }
}

/// A list's row: its title, and its status at the trailing edge. `Equatable`,
/// so an unchanged row is served from the render cache, as an app's is.
private struct CaseListRow: View, Equatable {
    let title: String
    let status: String

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: status).foregroundStyle(.secondary)
        }
    }
}

/// A message: its lines, on one side or the other, as a conversation alternates.
private struct CaseMessage: View, Equatable {
    let text: String
    let leading: Bool

    var body: some View {
        Text(verbatim: text)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}

/// A five-column table of the rows: every column `.fit`, or the last wrapping.
private struct CaseTableView: View {
    let rows: CaseRows
    let wraps: Bool

    var body: some View {
        if wraps {
            Table(rows.rows, selection: selection) {
                TableColumn(Self.titles[0]) { (row: CaseRows.Row) in Text(verbatim: rows.name(row)) }
                TableColumn(Self.titles[1]) { (row: CaseRows.Row) in Text(verbatim: rows.slug(row)) }
                TableColumn(Self.titles[2]) { (row: CaseRows.Row) in Text(verbatim: rows.status(row)) }
                TableColumn(Self.titles[3]) { (row: CaseRows.Row) in Text(verbatim: "\(rows.size(row))") }
                TableColumn(Self.titles[4]) { (row: CaseRows.Row) in Text(verbatim: rows.message(row)) }
                    .lineLimit(3)
            }
        } else {
            Table(rows.rows, selection: selection) {
                TableColumn(Self.titles[0]) { (row: CaseRows.Row) in Text(verbatim: rows.name(row)) }.width(.fit)
                TableColumn(Self.titles[1]) { (row: CaseRows.Row) in Text(verbatim: rows.slug(row)) }.width(.fit)
                TableColumn(Self.titles[2]) { (row: CaseRows.Row) in Text(verbatim: rows.status(row)) }.width(.fit)
                TableColumn(Self.titles[3]) { (row: CaseRows.Row) in Text(verbatim: "\(rows.size(row))") }
                    .width(.fit)
                TableColumn(Self.titles[4]) { (row: CaseRows.Row) in Text(verbatim: rows.title(row)) }.width(.fit)
            }
        }
    }

    private var selection: Binding<Int?> { Binding(get: { rows.selection }, set: { rows.selection = $0 }) }

    /// Column titles, as strings rather than literals: a literal is a
    /// localization key, and a case adds none.
    static let titles = ["Name", "Slug", "Status", "Size", "Title"]
}

extension CasePage {
    /// An adopted scenario's page, built as `--bench` builds it — once, with
    /// the clock its pages read — or `nil` for a scenario or variant `Stress`
    /// does not have.
    @MainActor
    static func adopted(scenario: String, variant: String?, scale: Int, seed: UInt64) -> AnyView? {
        guard let found = Scenarios.byID(scenario) else { return nil }
        if let variant, !ScenarioVariants.variants(of: scenario).contains(where: { $0.id == variant }) { return nil }
        var config = StressConfig()
        config.scale = scale
        config.seed = seed
        config.variant = variant
        let built = found.drive?(config)?.view ?? found.make(config)
        return AnyView(built.environment(StressClock()))
    }
}
