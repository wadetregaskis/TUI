//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumn.swift
//
//  Created by LAYERED.work
//  License: MIT

// `KeyPathComparator` / `SortOrder` are Foundation's, not SwiftUI's — the same
// modern-Foundation generation as the `FormatStyle` `Text(_:format:)` already
// depends on, and present on every platform TUIkit builds for.
import Foundation

// MARK: - Column Width

/// Defines the width behavior for a table column.
public enum ColumnWidth: Sendable, Equatable {
    /// Fixed width in characters.
    case fixed(Int)

    /// Flexible width that expands to fill available space.
    /// Multiple flexible columns share space equally.
    case flexible

    /// Proportional width as a ratio of total available space.
    /// For example, `.ratio(0.5)` takes 50% of available width.
    case ratio(Double)

    /// Sizes the column to fit its content — the width of the widest of the
    /// column header and every cell value in the column (so nothing in the
    /// column is truncated, space permitting). This mirrors the content-based
    /// sizing of a SwiftUI table's automatic columns.
    ///
    /// It scans all of the column's values to find that width, so it is O(rows);
    /// for very large tables where a per-frame content scan is undesirable,
    /// prefer `.fixed` or `.flexible`. The fitted width is stable as the table
    /// scrolls (it considers every row, not just the visible ones), so the
    /// columns do not jump while scrolling.
    case fit
}

// MARK: - Table Column

/// A column that displays a view for each row in a table.
///
/// You create a column with a label, content view, and optional key path. The
/// table calls the content view builder with the value for each row in the
/// table. The column uses a key path to map to a property of each row value,
/// which sortable tables use to reflect the current sort order.
///
/// ```swift
/// Table(people, selection: $selection, sortOrder: $sortOrder) {
///     TableColumn("Given name", value: \.givenName) { person in
///         Text(person.givenName)
///     }
///     TableColumn("Family name", value: \.familyName)
///     TableColumn("Age") { Text("\($0.age)") }
///         .width(.fixed(5))
///         .alignment(.numeric)
/// }
/// ```
///
/// For the common case of `String` properties, the convenience initializer
/// that takes no content closure displays the string verbatim, exactly as a
/// ``Text`` would. It is also the fastest column there is: its cells are a pure
/// function of the row, so a table whose every column is one can keep its rows
/// across frames (see ``Table``).
///
/// ## Sorting
///
/// `Sort` is the comparator a click on the column's header puts at the head of
/// the table's `sortOrder` — `Never` for a column that cannot sort. As in
/// SwiftUI, which initializer you call decides it: `value:` with a
/// `Comparable` key path (and an optional `comparator:`) sorts by that
/// property, `sortUsing:` sorts with the comparator you give, and a column
/// with only a content closure cannot sort.
///
/// ## Cells
///
/// A cell is one line, like a row of text in a terminal table, unless the
/// column's ``lineLimit(_:)`` allows more: a `Text` cell then wraps, and any
/// other view is given that many lines. A plain `Text` — no styling of its own
/// — is drawn exactly as the `String` key-path column draws its value. Any
/// other content is rendered as a view at the column's width.
///
/// ## Width Modes
///
/// | Mode | Behavior |
/// |------|----------|
/// | `.fixed(n)` | Exactly n characters wide |
/// | `.flexible` | Expands to fill remaining space (shared equally) |
/// | `.ratio(r)` | Takes r proportion of available width (0.0-1.0) |
/// | `.fit` | Sizes to the widest of the header and all cell values (O(rows)) |
public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: View, Label: View>:
    TableColumnContent
{
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never

    /// The column header title.
    let title: String

    /// The width mode for this column.
    var width: ColumnWidth = .flexible

    /// How a cell value is shortened when it is wider than the column.
    ///
    /// A cell is always clipped to its column's width so the columns stay
    /// aligned; this controls *which* part of an over-long value is kept.
    /// Defaults to `.tail` (keep the start, drop the end).
    var truncationMode: TruncationMode = .tail

    /// The maximum number of lines a cell in this column may occupy.
    ///
    /// A value that is wider than the column — or that contains explicit line
    /// breaks — wraps onto further lines up to this limit (the row grows to its
    /// tallest cell); content beyond the limit is folded into the last line and
    /// truncated with an ellipsis. Mirrors SwiftUI's `lineLimit`. Defaults to `1`
    /// (single-line cells, the classic table look).
    ///
    /// Clamped to at least 1 on assignment, as ``lineLimit(_:)`` already does:
    /// the wrapper folds and truncates only for `maxLines >= 1`, so a column
    /// written to directly with 0 or a negative computed value did not become a
    /// single-line column — it became an UNLIMITED one, growing the row to
    /// however many lines the value wrapped to.
    var lineLimit: Int = 1 {
        didSet { lineLimit = max(1, lineLimit) }
    }

    /// What the column draws in each row's cell.
    let cell: _TableCellSource<RowValue>

    /// Whether ``cell`` NAMES a property rather than computing one — true
    /// exactly for the `init(_:value:)` overloads that take a
    /// `KeyPath<RowValue, String>` and no content closure.
    ///
    /// The distinction is not cosmetic and it is not about sorting: a key path
    /// has no closure context, so it cannot capture anything from the view that
    /// built it. A closure can, and usually does — a formatter, a search term,
    /// a units toggle — none of which appears in the row it is handed.
    ///
    /// That makes this the one property a row-level memo can be keyed on
    /// honestly. Where every column names a property, a row's text is a pure
    /// function of the row (modulo global state, which is the hole this
    /// framework already has everywhere and this does not widen), so an equal
    /// row draws equal text. Where any column computes one, it is not, and the
    /// memo stands aside rather than guessing.
    ///
    /// NOT derivable from ``sortComparator``, which is the trap: the
    /// `init(_:value:content:)` overloads take a key path to sort BY and a
    /// closure to display, so they carry a comparator and compute their value.
    let namesAProperty: Bool

    /// How this column sorts, when it can — the comparator a click on its
    /// header puts at the head of the table's `sortOrder`. Always `nil` when
    /// `Sort` is `Never`.
    let sortComparator: Sort?

    /// The one initializer that stores anything.
    init(
        title: String, cell: _TableCellSource<RowValue>, namesAProperty: Bool,
        sortComparator: Sort?
    ) {
        self.title = title
        self.cell = cell
        self.namesAProperty = namesAProperty
        self.sortComparator = sortComparator
    }

    /// Never called: a column hands itself to the table directly.
    public var tableColumnBody: Never { fatalError("TableColumn is primitive table column content") }
}

extension TableColumn: _TableColumnPrimitive {
    typealias ColumnRow = RowValue

    func appendColumns(to columns: inout [_TableColumnSpec<RowValue>]) {
        columns.append(spec)
    }

    /// The characters this column's cell holds for `item`: a `String` key
    /// path's value, or a `Text`'s string — `nil` for any other view.
    func value(for item: RowValue) -> String? {
        switch cell {
        case .string(let extract): extract(item)
        case .text(let make): make(item).content
        case .view: nil
        }
    }

    /// This column as the renderer draws it.
    var spec: _TableColumnSpec<RowValue> {
        _TableColumnSpec(
            title: title, alignment: .leading, width: width,
            truncationMode: truncationMode, lineLimit: lineLimit,
            cell: cell, namesAProperty: namesAProperty,
            sortComparator: sortComparator)
    }
}

// MARK: - Cell sources

extension _TableCellSource {
    /// The cell source for a content closure: the `Text` path when the closure
    /// builds a `Text`, so a plain one can be drawn as a string, and a rendered
    /// view otherwise.
    @MainActor
    static func content<Content: View>(_ content: @escaping (Value) -> Content) -> Self {
        if Content.self == Text.self {
            // Same type, so the cast cannot fail; the check above is what
            // makes it a cast at all rather than a conversion.
            return .text { content($0) as! Text }  // swiftlint:disable:this force_cast
        }
        return .view { row, context in TUIkit.renderToBuffer(content(row), context: context) }
    }
}

// MARK: - Columns that cannot sort

extension TableColumn where Sort == Never, Label == Text {
    /// Creates an unsortable column with a localized title.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - content: The view content to display for each row in a table.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(
            title: titleKey.localized, cell: .content(content), namesAProperty: false,
            sortComparator: nil)
    }

    /// Creates an unsortable column with a title, displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - content: The view content to display for each row in a table.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(
            title: String(title), cell: .content(content), namesAProperty: false,
            sortComparator: nil)
    }

    /// Creates an unsortable column with a text label.
    ///
    /// The header draws the label's text; its styling is the header's own.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - content: The view content to display for each row in a table.
    public init(_ text: Text, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(
            title: text.content, cell: .content(content), namesAProperty: false,
            sortComparator: nil)
    }

    /// Creates an unsortable column that displays a string property.
    ///
    /// A string **literal** binds here, so the header is a lookup key — see
    /// ``LocalizedStringKey``. Only the header: the cells come from the data.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - value: The path to the property associated with the column.
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) where Content == Text {
        self.init(titleKey.localized, value: value)
    }

    /// Creates an unsortable column that displays a string property, with a
    /// title displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - value: The path to the property associated with the column.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) where Content == Text {
        self.init(
            title: String(title), cell: .string { $0[keyPath: value] }, namesAProperty: true,
            sortComparator: nil)
    }

    /// Creates an unsortable column that displays a string property, with a
    /// text label.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - value: The path to the property associated with the column.
    public init(_ text: Text, value: KeyPath<RowValue, String>) where Content == Text {
        self.init(text.content, value: value)
    }
}

// MARK: - Columns sorted with a given comparator

extension TableColumn where RowValue == Sort.Compared, Label == Text {
    /// Creates a sortable column that sorts with `comparator`.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - comparator: The prototype sort comparator a click on the header
    ///     puts at the head of the table's sort order.
    ///   - content: The view content to display for each row in a table.
    public init(
        _ titleKey: LocalizedStringKey, sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(titleKey.localized, sortUsing: comparator, content: content)
    }

    /// Creates a sortable column that sorts with `comparator`, with a title
    /// displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - comparator: The prototype sort comparator.
    ///   - content: The view content to display for each row in a table.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(
            title: String(title), cell: .content(content), namesAProperty: false,
            sortComparator: comparator)
    }

    /// Creates a sortable column that sorts with `comparator`, with a text
    /// label.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - comparator: The prototype sort comparator.
    ///   - content: The view content to display for each row in a table.
    public init(
        _ text: Text, sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(text.content, sortUsing: comparator, content: content)
    }
}

// MARK: - Columns sorted by a key path

extension TableColumn {
    /// `keyPath`, as the `Sendable` key path Foundation's `KeyPathComparator`
    /// asks for.
    ///
    /// SwiftUI's initializers take a plain `KeyPath` and so do these, so that
    /// SwiftUI source compiles as written. A key path is an immutable value; it
    /// is unsafe to share only when a subscript component captured an argument
    /// that is not itself `Sendable` — a key path SwiftUI accepts here too.
    /// `Sendable` is a marker protocol, so the composition has the class
    /// reference's own layout and the cast changes no bits.
    static func sendable<V>(_ keyPath: KeyPath<RowValue, V>) -> any KeyPath<RowValue, V> & Sendable {
        unsafeBitCast(keyPath, to: (any KeyPath<RowValue, V> & Sendable).self)
    }
}

extension String.StandardComparator {
    /// What a `String` column sorts with when it is not given a comparator:
    /// `.localizedStandard` — so "item2" sorts before "item10" — where
    /// Foundation has it, `.lexical` where it does not (the static Linux SDK's
    /// Foundation, measured with Swift 6.3.3).
    @usableFromInline
    static var tableColumnDefault: Self {
        #if canImport(Darwin)
            .localizedStandard
        #else
            .lexical
        #endif
    }
}

extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
    /// Creates a sortable column that displays a string property.
    ///
    /// The overload a `String` key path takes in a table with a `sortOrder`;
    /// in a table without one, the `init(_:value:)` that cannot sort takes
    /// it instead, exactly as SwiftUI resolves the two.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - value: The path to the property associated with the column.
    ///   - comparator: The comparator the property's values are ordered by.
    public init(
        _ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .tableColumnDefault
    ) where Content == Text {
        self.init(titleKey.localized, value: value, comparator: comparator)
    }

    /// Creates a sortable column that displays a string property, with a
    /// title displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - value: The path to the property associated with the column.
    ///   - comparator: The comparator the property's values are ordered by.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .tableColumnDefault
    ) where Content == Text {
        self.init(
            title: String(title), cell: .string { $0[keyPath: value] }, namesAProperty: true,
            sortComparator: KeyPathComparator(Self.sendable(value), comparator: comparator))
    }

    /// Creates a sortable column that displays a string property, with a text
    /// label.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - value: The path to the property associated with the column.
    ///   - comparator: The comparator the property's values are ordered by.
    public init(
        _ text: Text, value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .tableColumnDefault
    ) where Content == Text {
        self.init(text.content, value: value, comparator: comparator)
    }

    /// Creates a sortable column that sorts by one property with a given
    /// comparator, and displays the view `content` builds.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - value: The path to the property the column sorts by.
    ///   - comparator: The comparator the property's values are ordered by.
    ///   - content: The view content to display for each row in a table.
    public init<V, C: SortComparator>(
        _ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V>, comparator: C,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where V == C.Compared {
        self.init(titleKey.localized, value: value, comparator: comparator, content: content)
    }

    /// Creates a sortable column that sorts by one property with a given
    /// comparator, with a title displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - value: The path to the property the column sorts by.
    ///   - comparator: The comparator the property's values are ordered by.
    ///   - content: The view content to display for each row in a table.
    @_disfavoredOverload
    public init<S: StringProtocol, V, C: SortComparator>(
        _ title: S, value: KeyPath<RowValue, V>, comparator: C,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where V == C.Compared {
        self.init(
            title: String(title), cell: .content(content), namesAProperty: false,
            sortComparator: KeyPathComparator(Self.sendable(value), comparator: comparator))
    }

    /// Creates a sortable column that sorts by one property with a given
    /// comparator, with a text label.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - value: The path to the property the column sorts by.
    ///   - comparator: The comparator the property's values are ordered by.
    ///   - content: The view content to display for each row in a table.
    public init<V, C: SortComparator>(
        _ text: Text, value: KeyPath<RowValue, V>, comparator: C,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where V == C.Compared {
        self.init(text.content, value: value, comparator: comparator, content: content)
    }

    /// Creates a sortable column that sorts by a `Comparable` property, and
    /// displays the view `content` builds — for a column whose display form is
    /// not its sort form: a size shown as "4.2 KB" that sorts by its byte
    /// count, a date shown formatted that sorts chronologically.
    ///
    /// ```swift
    /// TableColumn("Size", value: \.byteCount) {
    ///     Text($0.byteCount.formatted(.byteCount(style: .file)))
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - value: The path to the property the column sorts by.
    ///   - content: The view content to display for each row in a table.
    public init<V: Comparable>(
        _ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(titleKey.localized, value: value, content: content)
    }

    /// Creates a sortable column that sorts by a `Comparable` property, with a
    /// title displayed as written.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - value: The path to the property the column sorts by.
    ///   - content: The view content to display for each row in a table.
    @_disfavoredOverload
    public init<S: StringProtocol, V: Comparable>(
        _ title: S, value: KeyPath<RowValue, V>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(
            title: String(title), cell: .content(content), namesAProperty: false,
            sortComparator: KeyPathComparator(Self.sendable(value)))
    }

    /// Creates a sortable column that sorts by a `Comparable` property, with a
    /// text label.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - value: The path to the property the column sorts by.
    ///   - content: The view content to display for each row in a table.
    public init<V: Comparable>(
        _ text: Text, value: KeyPath<RowValue, V>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.init(text.content, value: value, content: content)
    }
}

// MARK: - Modifiers

extension TableColumn {
    /// Sets the width mode for this column.
    ///
    /// - Parameter width: The column width mode.
    /// - Returns: A modified column with the specified width.
    public func width(_ width: ColumnWidth) -> TableColumn {
        var copy = self
        copy.width = width
        return copy
    }

    /// Sets the maximum number of lines a cell in this column may occupy.
    ///
    /// With a limit above 1 a cell wraps its value (and honours embedded
    /// newlines) onto multiple lines, growing the row; the content is clipped to
    /// the limit with an ellipsis. A cell built from a view other than a `Text`
    /// is given that many lines to draw in. A limit below 1 is treated as 1.
    ///
    /// ```swift
    /// TableColumn("Notes", value: \.notes).lineLimit(3)
    /// ```
    ///
    /// - Parameter limit: The maximum number of lines per cell.
    /// - Returns: A modified column with the specified line limit.
    public func lineLimit(_ limit: Int) -> TableColumn {
        var copy = self
        copy.lineLimit = limit  // clamped by the property's own didSet
        return copy
    }

    /// Sets how cell values in this column are shortened when they exceed
    /// the column's width.
    ///
    /// Cells are always clipped to the column width so the table stays
    /// aligned; this chooses which part of an over-long value survives —
    /// for example `.head` keeps the end of a long file path.
    ///
    /// - Parameter mode: The truncation mode for this column's cells.
    /// - Returns: A modified column with the specified truncation mode.
    public func truncationMode(_ mode: TruncationMode) -> TableColumn {
        var copy = self
        copy.truncationMode = mode
        return copy
    }
}
