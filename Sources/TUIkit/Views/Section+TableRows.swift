//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Section+TableRows.swift
//
//  `Section` among a table's rows: a header row — a view across the table —
//  above the section's rows, and `TableHeaderRowContent`, the row a section's
//  header is.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - The header row

/// A section's header, as a table's rows carry it: the view, and the row it is
/// drawn above.
struct _TableSectionHeader {
    /// The header, as drawn — behind a disclosure triangle for a collapsible
    /// section (`_SectionHeader`).
    let view: AnyView

    /// How many of the table's rows come before it: it is drawn above the row
    /// at this index, or below the last row when it equals their count.
    var beforeRow: Int
}

/// Where a table's section headers fall among its rows: drawn with the row
/// below them, or — after the last row — with that row, below it.
///
/// A header is not an entry of its own in the table's numbering. Every path
/// through a table counts its rows by their index into the data — the window,
/// the cursor, the selection, the hit bands — and a header carried as lines of
/// the row it precedes leaves all of them counting rows: the cursor steps over
/// it because it is not a row, the selection cannot hold it for the same
/// reason, and the "N more rows" indicators count rows only. What it changes is
/// a row's height, which the multi-line layout already takes row by row.
struct _TableSectionLayout {
    /// The headers drawn above each row that has any, by row index.
    private let above: [Int: [Int]]

    /// The headers drawn below the last row: a section with no rows at the end.
    private let below: [Int]

    /// The last row's index.
    private let lastRow: Int

    /// Places `headers` among `rowCount` rows.
    init(_ headers: [_TableSectionHeader], rowCount: Int) {
        var above: [Int: [Int]] = [:]
        var below: [Int] = []
        for (index, header) in headers.enumerated() {
            if header.beforeRow < rowCount {
                above[header.beforeRow, default: []].append(index)
            } else {
                below.append(index)
            }
        }
        self.above = above
        self.below = below
        self.lastRow = rowCount - 1
    }

    /// The headers drawn above row `index`, in order.
    func headers(above index: Int) -> [Int] { above[index] ?? [] }

    /// The headers drawn below row `index`: those after the last row.
    func headers(below index: Int) -> [Int] { index == lastRow ? below : [] }
}

/// A table row that displays a single view instead of columned content.
///
/// You do not create this type directly: a ``Section`` among a table's rows
/// makes one of its header.
public struct TableHeaderRowContent<Value: Identifiable, Content: View>: TableRowContent {
    public typealias TableRowValue = Value

    /// The header's view.
    let content: Content

    /// The type of the header's body: no rows.
    ///
    /// Spelled out where SwiftUI's is opaque: SwiftUI declares the alias, and
    /// an opaque body here would declare none (as for `TableForEachContent`).
    public typealias TableRowBody = EmptyTableRowContent<Value>

    /// Never asked for its rows: the header hands itself to the table, as a
    /// row's view across the table's width. An empty body, so that what it is
    /// says nothing a table could draw twice.
    public var tableRowBody: EmptyTableRowContent<Value> { EmptyTableRowContent() }
}

extension TableHeaderRowContent {
    /// Appends the header row.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Value>) {
        rows.appendSectionHeader(AnyView(_SectionHeader(header: content.content, isExpanded: nil)))
    }
}

// MARK: - Section as table rows

extension Section: _TableRowValued
where
    Parent: TableRowContent, Content: TableRowContent, Footer: TableRowContent,
    Parent.TableRowValue == Content.TableRowValue, Footer.TableRowValue == Content.TableRowValue
{
    public typealias TableRowValue = Content.TableRowValue
}

extension Section: TableRowContent
where
    Parent: TableRowContent, Content: TableRowContent, Footer: TableRowContent,
    Parent.TableRowValue == Content.TableRowValue, Footer.TableRowValue == Content.TableRowValue
{
    public typealias TableRowBody = Never

    /// Never called: a section hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("Section renders its rows directly") }
}

extension Section
where
    Parent: TableRowContent, Content: TableRowContent, Footer: TableRowContent,
    Parent.TableRowValue == Content.TableRowValue, Footer.TableRowValue == Content.TableRowValue
{
    /// Appends the section: its header row, then its rows — none while a
    /// collapsible section is collapsed, its header staying, as SwiftUI's
    /// table draws it (measured on macOS 15.8).
    @MainActor
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Content.TableRowValue>) {
        if let header = content.header as? any _TableSectionHeaderView {
            rows.appendSectionHeader(header.sectionHeader(isExpanded: content.isExpanded))
        } else {
            appendTableRows(content.header, to: &rows)
        }
        if content.showsContent { appendTableRows(content.content, to: &rows) }
        appendTableRows(content.footer, to: &rows)
    }
}

/// A header row that can be drawn behind a section's disclosure triangle.
@MainActor
protocol _TableSectionHeaderView {
    /// The header as a section draws it: behind a disclosure triangle when the
    /// section is collapsible.
    func sectionHeader(isExpanded: Binding<Bool>?) -> AnyView
}

extension TableHeaderRowContent: _TableSectionHeaderView {
    func sectionHeader(isExpanded: Binding<Bool>?) -> AnyView {
        AnyView(_SectionHeader(header: content, isExpanded: isExpanded))
    }
}

// MARK: - Initializers

extension Section where Content: TableRowContent {
    /// Creates a section of table rows with a localized title as its header.
    ///
    /// The header is a row of its own across the table, above the section's
    /// rows, drawn as a `List` draws a section's header; the cursor steps over
    /// it and nothing selects it.
    ///
    /// ```swift
    /// Table(of: Person.self) {
    ///     TableColumn("Name", value: \.name)
    /// } rows: {
    ///     Section("Team") {
    ///         ForEach(team) { TableRow($0) }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - titleKey: The key for the header's text.
    ///   - content: The section's rows.
    public init<V>(_ titleKey: LocalizedStringKey, @TableRowBuilder<V> content: () -> Content)
    where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: Text(titleKey)), content: content(),
            footer: EmptyTableRowContent(), isExpanded: nil)
    }

    /// Creates a section of table rows with a title, shown as written, as its
    /// header.
    ///
    /// - Parameters:
    ///   - title: The header's text.
    ///   - content: The section's rows.
    @_disfavoredOverload
    public init<V, S: StringProtocol>(_ title: S, @TableRowBuilder<V> content: () -> Content)
    where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: Text(String(title))), content: content(),
            footer: EmptyTableRowContent(), isExpanded: nil)
    }

    /// Creates a collapsible section of table rows with a localized title as
    /// its header.
    ///
    /// The header carries a disclosure triangle — `▼` while the rows show, `▶`
    /// while they do not — and is a control of its own: a Tab stop that Return
    /// or Space toggles, Right opens and Left closes, and a click toggles, as a
    /// collapsible section's header in a `List` is. A collapsed section's rows
    /// leave the table; its header stays.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the header's text.
    ///   - isExpanded: A binding to whether the section's rows show.
    ///   - content: The section's rows.
    public init<V>(
        _ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @TableRowBuilder<V> content: () -> Content
    ) where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: Text(titleKey)), content: content(),
            footer: EmptyTableRowContent(), isExpanded: isExpanded)
    }

    /// Creates a collapsible section of table rows with a title, shown as
    /// written, as its header.
    ///
    /// - Parameters:
    ///   - title: The header's text.
    ///   - isExpanded: A binding to whether the section's rows show.
    ///   - content: The section's rows.
    @_disfavoredOverload
    public init<V, S: StringProtocol>(
        _ title: S, isExpanded: Binding<Bool>, @TableRowBuilder<V> content: () -> Content
    ) where Parent == TableHeaderRowContent<V, Text>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: Text(String(title))), content: content(),
            footer: EmptyTableRowContent(), isExpanded: isExpanded)
    }

    /// Creates a section of table rows with no header: its rows among the
    /// table's, as a group of rows.
    ///
    /// - Parameter content: The section's rows.
    public init<V>(@TableRowBuilder<V> content: () -> Content)
    where Parent == EmptyTableRowContent<V>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: EmptyTableRowContent(), content: content(), footer: EmptyTableRowContent(),
            isExpanded: nil)
    }

    /// Creates a section of table rows with a view as its header.
    ///
    /// - Parameters:
    ///   - content: The section's rows.
    ///   - header: The header's view, drawn across the table.
    public init<V, H: View>(@TableRowBuilder<V> content: () -> Content, @ViewBuilder header: () -> H)
    where Parent == TableHeaderRowContent<V, H>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: header()), content: content(),
            footer: EmptyTableRowContent(), isExpanded: nil)
    }

    /// Creates a collapsible section of table rows with a view as its header.
    ///
    /// - Parameters:
    ///   - isExpanded: A binding to whether the section's rows show.
    ///   - content: The section's rows.
    ///   - header: The header's view, drawn across the table behind a
    ///     disclosure triangle.
    public init<V, H: View>(
        isExpanded: Binding<Bool>, @TableRowBuilder<V> content: () -> Content, @ViewBuilder header: () -> H
    ) where Parent == TableHeaderRowContent<V, H>, Footer == EmptyTableRowContent<V>, V == Content.TableRowValue {
        self.init(
            header: TableHeaderRowContent(content: header()), content: content(),
            footer: EmptyTableRowContent(), isExpanded: isExpanded)
    }
}
