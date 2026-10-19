//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Table.swift
//
//  Created by LAYERED.work
//  License: MIT

// `Table` and its single cohesive render core `_TableCore` (column-width
// resolution, the single-line and multi-line layout paths, scroll indicators,
// and mouse wiring) are tightly coupled through the row/column/selection model;
// splitting them across files purely to satisfy the length ceiling would scatter
// that model for no clarity gain — the same rationale by which `type_body_length`
// is disabled project-wide and `_ListCore` keeps its `file_length` disable.

import Foundation
import TUIkitFoundation
import TUIkitLists
// swiftlint:disable file_length

// MARK: - Table

/// A scrollable table with columns, keyboard navigation, and selection.
///
/// `Table` displays tabular data inside a bordered container with:
/// - Column headers in the container header section
/// - Optional footer section
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single or multi-selection via bindings
/// - Configurable column widths (fixed, flexible, ratio, fit)
/// - Column alignment (leading, center, trailing)
/// - Cells that are a property's string, a `Text`, or any view
/// - ANSI-aware column layout
/// - Scrolling with automatic viewport management
///
/// ## Usage
///
/// ```swift
/// struct FileInfo: Identifiable {
///     let id: String
///     let name: String
///     let size: String
///     let modified: String
/// }
///
/// @State var selectedID: String?
///
/// Table(files, selection: $selectedID) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.size)
///         .width(10)
///         .alignment(.trailing)
///     TableColumn("Modified") { file in
///         Text(file.modified).foregroundStyle(.palette.foregroundSecondary)
///     }
///     .width(.ratio(0.3))
/// }
/// ```
///
/// The columns are SwiftUI's: ``TableColumn`` and the ``TableColumnContent``
/// they compose into, built by ``TableColumnBuilder`` — `if`/`else`, `Group`,
/// columns factored into a builder property, and ``TableColumnForEach`` for
/// columns computed from data. A cell is one line unless its column's
/// `lineLimit(_:)` allows more.
///
/// The rows are a collection's elements, or — with the `rows:` initializers,
/// `Table(of:columns:rows:)` and its siblings — whatever a ``TableRowBuilder``
/// closure gives: ``TableRow``s, `ForEach` of rows, an `if`, a `Group`, and
/// ``Section``s, each drawn under a header row across the table that the
/// cursor steps over and nothing selects.
///
/// ## Sorting
///
/// Give the table a `sortOrder` binding and the sortable columns' headers
/// become clickable, exactly as in SwiftUI. A column is sortable when it was
/// built from a key path (`TableColumn(_:value:)`, `TableColumn(_:value:content:)`,
/// `TableColumn(_:value:comparator:content:)`) or given a comparator
/// (`TableColumn(_:sortUsing:content:)`); one built from a content closure
/// alone is not, because nothing there says how to order the rows. The
/// comparator type is the binding's: `KeyPathComparator`, `SortDescriptor`, or
/// any other `SortComparator` over the row.
///
/// ```swift
/// @State private var sortOrder = [KeyPathComparator(\FileInfo.name)]
///
/// Table(files, selection: $selectedID, sortOrder: $sortOrder) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.byteCount) { Text("\($0.byteCount) B") }
/// }
/// .onChange(of: sortOrder) { files.sort(using: $0) }
/// ```
///
/// The table publishes the order and the app applies it — SwiftUI's division
/// of labour, and the reason for that `onChange`. Clicking the column already
/// sorted by reverses it; clicking another makes it the primary sort and keeps
/// the previous one behind it as the tie-break. The column being sorted by
/// carries a `▲` / `▼`, and every sortable column reserves that glyph's width
/// so the table does not change shape as you sort it.
///
/// From the keyboard, on the focused table: `Ctrl-S` sorts by the next sortable
/// column — the same gesture as clicking its header, wrapping round to the
/// first — and `Ctrl-D` reverses the current direction. Both are rebindable,
/// like every other row chord: see ``RowAction/sortNextColumn``,
/// ``RowAction/reverseSortOrder`` and ``RowShortcuts``.
///
/// ### What `sort(using:)` costs
///
/// `sort(using:)` with `KeyPathComparator`s is **two to three orders of
/// magnitude** slower than sorting by the same property directly. Measured on
/// macOS 26, arm64, release, one sort of an array of structs:
///
/// | rows | key | `sort(using:)` | `sort { $0.k < $1.k }` |
/// |---|---|---|---|
/// | 1,000 | stored `String` | 18.6 ms | 0.037 ms |
/// | 5,000 | stored `String` | 78.5 ms | 0.185 ms |
/// | 5,000 | stored `Int` | 9.8 ms | 0.036 ms |
/// | 5,000 | computed `Int` | 45.2 ms | 0.145 ms |
///
/// Three separate costs stack up: a key-path read cannot inline the getter
/// (~130 ns against ~1 ns, so a *computed* property is the worst case), the
/// comparator is reached through a protocol, and `sort(using:)`'s own generic
/// wrapper adds more again. For a `String` key some of it is not waste —
/// Foundation compares those with localized standard ordering, so `"item2"`
/// sorts before `"item10"`, which `<` does not do.
///
/// None of this is the table's: it publishes an order and never sorts. But it
/// is paid on the frame the user clicks a header, and a table of a few thousand
/// rows spends longer there than on every frame it has ever drawn. When a sort
/// is slow enough to feel:
///
/// - sort by the property directly (`data.sort { $0.name < $1.name }`) where
///   plain ordering will do, reading the comparator only for which column and
///   which direction;
/// - or decorate, sort, undecorate — build `(key, row)` pairs once and sort
///   those — which reads each row's property once instead of O(n log n) times
///   and is the whole difference on a computed key;
/// - and sort on the frame the ORDER changes, not on every snapshot.
///
/// ## Column Spacing
///
/// Columns are separated by spaces (no vertical lines) for a clean look: two,
/// unless ``tableColumnSpacing(_:)`` says otherwise.
///
/// ## The cursor row where the terminal decides the colours
///
/// The cursor row marks itself with a fill of the palette's accent over its
/// page, breathing while the table has focus. Where the palette names colours
/// the terminal decides — its own foreground or background, or one of its
/// sixteen slots — and the terminal has not said what it paints for them, there
/// is no tint between them to draw, so the row draws **reverse video** instead,
/// over the palette's own ink and page. It is steady rather than breathing, and
/// it keeps its `●`. A selected row that is not the cursor draws its `●` and no
/// fill, which is what it has always done. A palette that states ordinary
/// colours is unaffected, on any terminal.
public struct Table<Value: Identifiable>: View {
    /// The data items to display.
    let data: [Value]

    /// The column definitions, as the renderer draws them.
    let columns: [_TableColumnSpec<Value>]

    /// Binding for single selection (optional ID).
    let singleSelection: Binding<Value.ID?>?

    /// Binding for multi-selection (Set of IDs).
    let multiSelection: Binding<Set<Value.ID>>?

    /// The sort the table's headers drive, when it was given one.
    ///
    /// Its presence is what makes the headers clickable at all — exactly as in
    /// SwiftUI, where a `Table` without a `sortOrder` binding has inert
    /// headers. The table never sorts the data itself; it publishes the order
    /// the user asked for and the app applies it (`data.sort(using:)`), which
    /// is also SwiftUI's division of labour.
    let sortModel: _TableSortModel<Value>?

    /// The selection mode derived from which binding is set.
    var selectionMode: SelectionMode {
        multiSelection != nil ? .multi : .single
    }

    /// The unique focus identifier for this table, set by ``focusID(_:)``.
    var focusID: String?

    /// Whether the table is disabled.
    var isDisabled: Bool

    /// The placeholder text shown when the table is empty, set by
    /// `tableEmptyPlaceholder(_:)`.
    var emptyPlaceholder: String = ViewConstants.localizedEmptyListPlaceholder

    /// The spacing between columns in characters, set by
    /// ``tableColumnSpacing(_:)``.
    var columnSpacing: Int = 2

    /// The action that reorders the data, set via ``onMove(_:)``. Present means
    /// the rows can be dragged into a new order.
    var moveAction: ((IndexSet, Int) -> Void)?

    /// The `.dropDestination(for:action:)` insertion action, if attached:
    /// `(insertion index, payloads)`. Type-erased so `Table` need not carry the
    /// payload type; the erased pair is `(accepts, perform)`.
    var dropInsertion: _TableDropInsertion?

    /// The customization the table's columns are shown by, when it was given
    /// one with a `columnCustomization:` initializer.
    let columnCustomization: Binding<TableColumnCustomization<Value>>?

    /// The rows as a tree, when the table is hierarchical — `Table(_:children:)`,
    /// or rows with an `OutlineGroup` or a `DisclosureTableRow` among them.
    /// ``data`` is empty then: which rows show is the expansion's to say, and
    /// only the render knows where the expansion lives.
    var rowTree: _TableRowBranch<Value>?

    /// What the row modifiers said about each row, parallel to ``data``, or
    /// `nil` when none reached any row. A tree keeps its rows' traits in its
    /// nodes instead.
    var rowTraits: [_TableRowTraits]?

    /// The section headers among the rows — a `Section` in a `rows:` closure —
    /// each at the row it is drawn above. Empty for a table of plain rows and
    /// for a tree, which draws its sections' rows without their headers.
    var sectionHeaders: [_TableSectionHeader] = []

    /// In a compact class the table shows its first column alone
    /// (``shownColumns(compact:)``).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public var body: some View {
        _TableCore(
            data: data,
            // Read here, at the body, so a change to the customization or the
            // size class shows on the next frame.
            columns: shownColumns(compact: horizontalSizeClass == .compact),
            singleSelection: singleSelection,
            multiSelection: multiSelection,
            sortModel: sortModel,
            selectionMode: selectionMode,
            focusID: focusID,
            isDisabled: isDisabled,
            emptyPlaceholder: emptyPlaceholder,
            columnSpacing: columnSpacing,
            moveAction: moveAction,
            dropInsertion: dropInsertion,
            rowTree: rowTree,
            rowTraits: rowTraits,
            sectionHeaders: sectionHeaders,
            declaredColumns: columns,
            columnCustomization: columnCustomization
        )
        // The same pairing as `ScrollView.body` and `List.body`. A table's rows
        // are its own focus stops, so its stored flag alone already suppressed
        // everything it draws today — but the flag and the subtree disable are
        // still two different statements, and the three containers agreeing is
        // what stops the next interactive cell from reintroducing the gap.
        .disabled(isDisabled)
        .paintingScrollContentBackground()
    }
}

extension Table {
    /// Lets the rows be dragged into a new order, calling `action` to perform the
    /// move — the same signature as SwiftUI's `DynamicViewContent.onMove(perform:)`
    /// and satisfied the same way, with `move(fromOffsets:toOffset:)`:
    ///
    /// ```swift
    /// Table(tasks, selection: $selected) {
    ///     TableColumn("Task", value: \.title)
    /// }
    /// .onMove { tasks.move(fromOffsets: $0, toOffset: $1) }
    /// ```
    ///
    /// The drag shows whatever ``View/rowReorderFeedback(_:)`` asks for, exactly as
    /// a `List`'s does: they share one state machine.
    ///
    /// This is a modifier on the `Table` rather than on its rows, because a
    /// `Table` built from a collection has no `ForEach` to attach SwiftUI's
    /// row-level `onMove` to. A **multi-line**
    /// table (any column with a `lineLimit` above 1) reorders too, but always
    /// with ``RowReorderFeedback/live`` feedback: a drop slot there would have to
    /// take part in the line-budget arithmetic that lets a tall row be partially
    /// clipped, and moving the rows themselves needs no slot.
    ///
    /// - Parameter action: Called with the offsets being moved and the
    ///   destination offset, measured against the collection before the move.
    public func onMove(_ action: @escaping (IndexSet, Int) -> Void) -> Table {
        var copy = self
        copy.moveAction = action
        return copy
    }

    /// Makes the ROWS a drop destination that reports WHERE the drop landed —
    /// the `Table` counterpart of `ForEach.dropDestination(for:action:)`.
    ///
    /// A `Table` built from a collection has no `ForEach` to carry SwiftUI's
    /// row-level modifier; it lives on the table itself, exactly as
    /// ``onMove(_:)`` does and for the same reason. (SwiftUI's own `Table` has
    /// neither.)
    ///
    /// While a compatible drag hovers, the table opens a gap at the prospective
    /// index — the same gap a ``RowReorderFeedback/cursor`` reorder shows,
    /// because it is the same machinery and means the same thing. On release the
    /// app is told the index it was pointing at; a drop past the last row
    /// reports one past the end, which is also how an EMPTY table is filled.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type these rows accept.
    ///   - action: Inserts the payloads at the given index — the payloads
    ///     first, then the index, as `ForEach`'s.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self,
        action: @escaping ([Payload], Int) -> Void
    ) -> Table {
        var copy = self
        copy.dropInsertion = _TableDropInsertion(
            accepts: { $0 is Payload }, takes: nil,
            perform: { index, values in action(values.compactMap { $0 as? Payload }, index) })
        return copy
    }
}

// MARK: - Initializers

extension Table {
    /// The one initializer that stores anything; the public ones differ only in
    /// which selection binding and which sort order they hand it, and `nil`
    /// for both selections is the no-selection table.
    init(
        rows: [Value], columns: [_TableColumnSpec<Value>],
        single: Binding<Value.ID?>?, multi: Binding<Set<Value.ID>>?,
        sortModel: _TableSortModel<Value>?,
        customization: Binding<TableColumnCustomization<Value>>? = nil
    ) {
        self.data = rows
        self.columns = columns.enumerated().map { index, column in
            var column = column
            column.declarationIndex = index
            return column
        }
        self.columnCustomization = customization
        self.singleSelection = single
        self.multiSelection = multi
        self.sortModel = sortModel
        self.focusID = nil
        self.isDisabled = false
    }

    /// The same, from a row builder's rows: flat ones become the table's data,
    /// a tree its ``rowTree``.
    init(
        rowList: _TableRowList<Value>, columns: [_TableColumnSpec<Value>],
        single: Binding<Value.ID?>?, multi: Binding<Set<Value.ID>>?,
        sortModel: _TableSortModel<Value>?,
        customization: Binding<TableColumnCustomization<Value>>? = nil
    ) {
        self.init(
            rows: rowList.isTree ? [] : rowList.values, columns: columns, single: single,
            multi: multi, sortModel: sortModel, customization: customization)
        if rowList.isTree {
            // With the roots' loops: a loop's insertions are placed among the
            // rows the outline shows, which only a render knows
            // (``_TableOutlineInsertions``).
            rowTree = rowList.branch
        } else {
            rowTraits = rowList.traits
            // A loop's `.dropDestination(for:action:)` or `.onInsert(of:perform:)`.
            dropInsertion = rowList.insertionAction
            sectionHeaders = rowList.sectionHeaders
        }
    }

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data.
    ///
    /// Nothing is selectable and there is no binding to write into. The rows
    /// still carry a keyboard CURSOR — it is what the arrow, Home/End and Page
    /// keys scroll with, it wears the focus background, and a click lands it
    /// on a row — only the selection gutter and the selection itself are
    /// absent.
    ///
    /// Worth reaching for whenever the rows are a display and nothing should
    /// be chosen from them. `.disabled(true)` is not the same thing: that also
    /// greys the rows and takes the table out of the focus ring, so it can no
    /// longer be scrolled from the keyboard.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        // No binding at all, rather than a `.constant` one. A constant binding
        // reads as a single-selection table whose selection happens to be
        // empty — which is how the gutter for a mark that can never be drawn
        // survived, and what `isReserved(hasSelection:environment:)` asks
        // about.
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil, multi: nil,
            sortModel: nil)
    }

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data, and that supports selecting zero or one row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Value.ID?>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: selection, multi: nil,
            sortModel: nil)
    }

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data, and that supports selecting multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Set<Value.ID>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil, multi: selection,
            sortModel: nil)
    }

    /// Creates a sortable table that computes its rows based on a collection
    /// of identifiable data.
    ///
    /// Supplying a sort order makes the sortable columns' headers clickable,
    /// and Ctrl-S / Ctrl-D sort from the keyboard; a table without one has
    /// inert headers, as a SwiftUI `Table` without one does.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil, multi: nil,
            sortModel: _TableSortModel(sortOrder))
    }

    /// Creates a sortable table that computes its rows based on a collection
    /// of identifiable data, and supports selecting zero or one row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: selection, multi: nil,
            sortModel: _TableSortModel(sortOrder))
    }

    /// Creates a sortable table that computes its rows based on a collection
    /// of identifiable data, and supports selecting multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil, multi: selection,
            sortModel: _TableSortModel(sortOrder))
    }
}

// MARK: - Convenience Modifiers

extension Table {
    /// Sets an explicit focus identifier for this table.
    ///
    /// By default a table generates its focus identifier from its position in
    /// the view hierarchy. Use this modifier when you need a stable, explicit
    /// identifier for programmatic focus management.
    ///
    /// - Parameter id: The focus identifier.
    /// - Returns: A table with the specified focus identifier.
    public func focusID(_ id: String) -> Table {
        var copy = self
        copy.focusID = id
        return copy
    }

    /// Sets the localized placeholder text displayed when the table has no
    /// rows.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The default is the localized "No items".
    ///
    /// - Parameter placeholderKey: The key for the text to show when empty.
    /// - Returns: A table with the specified empty placeholder.
    public func tableEmptyPlaceholder(_ placeholderKey: LocalizedStringKey) -> Table {
        tableEmptyPlaceholder(placeholderKey.localized)
    }

    /// Sets the empty placeholder text, displayed as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter placeholder: The text to show when the table is empty.
    /// - Returns: A table with the specified empty placeholder.
    @_disfavoredOverload
    public func tableEmptyPlaceholder<S: StringProtocol>(_ placeholder: S) -> Table {
        var copy = self
        copy.emptyPlaceholder = String(placeholder)
        return copy
    }

    /// Sets the number of cells between adjacent columns (default 2).
    ///
    /// Columns are separated by spaces, not rules, so this is the whole of the
    /// gap. A negative spacing is treated as zero.
    ///
    /// - Parameter spacing: The gap between columns, in cells.
    /// - Returns: A table with the specified column spacing.
    public func tableColumnSpacing(_ spacing: Int) -> Table {
        var copy = self
        // Clamped: spacing reaches `String(repeating:count:)` in three
        // places, which traps on a negative count. Clamp once here, at the
        // boundary, so every use downstream is safe by construction rather
        // than by remembering.
        copy.columnSpacing = max(0, spacing)
        return copy
    }

    /// Creates a disabled version of this table.
    ///
    /// - Parameter disabled: Whether the table is disabled.
    /// - Returns: A new table with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Table {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }
}

// MARK: - Table Core (Internal Rendering)

/// `_TableCore`'s `StateStorage` slots, by name.
///
/// Required of every `_*Core` — the project rule is "never use bare integer
/// literals for `propertyIndex`" — and this was one of the last two views still
/// writing `propertyIndex: 1  // focusID`, at seven call sites, where a comment
/// is the only thing saying which slot that is and nothing checks it.
///
/// `0...`, not the negative reserved range: a table renders no caller-supplied
/// content at its OWN identity, so these can never alias a composite content
/// view's first `@State`. At file scope rather than nested, because
/// `_TableCore` is generic and a nested type inherits that generic context,
/// where a `static let` is not allowed (`_ImageCore` and `_UserResizableCore`
/// do the same).
private enum StateIndex {
    /// The persisted ``ItemListHandler`` — selection, cursor, scroll offset.
    static let handler = 0
    /// The focus id, persisted so it survives a frame where the declaration is
    /// momentarily absent (see `FocusRegistration.persistFocusID`).
    static let focusID = 1
    /// A hierarchical table's open branches — those no `DisclosureTableRow`
    /// binding owns — by row id.
    static let outlineExpansion = 2
    /// The row menu — a selection menu's or a row's own — and what it was
    /// opened on (``RowMenuState``).
    static let rowMenu = 3
    /// The column menu, opened from the header or Return on a picked column,
    /// and the column it was opened on.
    static let columnMenu = 4
}

/// Internal core view that handles table rendering inside a ContainerView.
private struct _TableCore<Value: Identifiable>: View, Renderable, Layoutable {
    /// The inset between the table's border and its row lines.
    ///
    /// One constant because two things must agree about it: the layout that
    /// draws the rows there, and the mouse maths that works out which cell of a
    /// row a press landed on. They drifted apart once already — see
    /// `rowContentLeft` in `attachMouseHandlers`.
    static var containerPadding: EdgeInsets { EdgeInsets(horizontal: 1, vertical: 0) }

    /// The padding the container is DRAWN with: ``containerPadding`` less the
    /// leading cell, which the header and the rows draw themselves so a row's
    /// fill reaches the table's edge (``TableRowInset``). The geometry is
    /// ``containerPadding``'s either way.
    static var drawnContainerPadding: EdgeInsets {
        EdgeInsets(top: containerPadding.top, leading: 0, bottom: containerPadding.bottom, trailing: containerPadding.trailing)
    }

    /// The gap between columns in a row that is riding the pointer.
    static var previewColumnSpacing: Int { 2 }

    /// The cells a row spends on its selection mark when it has one: the glyph
    /// and the gap to the first column.
    ///
    /// Everything that places anything on a row line goes through
    /// ``selectionGutter(_:)`` rather than this — the header indent, the column
    /// widths, the row content, the ramp's column walk, the header's click
    /// ranges and the row-in-hand preview — because a table with nothing to
    /// mark reserves none of it and they would otherwise disagree by two cells.
    static var selectionGutterWidth: Int { 2 }

    var data: [Value]
    var columns: [_TableColumnSpec<Value>]
    let singleSelection: Binding<Value.ID?>?
    let multiSelection: Binding<Set<Value.ID>>?
    let sortModel: _TableSortModel<Value>?
    let selectionMode: SelectionMode
    let focusID: String?
    let isDisabled: Bool
    let emptyPlaceholder: String
    let columnSpacing: Int
    var moveAction: ((IndexSet, Int) -> Void)?
    var dropInsertion: _TableDropInsertion?

    /// The table's rows as a tree, when it is hierarchical; ``data`` is empty
    /// until ``resolveRows(_:)`` flattens it.
    let rowTree: _TableRowBranch<Value>?

    /// This frame's flattening of ``rowTree``: the rows that show and where
    /// each sits. Set only on the copy ``prepared(_:)`` makes (``resolveRows(_:)``).
    var outline: _TableOutline<Value>?

    /// What the row modifiers said about each row, parallel to ``data``, or
    /// `nil` when none reached any row.
    var rowTraits: [_TableRowTraits]?

    /// The section headers among the rows (``Table/sectionHeaders``).
    var sectionHeaders: [_TableSectionHeader] = []

    /// Every column the table declares, shown or not, in declaration order —
    /// what the column menu lists and an order is laid over.
    var declaredColumns: [_TableColumnSpec<Value>] = []

    /// The customization the user's column gestures write to, when the table
    /// was bound to one. A table without one takes no column gesture: its
    /// columns are the app's alone, as SwiftUI's are to reorder.
    var columnCustomization: Binding<TableColumnCustomization<Value>>?

    /// Where those headers fall among this frame's rows, when there are any.
    /// Filled in by ``resolveRows(_:)``.
    var sections: _TableSectionLayout?

    /// The rows a `.selectionDisabled()` reached, by their index in ``data``.
    /// Filled in by ``resolveRows(_:)``.
    var selectionDisabledRows: Set<Int> = []

    /// Whether any row has a menu of its own (`TableRow.contextMenu`). Filled
    /// in by ``resolveRows(_:)``, so a frame asks the traits once.
    var hasRowMenus = false

    /// Whether this copy is the one a pass laid out (``prepared(_:)``): its
    /// rows sized and resolved, the widths the table keeps applied, and
    /// ``cascadesCellText`` answered.
    var isPrepared = false

    /// Whether the style cascade says something to a `String` or plain `Text`
    /// cell's text this pass — ``cellTextAttributes(_:)`` is not empty — on
    /// the copy ``prepared(_:)`` made; `nil` on any other. Asked once for the
    /// table rather than by every cell: the question builds a set of scopes
    /// and walks the cascade, and every reader of every cell asks it, the fit
    /// scan over every row among them.
    var cascadesCellText: Bool?

    var body: Never {
        fatalError("_TableCore renders via Renderable")
    }

    /// Whether this table's rows need resolving before it draws — a tree to
    /// flatten, or rows a modifier reached. Asked by ``prepared(_:)`` alone,
    /// before it resolves them.
    private var needsResolution: Bool {
        rowTree != nil || rowTraits != nil || !sectionHeaders.isEmpty
    }

    /// Resolves this table's rows as this frame draws them: a tree flattened
    /// into the rows that show, its first column drawing each row's place in
    /// the tree, and what the row modifiers said gathered by row.
    ///
    /// Done at the entry points rather than when the table is built, because
    /// a tree's open branches are state, kept at this table's identity, which
    /// only a pass's context can reach. Everything past the entry points then
    /// reads an ordinary table of rows.
    private mutating func resolveRows(_ context: RenderContext) {
        if let rowTree {
            let expansion: StateBox<Set<AnyHashable>> =
                context.stateStorage?.storage(
                    for: StateStorage.StateKey(
                        identity: context.identity, propertyIndex: StateIndex.outlineExpansion),
                    default: []) ?? StateBox([])
            let outline = _TableOutline(tree: rowTree, expansion: expansion)
            data = outline.values
            rowTraits = outline.traits
            self.outline = outline
            // The loops' insertions among the rows shown, unless the table
            // takes drops between its rows itself (`Table.dropDestination`).
            if dropInsertion == nil { dropInsertion = outline.insertionAction }
            if let first = columns.first {
                columns[0] = outline.disclosing(first)
            }
        }
        if let traits = rowTraits {
            selectionDisabledRows = Set(
                traits.indices.lazy.filter { traits[$0].selectionDisabled == true })
            hasRowMenus = traits.contains { $0.contextMenu != nil }
        }
        if !sectionHeaders.isEmpty {
            sections = _TableSectionLayout(sectionHeaders, rowCount: data.count)
        }
    }

    /// This table as a pass lays it out, when that is not this copy: its row
    /// heights sized (``sizeRows(_:)``), the widths it keeps for its columns
    /// applied (``applyKeptWidths(_:)``), its rows resolved
    /// (``resolveRows(_:)``) and ``cascadesCellText`` answered — `nil` for the
    /// copy that already is. `context` is the one the entry points prepare,
    /// its text claimed for `.control(.table)` (``claimCellText(in:)``).
    ///
    /// All of it on one copy, which each entry point makes once. Prepared a
    /// step at a time, a copy a step, each copy went round the entry point
    /// again and asked every question again: the kept widths' state lookup
    /// twice a pass, and the table copied twice where its rows were sized.
    private func prepared(_ context: RenderContext) -> Self? {
        guard !isPrepared else { return nil }
        var table = self
        table.isPrepared = true
        table.sizeRows(context.environment)
        table.applyKeptWidths(context)
        if table.needsResolution { table.resolveRows(context) }
        table.cascadesCellText = Self.cellTextAttributes(context.environment) != StyleAttributes()
        return table
    }

    /// Gives the columns the widths a user gave them where no customization
    /// records them (``ItemListHandler/transientColumnWidths``): a table with
    /// no customization binding, or a column with no identifier. Read off the
    /// table's handler without making one: a table nobody has resized pays a
    /// state lookup and nothing else (decisions B-D4T-7).
    private mutating func applyKeptWidths(_ context: RenderContext) {
        guard let storage = context.stateStorage else { return }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.handler)
        guard let box: StateBox<ItemListHandler<Value.ID>> = storage.existingStorage(for: key) else { return }
        let widths = box.value.transientColumnWidths
        guard !widths.isEmpty else { return }
        for index in columns.indices where columns[index].resizedWidth == nil {
            if let width = widths[columns[index].columnKey] {
                columns[index].resizedWidth = width
            }
        }
    }

    /// Gives the columns the line limits ``EnvironmentValues/tableRowHeights``
    /// says — nothing to do where it says what they already are, which is the
    /// default.
    ///
    /// A column that grows to its content is given ``_TableCellSizing/naturalLines``
    /// as its limit, which puts the table on the multi-line layout and tells
    /// its view cells to be measured before they are drawn.
    private mutating func sizeRows(_ environment: EnvironmentValues) {
        let heights = environment.tableRowHeights
        guard heights != .lineLimited else { return }
        for index in columns.indices where !columns[index].lineLimitIsStated {
            switch columns[index].cell {
            case .view: break
            case .text where heights == .automatic: break
            case .text, .string: continue
            }
            columns[index].lineLimit = _TableCellSizing.naturalLines
        }
    }

    /// Whether this table lays its rows out as rows of their own heights —
    /// any column of more than one line, or section headers among the rows,
    /// which are lines a row carries above itself.
    private var usesMultiLineLayout: Bool {
        sections != nil || columns.contains { $0.lineLimit > 1 }
    }

    /// The lines the column header takes: one, or none under
    /// `.tableColumnHeaders(.hidden)` and in a horizontally compact size
    /// class, where SwiftUI's table "automatically hides headers and all
    /// columns after the first" (decisions B3).
    private func headerLines(_ environment: EnvironmentValues) -> Int {
        environment.tableColumnHeadersVisibility == .hidden || environment.horizontalSizeClass == .compact ? 0 : 1
    }

    /// The cells the table's border takes on each side: one under a bordered
    /// style, none under `.inset` or `.surface`.
    private func borderWidth(_ environment: EnvironmentValues) -> Int {
        switch environment.tableStyle.builtInChrome {
        case .inset, .surface: 0
        case .bordered, nil: 1
        }
    }

    /// The table's container drawn — and under `.tableStyle(.surface)` painted
    /// with its tones, where there is no border, so the header (when there is
    /// one) is line 0.
    private func render(_ container: some View, on surface: CollectionSurface?, context: RenderContext) -> FrameBuffer {
        let buffer = TUIkitView.renderToBuffer(container, context: context)
        return surface?.painted(buffer, headerLines: 0..<headerLines(context.environment), context: context) ?? buffer
    }

    /// The lines of chrome around the rows: the border's two rules, when it
    /// has them, and the column header. Every height the rows are budgeted is
    /// the space on offer less these.
    private func chromeLines(_ environment: EnvironmentValues) -> Int {
        2 * borderWidth(environment) + headerLines(environment)
    }

    /// The width inside the border and its padding, out of `width` — what
    /// the header and the rows lay out in.
    private func innerWidth(_ width: Int, _ environment: EnvironmentValues) -> Int {
        max(
            0,
            width - 2 * borderWidth(environment) - Self.containerPadding.leading
                - Self.containerPadding.trailing)
    }

    /// The width inside, for a table that shows its vertical scrollbar or
    /// does not: ``innerWidth(_:_:)`` and the cell ``trailingPadding(_:showsBar:)``
    /// gives back.
    private func innerWidth(_ width: Int, _ environment: EnvironmentValues, showsBar: Bool) -> Int {
        innerWidth(width, environment) + Self.containerPadding.trailing
            - trailingPadding(environment, showsBar: showsBar)
    }

    /// The cells between the rows' last column and the table's edge: one,
    /// as before them — except beside a `.surface` table's vertical scrollbar,
    /// none. A bordered table's blank cell after the bar mirrors the one before
    /// the rows, inside a frame; a surface table has no frame, and the
    /// column of surface past the bar read as the table running on past its
    /// own edge (the owner's ruling, 2026-10-16).
    private func trailingPadding(_ environment: EnvironmentValues, showsBar: Bool) -> Int {
        showsBar && environment.tableStyle.builtInChrome == .surface ? 0 : Self.containerPadding.trailing
    }

    /// The padding the container is drawn with, for a table that shows its
    /// vertical scrollbar or does not — see ``trailingPadding(_:showsBar:)``.
    private func drawnPadding(_ environment: EnvironmentValues, showsBar: Bool) -> EdgeInsets {
        var padding = Self.drawnContainerPadding
        padding.trailing = trailingPadding(environment, showsBar: showsBar)
        return padding
    }

    /// The container the header and rows are drawn in: bordered, or not, as
    /// the table style says.
    private func containerStyle(_ environment: EnvironmentValues) -> ContainerStyle {
        ContainerStyle(
            showHeaderSeparator: true, showFooterSeparator: false,
            hasBorder: borderWidth(environment) > 0)
    }

    /// The style's own body, when the table style in force is not one of the
    /// built-in ones: a custom style draws the table — or not — through
    /// ``TableStyle/makeBody(configuration:)``, as in SwiftUI.
    private func customStyle(_ environment: EnvironmentValues) -> (any TableStyle)? {
        let style = environment.tableStyle
        return style.builtInChrome == nil ? style : nil
    }

    /// Whether this table has a selection binding — the only thing that can
    /// ever put a mark in the gutter.
    private var hasSelection: Bool { singleSelection != nil || multiSelection != nil }

    /// The cells this table's rows open with, before the first column:
    /// ``selectionGutterWidth`` when a mark could appear there, none when it
    /// could not. See ``RowSelectionIndicator/isReserved(hasSelection:environment:)``.
    private func selectionGutter(_ environment: EnvironmentValues) -> Int {
        RowSelectionIndicator.isReserved(hasSelection: hasSelection, environment: environment)
            ? Self.selectionGutterWidth : 0
    }

    /// Sizes the table analytically rather than by rendering it to measure.
    ///
    /// Being `Renderable`-only, `_TableCore` previously fell through `measureChild`
    /// to the fallback, which rendered the table to measure it — at the time TWICE
    /// per measure (a second render at `naturalWidth + 8` probed width-flexibility,
    /// since retired) — on top of the real render. On a 20k-row table that was
    /// ~72% of the frame (`measureChild`).
    ///
    /// The probe is unnecessary here: a table grows with the available width iff a
    /// column is `.flexible`/`.ratio` (those scale the content, which makes the
    /// hugging container fill; all-`.fixed` columns give a fixed-width content the
    /// container hugs). So flexibility is derived analytically and only the natural
    /// render remains — a single render whose context mirrors the fallback's first
    /// render exactly (`isMeasuring`, cleared `hasExplicitWidth`, proposed size),
    /// so the reported size is identical to what the fallback produced.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var context = RowSelectionIndicator.resolvingForTable(context)
        Self.claimCellText(in: &context)
        if let style = customStyle(context.environment) {
            return style.measureBody(
                configuration: TableStyleConfiguration(table: AnyView(self)), proposal: proposal,
                context: context)
        }
        if let prepared = prepared(context) {
            return prepared.sizeThatFits(proposal: proposal, context: context)
        }
        var measureContext = context
        measureContext.isMeasuring = true
        // Match the fallback: report the natural (minimum) size, not an expanded one.
        measureContext.hasExplicitWidth = false
        if let width = proposal.width {
            measureContext.availableWidth = width
        }
        if let height = proposal.height {
            measureContext.availableHeight = height
        }

        // A table's dimensions are arithmetic, not something to be discovered
        // by building the thing and measuring the result. Rendering the whole
        // table — styled cells, ANSI-aware padding, scrollbar, chrome — just to
        // read its buffer's size back off it dominated the measure pass of
        // large tables, and the sizing passes ask far more often than the
        // render does. Single-line tables are answered outright; multi-line
        // ones in every shape but one (see `analyticMultiLineSize`).
        let size: (width: Int, height: Int)
        // Both analytic paths answer "the rows, and the indicator lines an
        // OVERFLOWING table draws". Under
        // ``EnvironmentValues/alwaysShowsVerticalTextIndicators`` the two lines
        // are drawn whether or not anything is hidden, so a table whose rows fit
        // measured two lines shorter than it drew — and a container that
        // believed the measurement then handed it a viewport two lines too
        // short, in which the reservation ate two of the three rows it exists to
        // protect. The render is the authority on what the render does; a mode
        // this rare does not earn a third copy of the reservation arithmetic
        // (which is what the first two copies disagreeing about it cost).
        // The style question too: `.visible` with a SCROLLBAR spends a column,
        // not a line, and both analytic paths already handle that shape.
        if measureContext.environment.alwaysShowsVerticalTextIndicators,
            measureContext.environment.scrollIndicatorStyle == .text
        {
            let buffer = renderToBuffer(context: measureContext)
            size = (buffer.width, buffer.height)
        } else if usesMultiLineLayout {
            size =
                analyticMultiLineSize(context: measureContext)
                ?? {
                    let buffer = renderToBuffer(context: measureContext)
                    return (buffer.width, buffer.height)
                }()
        } else {
            size = analyticSingleLineSize(context: measureContext)
        }

        // `.fit` is content-sized (a fixed width derived from the data), so
        // like `.fixed` it does not grow with the available width.
        let fillsWidth = columns.contains { $0.effectiveWidth.growsWithAvailableWidth }
        return fillsWidth
            ? ViewSize.flexibleWidth(minWidth: size.width, height: size.height)
            : ViewSize.fixed(size.width, size.height)
    }

    /// The single-line table's rendered size, computed without building its
    /// rows: the header and column arithmetic are O(columns), the content
    /// block is a fixed-size stand-in reporting the exact line count and
    /// width the real rows would occupy, and the shared ``ContainerView``
    /// chrome is *measured* for real so padding/border/fill semantics stay
    /// exactly the render path's. Mirrors the corresponding line/width
    /// choices in `renderToBuffer` / `buildScrollbarContent` /
    /// `buildPopulatedContent` — TableAnalyticMeasureTests holds the two
    /// paths equal across the configuration matrix.
    private func analyticSingleLineSize(context: RenderContext) -> (width: Int, height: Int) {
        let palette = context.environment.palette
        let gutter = selectionGutter(context.environment)
        let rowArea = max(1, context.availableHeight - chromeLines(context.environment))
        let wantsScrollbar =
            !data.isEmpty
            && context.environment.verticalScrollIndicators(
                overflowing: data.count > rowArea
            ).bar
        let innerWidth = innerWidth(context.availableWidth, context.environment, showsBar: wantsScrollbar)
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? context.environment.scrollbarWidth : 0))
        // The columns stop short of the bar by the spacing; the rows' fills do
        // not (`View.scrollbarSpacing(_:)`).
        let columnsWidth = max(1, contentInnerWidth - context.environment.rowScrollbarSpacing(showsBar: wantsScrollbar))
        let columnWidths = calculateColumnWidths(
            availableWidth: columnsWidth, spacing: columnSpacing, gutter: gutter,
            context: context)
        var headerLine = renderHeader(
            columnWidths: columnWidths, gutter: gutter, palette: palette
        ).text
        if wantsScrollbar {
            headerLine += String(
                repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }

        let contentSize: (width: Int, height: Int)
        if data.isEmpty {
            contentSize = (emptyPlaceholder.strippedLength, 1)
        } else if wantsScrollbar {
            // The scrollbar path fills the whole content area: every line is
            // the row content padded to `contentInnerWidth` plus the bar cell.
            contentSize = (contentInnerWidth + 1, rowArea)
        } else {
            // The plain path emits the visible rows plus indicator lines,
            // filling the content area exactly when overflowing; rows are
            // padded to the table's content width, but an indicator line can
            // exceed it ("▼ N more below" on narrow tables), so the ones the
            // render pass would draw at the current scroll state are built
            // (O(1) each) and folded into the width.
            let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
            var widest = contentWidth
            if data.count > rowArea {
                let persistedFocusID = FocusRegistration.persistFocusID(
                    context: context, explicitFocusID: focusID,
                    defaultPrefix: "table",
                    propertyIndex: StateIndex.focusID)
                let (handler, _) = resolveHandler(
                    persistedFocusID: persistedFocusID,
                    stateStorage: context.stateStorage!,
                    context: context, contentHeight: rowArea, overflows: { _ in true })
                let window = reserveIndicatorLines(
                    handler: handler, contentHeight: rowArea, context: context)
                // Measure with the SAME locale the display path uses, or a
                // grouped "12,000" would be measured as "12000" and the column
                // sized one cell short.
                let measureLocale = context.environment.locale
                // From the pair just computed, NOT from the handler: this is a
                // measure pass and it no longer publishes them there.
                let rowsAbove = window.origin
                let rowsBelow = max(0, data.count - (window.origin + window.viewport))
                if rowsAbove > 0 {
                    widest = max(
                        widest,
                        scrollIndicatorWidth(
                            direction: .up, count: rowsAbove,
                            unit: .rows,
                            width: contentWidth, locale: measureLocale))
                }
                if rowsBelow > 0 {
                    widest = max(
                        widest,
                        scrollIndicatorWidth(
                            direction: .down, count: rowsBelow,
                            unit: .rows,
                            width: contentWidth, locale: measureLocale))
                }
            }
            contentSize = (widest, min(data.count, rowArea))
        }

        return analyticSize(headerLine: headerLine, content: contentSize, showsBar: wantsScrollbar, context: context)
    }

    /// A multi-line table's size, computed rather than rendered — or `nil` for
    /// the one shape that cannot be, which falls back to the render.
    ///
    /// Two of the three shapes are pure arithmetic:
    ///
    /// * **A bar is drawn.** The bar costs a column, not a line, and
    ///   ``composeMultiLineRows`` pads its output to the content area before
    ///   merging the bar in as the rightmost cell. The block is therefore the
    ///   content area exactly, whatever the rows do — not one row need be
    ///   wrapped to know the size.
    /// * **The rows fit.** No indicator, no clip, so the block is the sum of
    ///   their heights. Bounded work: rows that fit are at most a viewport's
    ///   worth.
    ///
    /// The third — overflowing with no bar — has the content area for a height
    /// but a *width* that a "▼ N more rows below" line can exceed on a narrow
    /// table, and that N comes from the scroll window. Reimplementing the
    /// window here would put a second copy of that arithmetic in this file, the
    /// mistake that keeps `List` and `Table` drifting apart, so it renders.
    ///
    /// This matters because the *sizing* passes ask far more often than the
    /// render does: `measureNaturalExtent` walks a ladder of ever-larger height
    /// budgets looking for the content's natural extent (see the ScrollView
    /// extent ladder), and every rung was building the whole table to read
    /// `buffer.height` back off it.
    ///
    /// `TableAnalyticMeasureTests` holds this equal to the rendered size across
    /// the multi-line configuration matrix, including the ladder's tall budgets.
    private func analyticMultiLineSize(
        context: RenderContext
    ) -> (width: Int, height: Int)? {
        // Empty is a placeholder line, not rows — the render's business.
        guard !data.isEmpty else { return nil }
        let palette = context.environment.palette
        let gutter = selectionGutter(context.environment)
        let rowArea = max(1, context.availableHeight - chromeLines(context.environment))
        // Decide the bar exactly as `renderToBuffer` does — at the width a bar
        // WOULD leave, where rows wrap taller and so overflow soonest.
        let overflows = multiLineOverflows(
                rowArea: rowArea,
                innerWidth: innerWidth(context.availableWidth, context.environment, showsBar: true)
                    - context.environment.scrollbarWidth,
                gutter: gutter, context: context)
        let wantsScrollbar = context.environment.verticalScrollIndicators(
            overflowing: overflows
        ).bar
        let innerWidth = innerWidth(context.availableWidth, context.environment, showsBar: wantsScrollbar)
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? context.environment.scrollbarWidth : 0))
        // The columns stop short of the bar by the spacing; the rows' fills do
        // not (`View.scrollbarSpacing(_:)`).
        let columnsWidth = max(1, contentInnerWidth - context.environment.rowScrollbarSpacing(showsBar: wantsScrollbar))
        let columnWidths = calculateColumnWidths(
            availableWidth: columnsWidth, spacing: columnSpacing, gutter: gutter,
            context: context)
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)

        let content: (width: Int, height: Int)
        if wantsScrollbar {
            // A bar costs a column, not a line, and ``composeMultiLineRows``
            // pads its output to the content area before merging the bar in as
            // the rightmost cell. So the block is the area, exactly, whatever
            // the rows do — no row need be wrapped at all to know this.
            content = (contentWidth + 1, rowArea)
        } else if !overflows {
            // Rows that fit draw no indicator and take no clip, so the block is
            // exactly their lines, each padded to the row content width.
            var totalLines = 0
            let headers = sectionHeaderHeights(columnWidths: columnWidths, context: context)
            for index in data.indices {
                totalLines += entryHeight(index, columnWidths: columnWidths, context: context, headers: headers)
            }
            content = (contentWidth, totalLines)
        } else {
            // Overflowing without a bar: the height is the content area, but a
            // "▼ N more rows below" line can be WIDER than the rows on a narrow
            // table, and that N comes from the scroll window. Declined rather
            // than reimplemented — see above.
            return nil
        }
        // The chrome is then *measured* for real, exactly as the single-line
        // analytic does, so border/padding semantics stay the render path's
        // rather than being duplicated as arithmetic here.
        var headerLine = renderHeader(
            columnWidths: columnWidths, gutter: gutter, palette: palette
        ).text
        if wantsScrollbar {
            headerLine += String(
                repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }
        return analyticSize(headerLine: headerLine, content: content, showsBar: wantsScrollbar, context: context)
    }

    /// The table's outer size, given the header line and the content block's
    /// dimensions: the shared ``ContainerView`` chrome measured around a
    /// fixed-size stand-in for the rows. Both analytic paths end here so
    /// neither can drift from the container `renderToBuffer` builds.
    private func analyticSize(
        headerLine: String, content: (width: Int, height: Int), showsBar: Bool, context: RenderContext
    ) -> (width: Int, height: Int) {
        let container = ContainerView(
            title: nil,
            style: containerStyle(context.environment),
            padding: drawnPadding(context.environment, showsBar: showsBar)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // No claims on the analytic MEASURE path: it reports a size and draws
                // nothing, and a claim describes cells that were never on screen.
                _TableHeaderView(
                    line: headerLines(context.environment) > 0 ? headerLine : nil, claims: [])
                // The rows' lines with the inset cell each draws (`TableRowInset`).
                _TableSizeStub(width: content.height > 0 ? content.width + 1 : content.width, height: content.height)
            }
        }
        let measured = measureChild(
            container,
            proposal: ProposedSize(
                width: context.availableWidth, height: context.availableHeight),
            context: context)
        return (measured.width, measured.height)
    }

    /// Populated-state snapshot the mouse handler needs.
    private struct PopulatedRenderState {
        let handler: ItemListHandler<Value.ID>
        let focusID: String
        let visibleRange: Range<Int>
        /// One when this frame drew an "N more above" line, zero otherwise —
        /// each path answering with the condition it actually drew by.
        ///
        /// Only the scrollbar's region needs it (see `attachMouseHandlers`);
        /// the bands carry the same offset for everything else.
        let scrollOffsetAbove: Int
        /// Where every drawn entry landed, in ``ItemListHandler/DrawnBand``'s
        /// space — lines from the interior's first CONTENT line, indicator and
        /// overscroll slide already in.
        ///
        /// The frame's ONE answer to "what is on this line": the hit-test
        /// closure maps a click through it, the keyboard cursor's marker takes
        /// its rectangle from it, and the handler is handed the same array for
        /// the drag to resolve against. `_ListCore` has always worked this way
        /// (`visibleRowYRanges`); `Table` re-derived it from `visibleRange`,
        /// per-row heights and a live "is an indicator drawn?" predicate, and
        /// the predicate did not match the one the rows were drawn by.
        let drawnBands: [ItemListHandler<Value.ID>.DrawnBand]
        /// Whether a scrollbar column was drawn — by either layout path. Drives
        /// the bar's mouse handler in `attachMouseHandlers`.
        var hasScrollbar = false

        /// This frame's column widths and row width — enough to re-render any
        /// row on demand, which is how a ``RowReorderFeedback/cursor`` drag gets
        /// its floating preview.
        ///
        /// Deliberately NOT the row line as drawn: that line is styled for the
        /// grid it sits in (selection background, padding out to the interior
        /// width, the scrollbar's column beside it), and floating it painted
        /// over the scrollbar and the right border. What rides the pointer is
        /// the row as its own object — the contract `_ListCore` already keeps by
        /// floating the row's own content buffer.
        var columnWidths: [Int] = []
        var rowContentWidth = 0

        /// The header's gesture for the frame (``attachHeaderHandlers(to:context:state:mouseDispatcher:focusManager:)``),
        /// with which the table's own handler takes the gaps between the
        /// titles — `nil` for a table with no header, and until the header's
        /// handlers are attached.
        var headerGesture: _TableHeaderGesture?
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var context = RowSelectionIndicator.resolvingForTable(context)
        Self.claimCellText(in: &context)
        if let style = customStyle(context.environment) {
            return style.makeBuffer(
                configuration: TableStyleConfiguration(table: AnyView(self)), context: context)
        }
        if let prepared = prepared(context) { return prepared.renderToBuffer(context: context) }
        // `.tableStyle(.surface)`: everything below is drawn on the table's own
        // surface — a field in a cell steps off it, a stripe tints over it — and
        // the finished buffer is painted with it at the end. Taken AFTER the
        // prepared table hands over, which renders in this same context and
        // would otherwise lift its surface off this one's.
        let surface: CollectionSurface?
        (context, surface) = CollectionSurface.drawing(context, when: context.environment.tableStyle.builtInChrome == .surface)
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!
        // The enabled selection scopes filed before the cells are drawn: any
        // filed after are the cells' own (see `fileSelectableRows`).
        let scopesBefore = context.environment.mouseEventDispatcher?.enabledSelectionScopeCount ?? 0

        // Rows beyond the viewport are skipped, not gone: retain their state
        // (see StateStorage.retainSubtree). Render path only, per the
        // measure-side-effect rule.
        if !context.isMeasuring { stateStorage.retainSubtree(context.identity) }

        // Calculate available width inside container (subtract border + padding).
        let gutter = selectionGutter(context.environment)

        // A single-line table decides a scrollbar cheaply (one line per row).
        // A multi-line table's overflow is its total WRAPPED height, so that
        // walk is only run when a bar is in play at all — scrollbars are opt-in
        // (`.hidden` by default), which is what keeps the default path free of
        // it (see `multiLineOverflows`).
        let rowArea = max(1, context.availableHeight - chromeLines(context.environment))
        let isMultiLine = usesMultiLineLayout
        let wantsScrollbar =
            !data.isEmpty
            && context.environment.verticalScrollIndicators(
                overflowing: isMultiLine
                    ? multiLineOverflows(
                rowArea: rowArea,
                innerWidth: innerWidth(context.availableWidth, context.environment, showsBar: true)
                    - context.environment.scrollbarWidth,
                gutter: gutter, context: context)
                    : data.count > rowArea
            ).bar
        let innerWidth = innerWidth(context.availableWidth, context.environment, showsBar: wantsScrollbar)
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? context.environment.scrollbarWidth : 0))
        // The columns stop short of the bar by the spacing; the rows' fills do
        // not (`View.scrollbarSpacing(_:)`).
        let columnsWidth = max(1, contentInnerWidth - context.environment.rowScrollbarSpacing(showsBar: wantsScrollbar))

        let columnWidths = calculateColumnWidths(
            availableWidth: columnsWidth, spacing: columnSpacing, gutter: gutter,
            context: context)

        let contentLines: [String]
        var contentRuns: [AnimatedCellRun] = []
        var contentClaims: [OpacityRegion] = []
        /// What the drawn rows' view cells registered, in the content lines'
        /// coordinates — see ``_TableRowPayload``.
        var contentPayload = _TableRowPayload()
        let renderState: PopulatedRenderState?
        if data.isEmpty {
            (contentLines, contentPayload) = emptyContent(columnWidths: columnWidths, rowArea: rowArea, innerWidth: innerWidth, context: context)
            // Empty is a state, not an absence: the table still occupies its
            // frame, so it is still the thing under the pointer, still
            // clickable, still focusable, and still somewhere a drag can be
            // dropped. All of that hangs off this state — without it the table
            // contributed no hit region at all and a drag over it resolved
            // nothing. Same fix as `_ListCore`'s.
            renderState = emptyRenderState(
                context: context, stateStorage: stateStorage, contentHeight: rowArea)
        } else {
            let result =
                wantsScrollbar && !isMultiLine
                ? buildScrollbarContent(
                    context: context, stateStorage: stateStorage, palette: palette,
                    columnWidths: columnWidths, contentInnerWidth: contentInnerWidth)
                : buildPopulatedContent(
                    context: context, stateStorage: stateStorage, palette: palette,
                    columnWidths: columnWidths, showsScrollbar: wantsScrollbar, innerWidth: innerWidth)
            contentLines = result.lines
            contentRuns = result.runs
            contentClaims = result.claims
            contentPayload = result.payload
            renderState = result.state
        }

        if let drawn = renderState?.visibleRange { noteDrawnRows(drawn, stateStorage: stateStorage, context: context) }

        // The header, once the rows have said which column the keyboard has
        // picked (``ItemListHandler/columnFocus``), which it draws picked out.
        let header = renderHeader(
            columnWidths: columnWidths, gutter: gutter, palette: palette, picking: renderState?.handler, emphasised: surface != nil)
        var headerLine = header.text
        if wantsScrollbar {
            // Pad the header to the full inner width so it aligns with the rows
            // (whose last column is the scrollbar); the cell above the bar is blank.
            headerLine += String.spaces(max(0, innerWidth - headerLine.strippedLength))
        }

        // A table that was GIVEN a height fills it. `hasExplicitHeight` is
        // documented on ``RenderContext/withAvailableHeight(_:)`` as the flag by
        // which "child views (like List) know to expand to fill the available
        // height", and `Table` was the one row view that did not keep it:
        // `Table(threeRows).frame(height: 12)` drew a six-line bordered box with
        // six blank lines beneath it. On the Example's Emoji page, where a filter
        // narrows 1,212 rows to one, the box collapsed from twenty lines to three
        // on a keystroke and jumped the page under the cursor.
        //
        // Padded to the width the rows already have, so the box's width cannot
        // move either — a wider blank line would widen the container, a narrower
        // one is fine but says nothing.
        //
        // An unframed table in a `VStack` reaches none of this and still hugs,
        // which is what it wants.
        let (filledContentLines, filledContentWidths) = Self.filled(
            contentLines, toRows: context.hasExplicitHeight ? rowArea : nil)

        let container = ContainerView(
            title: nil,
            style: containerStyle(context.environment),
            padding: drawnPadding(context.environment, showsBar: wantsScrollbar)
        ) {
            // `.leading`: the header sits left, over its columns. A focused/selected
            // row or a scroll indicator must never be wider than the other lines, or
            // this VStack would centre the narrower header over them — so those are
            // padded to the same content width (see `contentWidth` below), not to the
            // full interior, keeping every line the same width.
            VStack(alignment: .leading, spacing: 0) {
                _TableHeaderView(
                    line: headerLines(context.environment) > 0 ? headerLine : nil,
                    claims: header.claims)
                _TableContentView(
                    lines: filledContentLines, lineWidths: filledContentWidths, runs: contentRuns,
                    claims: contentClaims, payload: contentPayload)
            }
        }
        var buffer = render(container, on: surface, context: context)

        if let state = renderState {
            // The cells' regions are the only ones the container carries up, and
            // they go back on LAST: above the table's own catch-all, its cursor
            // marker and a draggable row's handle, so a control in a cell takes
            // the press before anything the row registered — and a region that
            // declines it (a context-menu trigger declines a left click) passes
            // it on down to the row.
            let cellRegions = buffer.hitTestRegions
            buffer.hitTestRegions.removeAll()
            attachMouseHandlers(to: &buffer, context: context, state: state, scopesBefore: scopesBefore)
            buffer.hitTestRegions += cellRegions
            presentRowMenu(over: &buffer, state: state, context: context)
            presentColumnMenu(over: &buffer, state: state, context: context)
        }
        return buffer
    }

    // MARK: - Populated content

    /// Renders the populated data rows + scroll indicators and
    /// captures the state the mouse handler needs.
    private func buildPopulatedContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        showsScrollbar: Bool = false,
        innerWidth: Int
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        payload: _TableRowPayload, state: PopulatedRenderState
    ) {
        // Multi-line cells (any column with a line limit above 1) take a separate,
        // height-aware layout path. Single-line tables keep the original
        // row-per-line path below completely untouched.
        if usesMultiLineLayout {
            return buildMultiLineContent(
                context: context, stateStorage: stateStorage, palette: palette,
                columnWidths: columnWidths, showsScrollbar: showsScrollbar,
                innerWidth: innerWidth)
        }

        // The fixed chrome is 3 lines: the top border, the bottom
        // border, and the column-header line — less the header under
        // `tableColumnHeaders(.hidden)`, and the borders under
        // `.tableStyle(.inset)`. What's left is the scrollable content
        // area, shared between the visible rows and whichever scroll
        // indicators are present.
        let availableHeight = context.availableHeight
        let chromeRows = chromeLines(context.environment)
        let contentHeight = max(1, availableHeight - chromeRows)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "table",
            propertyIndex: StateIndex.focusID
        )
        let (handler, overflowing) = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: contentHeight,
            overflows: { data.count + $0 > contentHeight }
        )
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))
        raiseBackgroundProminence(handler: handler, tableHasFocus: tableHasFocus, context: context)

        // Also when nothing overflows but `.scrollIndicators(.visible)` asked for
        // the lines anyway: they come out of the rows' budget there too, and this
        // is what publishes that. Skipped only where no line is spent at all.
        // `(false, false)` when the branch is not taken, which is the whole of
        // what "this frame reserved nothing" means — and it is stated here rather
        // than left to whatever a previous frame published.
        var drawnIndicators = (above: false, below: false)
        if overflowing || handler.alwaysReservesIndicatorLines {
            // The landing slot is drawn among the rows and takes one of their
            // lines, so the rows are budgeted the content area minus it.
            let reserved = reserveIndicatorLines(
                handler: handler,
                contentHeight: contentHeight - (handler.dropSlotAddsRow ? 1 : 0),
                context: context)
            drawnIndicators = (reserved.above, reserved.below)
        }

        let composed = composeRowLines(
            handler: handler,
            tableHasFocus: tableHasFocus,
            indicators: drawnIndicators,
            columnWidths: columnWidths,
            innerWidth: innerWidth,
            context: context,
            palette: palette
        )

        return (
            lines: composed.lines,
            runs: composed.runs,
            claims: composed.claims,
            payload: composed.payload,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                // As DRAWN — the origin after the single-line absorb — so the
                // click map subscripts the rows actually on screen.
                visibleRange: handler.drawnVisibleRange,
                // Same predicate as the click map above and as the drawing
                // condition, rather than `hasContentAbove` alone — the
                // multi-line twin already spells it out. Its consumer is the
                // ScrollView cursor-follow marker, which was aiming one line
                // low in the same configuration.
                scrollOffsetAbove: drawnIndicators.above ? 1 : 0,
                drawnBands: composed.bands,
                columnWidths: columnWidths,
                rowContentWidth: innerWidth
            )
        )
    }

    // MARK: - Scrollbar content (single-line)

    /// The render path for a single-line table that shows a scrollbar. The bar
    /// supersedes the "N more" text indicators, so the whole row area is the
    /// viewport (no indicator reservation); each visible row is built one column
    /// narrower and the styled scrollbar cell is appended to its right, with the
    /// area below the last row left blank behind the bar.
    private func buildScrollbarContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        contentInnerWidth: Int
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        payload: _TableRowPayload, state: PopulatedRenderState
    ) {
        let contentHeight = max(1, context.availableHeight - chromeLines(context.environment))
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table",
            propertyIndex: StateIndex.focusID)
        let (handler, _) = resolveHandler(
            persistedFocusID: persistedFocusID, stateStorage: stateStorage, context: context,
            contentHeight: contentHeight, overflows: { data.count + $0 > contentHeight },
            showsScrollbar: true)
        // The whole row area is visible — the bar, not a text indicator, marks the
        // off-screen rows — so the viewport is the full content height, less the
        // line a hovering drag's landing slot takes from the rows.
        if !context.isMeasuring {
            // Render only, for the reason `reserveIndicatorLines` gives at
            // length: a measure pass is offered a different height and would
            // leave a later clamp reading another proposal's viewport.
            handler.viewportHeight = max(1, contentHeight - (handler.dropSlotAddsRow ? 1 : 0))
            // A bar spends no indicator line, so this path absorbs nothing: the
            // rows are drawn from the offset itself. Published anyway, so a
            // frame that took another path cannot leave a stale origin behind.
            handler.drawnOffset = handler.scrollOffset
            handler.clampScrollOffset()
        }
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))
        raiseBackgroundProminence(handler: handler, tableHasFocus: tableHasFocus, context: context)

        // The handler's accessor, not a raw `scrollOffset..<min(…)`: the
        // persisted offset can exceed a freshly-shrunk `data.count` during a
        // measure pass (the clamp above is render-gated), and the raw form
        // would construct an inverted range (e.g. `1300..<2`) and trap.
        let visibleRange = handler.visibleRange
        var bar = ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: data.count, viewport: contentHeight, offset: visibleRange.lowerBound,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: .resting(in: palette, flash: handler.indicatorFlash.strength(context: context)),
            width: context.environment.scrollbarWidth, cornerTriangles: context.environment.cornerTrianglesFillTheCell)

        // Content-only row lines; the bar cell is merged in at the END, keyed by
        // absolute line index, so an overscroll slide moves the rows and leaves
        // the bar exactly where it is (§1.5).
        //
        // Drawn in reorder order (the dragged row out, a slot where it would
        // land) — see `composeRowLines` for the same two lines of it.
        let drawn = handler.reorderDrawnRows(visibleRange)
        func padded(_ line: String) -> String {
            line + String.spaces(max(0, contentInnerWidth - line.strippedLength))
        }
        var rowLines: [String] = []
        // Heights, not entries: the slot stands for every row in hand, so it can
        // be several lines tall and the entries no longer map one-to-one onto
        // lines. Same shape as `composeRowLines`.
        var drawnHeights: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)] = []
        /// The breathing rows' lines and every frame of each, at their position
        /// among `rowLines` — turned into runs once the clip and the slide have
        /// settled where those lines actually ended up.
        var pulseRuns: [PulseRun] = []
        /// The rows' claims, at their position among `rowLines` — moved by the same
        /// slide the runs are, once the clip has settled where the lines landed.
        var rowOpacity: [OpacityRegion] = []
        /// The rows' cell payloads, at their position among `rowLines`.
        var rowPayload = _TableRowPayload()
        rowLines.reserveCapacity(contentHeight)
        // One sampler for the frame, not one per row: building it quantises the
        // ramp, which is an array a row must not allocate.
        let rowRamp = cellRamp(rowWidth: contentInnerWidth, context: context)
        let rowStripe = Self.frameStripe(context: context, palette: palette)
        beginRowMemo(
            handler: handler, columnWidths: columnWidths,
            gutter: selectionGutter(context.environment), rowWidth: contentInnerWidth,
            stripe: rowStripe, context: context, palette: palette)
        for entry in drawn {
            switch entry {
            case .row(let rowIndex):
                let row = renderRow(
                    item: data[rowIndex],
                    paint: RowPaint(row: rowIndex, ramp: rowRamp, stripe: rowStripe, width: contentInnerWidth),
                    columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.drawsSelected(at: rowIndex),
                    isReturningHome: handler.returningRows.contains(rowIndex),
                    context: context, palette: palette, memo: handler)
                if !row.payload.isEmpty {
                    rowPayload.append(row.payload.shifted(byX: 0, y: rowLines.count))
                }
                collect(
                    line: row.line, frames: row.pulseFrames, timing: row.pulseTiming, claims: row.claims,
                    into: &rowLines, runs: &pulseRuns, claims: &rowOpacity, transform: padded)
                drawnHeights.append((entry, 1))
            case .slot:
                let slot = reorderSlotLines(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentInnerWidth,
                    context: context, palette: palette)
                collect(
                    slot, into: &rowLines, runs: &pulseRuns, claims: &rowOpacity,
                    transform: padded)
                drawnHeights.append((entry, slot.lines.count))
            }
        }
        // See `composeRowLines`: clipped away from the slot, never through it.
        // The excursion term is NEGATED: `slid()` draws unslid line y at
        // y − excursion (both signs), so the bands must move the same way —
        // `+ excursion` sent them in the OPPOSITE direction, 2×excursion away
        // from the drawn rows. `ScrollOverscrollState.slidRange` (the List's
        // path) subtracts for the same reason.
        let slide =
            clipOverrun(&rowLines, to: contentHeight, drawn: drawnHeights)
            - handler.overscrollState.excursion
        // The scrollbar path draws no "N more above" line at all — the bar is
        // the indicator — so nothing sits between the header and the first row.
        let bands = publishRowBands(
            handler: handler, drawn: drawnHeights, slide: slide,
            indicatorLines: 0, lineCount: contentHeight)
        while rowLines.count < contentHeight { rowLines.append(padded("")) }
        let blankRow = String.spaces(max(0, contentInnerWidth))
        let slid = handler.overscrollState.slid(rowLines, blank: blankRow)
        // A bar cell on every line — plain track below a bar shorter than the lines.
        bar.fit(toCount: slid.count, field: ScrollbarColors.track(in: palette))
        let lines = zip(slid, bar.lines).map { $0 + $1 }

        return (
            lines,
            // The runs travel exactly as the hit bands do — same slide, no
            // indicator line on this path — so a run and the band it belongs to
            // can never end up on different rows.
            rowRuns(pulseRuns, slide: slide, topOffset: 0, lineCount: lines.count),
            // The bar's claims are NOT slid: the bar stays put while the rows move.
            rowClaims(rowOpacity, slide: slide, topOffset: 0, lineCount: lines.count)
                + bar.claims(atColumn: contentInnerWidth),
            rowPayloads(rowPayload, slide: slide, topOffset: 0, lineCount: lines.count),
            PopulatedRenderState(
                handler: handler, focusID: persistedFocusID, visibleRange: visibleRange,
                scrollOffsetAbove: 0, drawnBands: bands, hasScrollbar: true,
                columnWidths: columnWidths, rowContentWidth: contentInnerWidth))
    }

    // MARK: - Multi-line content (variable row heights)

    /// The render path for a table with multi-line cells. Rows can be taller than
    /// one line, so the visible window, the scroll bounds, focus-reveal, and the
    /// click mapping are all line-aware (driven by per-row heights). The
    /// single-line path above is left completely untouched.
    ///
    /// Marks the rows it can't show with a scrollbar when `showsScrollbar`, "N
    /// more above/below" indicator lines otherwise — the same choice every other
    /// scrollable makes. The bar costs a column instead of a line, so the rows
    /// get the whole content area, and nothing here reserves an indicator line
    /// (which is what lets the table reach its true last screenful).
    private func buildMultiLineContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        showsScrollbar: Bool,
        innerWidth: Int
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        payload: _TableRowPayload, state: PopulatedRenderState
    ) {
        let gutter = selectionGutter(context.environment)
        // The chrome: top border + column header + bottom border, as the
        // style and the header visibility leave them.
        let contentHeight = max(1, context.availableHeight - chromeLines(context.environment))

        // Row heights are answered lazily. The scroll arithmetic below touches only
        // a viewport's worth of rows — the visible window, plus the bottom suffix
        // that fixes the furthest scroll — so a tall table needn't wrap every
        // off-screen row (the optimisation a scrollbar's *absence* permits: nothing
        // exposes the total extent).
        //
        // TWO memos, not one, because the rows fall into two kinds and only one of
        // them is worth remembering the CELLS of. A row that will be DRAWN is laid
        // out once, cells and all, and `composeMultiLineRows` draws from that same
        // answer — it used to call `cellLayout` again, so every visible cell's value
        // String was built twice a frame and hashed into `TextWrapping`'s fit memo
        // twice. A row that is only MEASURED — the bottom suffix `maxScrollOffset`
        // walks, the rows `ScrollExtentEstimator` samples — keeps `rowHeight`'s
        // height-only path, which is the whole reason that function exists: one
        // shared memo carrying cells would retain a `[[String]]` per measured row
        // too, and under ``ScrollExtentPrecision/exact`` (or for any table at or
        // below its 256-row limit) the estimator measures every row — turning an
        // O(1)-cells walk into an O(rows)-cells one.
        //
        // What the split gives up, since this is where the single memo's own note
        // used to claim it: scrolled near the end the window and the suffix overlap,
        // and an overlapping row is now measured height-only by the suffix walk AND
        // laid out by the window walk — a height pass plus a layout per drawn row,
        // which is exactly what it cost before, so nothing is lost there and nothing
        // is saved either. The saving is the whole window at every offset where the
        // two don't overlap. Routing the suffix through `layoutOf` as well would
        // recover the end of the table and pay for it everywhere else, allocating
        // cells for a screenful of rows nothing draws.
        var layoutCache: [Int: MultiLineRowLayout] = [:]
        var heightCache: [Int: Int] = [:]
        /// The lines each section header takes, when there are any.
        let headers = sectionHeaderHeights(columnWidths: columnWidths, context: context)
        /// The focused, selected row, laid out over a raised background once the
        /// focus is known (``raiseBackgroundProminence(handler:tableHasFocus:context:)``)
        /// — before the window walk, which is the first to lay a row out.
        var raisedRow: Int?
        /// The wrapped cells and the height of a row that is about to be drawn.
        func layoutOf(_ index: Int) -> MultiLineRowLayout {
            if let cached = layoutCache[index] { return cached }
            let layout = entryLayout(
                index, columnWidths: columnWidths, raised: index == raisedRow, context: context,
                headers: headers)
            layoutCache[index] = layout
            return layout
        }
        /// The height of a row that may only be measured. The layout memo is asked
        /// first because most callers ask about rows that are IN the window: by the
        /// time the scrollbar's extent estimator and `onScreenRowHeights` run, every
        /// window row is already laid out.
        func heightOf(_ index: Int) -> Int {
            if let cached = layoutCache[index] { return cached.height }
            if let cached = heightCache[index] { return cached }
            let height = entryHeight(index, columnWidths: columnWidths, context: context, headers: headers)
            heightCache[index] = height
            return height
        }

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table",
            propertyIndex: StateIndex.focusID)
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID, itemCount: data.count, viewportHeight: 1,
                selectionMode: selectionMode, canBeFocused: !isDisabled(in: context)))
        let handler = handlerBox.value
        refresh(handler, context: context)
        // As on the single-line path: a hovering drag's landing slot is a line
        // nothing left to make room for, so the rows are budgeted the content
        // area minus it and ``ItemListHandler/extent`` gains the row that lets
        // the viewport reach past the last one.
        // A landing slot occupies a line whoever opened it. A drag of this
        // control's OWN rows pays for it with the lines those rows gave up —
        // but only while those rows are still in the window, which is the
        // question ``ItemListHandler/reorderSlotNeedsALine`` answers.
        handler.dropSlotAddsRow = handler.externalDropSlot != nil || handler.reorderSlotNeedsALine
        handler.syncReturningRows(with: context.environment.dragAndDropSession)
        let rowArea = max(1, contentHeight - (handler.dropSlotAddsRow ? 1 : 0))
        // The FULL area, not `rowArea`: `dropSlotAddsRow` is already set above,
        // and every reader inside the handler that has to account for the slot
        // subtracts it itself (``rowLineBudget``). Passing the reduced figure
        // charges for the slot twice — see the twin at the single-line path,
        // which passes `contentHeight` for the same reason.
        handler.contentHeight = contentHeight
        handler.canBeFocused = !isDisabled(in: context)
        syncRowActions(handler, context: context)
        // BEFORE the rows are composed — see the List's twin call site.
        handler.carryReorderTargetThroughAutoScroll()
        // As on the single-line path, in one shared call — see
        // `ItemListHandler.syncFrameInputs`.
        //
        // `reorderFeedback: .live` — multi-line rows reorder live only: a drop
        // slot would have to take part in the line-budget arithmetic below that
        // lets a tall row be partially clipped, and moving the rows themselves
        // needs no slot. Stated in ``Table/onMove(_:)``.
        //
        // `keyboardMoveIsLive: true` — for the same reason. The handler
        // otherwise previews a keyboard move `.dimmed`, at a slot this composer
        // never draws, so Ctrl-R moved nothing visible and parked the cursor on
        // the slot's neighbour.
        //
        // `rowHeight` — the reveal-on-focus arithmetic runs between renders, on
        // key events, and answers heights lazily from this frame's data and
        // column widths.
        handler.syncFrameInputs(
            environment: context.environment, reorderFeedback: .live, keyboardMoveIsLive: true,
            rowHeight: { entryHeight($0, columnWidths: columnWidths, context: context, headers: headers) })
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // `viewportHeight` is set once the window is cut, below. It used to be
        // set HERE to the row count of the tail screenful — an
        // offset-independent number that once calibrated the handler's
        // row-based maxOffset, a job the height walk in `resolvedMaxOffset`
        // has done since `rowHeight` and `contentHeight` are both set on this
        // path — and that made PageDown, Shift+Page and the row-move page step
        // travel by the wrong count wherever the rows at the end are taller or
        // shorter than the rows on screen.
        let furthest = syncIndicatorChrome(
            handler, showsScrollbar: showsScrollbar, rowArea: rowArea,
            contentHeight: contentHeight, context: context, heightOf: heightOf)
        // §1.5, in LINES — not against `viewportHeight`, which on this path is
        // a ROW count (set from the window further down). Resolving against
        // that made `.viewport(minus:)` mean "rows visible − n" lines here
        // while the List twin meant "viewport lines − n"; and being a frame
        // stale, the first blocked tick resolved against a fresh handler's
        // default of 1.
        handler.resolveOverscroll(context: context, contentHeight: contentHeight)
        resolveScrollTo(handler, rows: data, context: context)
        // Clamp, snap off the resting duplicate, apply the anchor — the sequence
        // `_ListCore` and the single-line path below run too, and the render-pass
        // guard that has to wrap it. See `settleScrollPosition`.
        handler.settleScrollPosition(
            measuring: context.isMeasuring, overflowing: furthest > 0,
            drawsTextIndicators: handler.drawsScrollIndicators,
            firstRowHeight: heightOf(0))
        bindSelection(handler, context: context)

        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(handler.engageFocus(context: context, focusID: persistedFocusID))
        raisedRow = raiseBackgroundProminence(handler: handler, tableHasFocus: tableHasFocus, context: context)

        let window = ScrollRowWindow.resolve(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, topClip: handler.scrollTopClipLines,
            drawsTextIndicators: handler.drawsScrollIndicators,
            alwaysDrawsIndicators: context.environment.alwaysShowsVerticalTextIndicators,
            // `layoutOf`, not `heightOf`: every row this walk asks about is a row it
            // then puts IN the window (the one straddling the budget included — see
            // `ScrollRowWindow.fill`), so laying it out here with its cells is what
            // `composeMultiLineRows` draws instead of laying it out a second time.
            height: { layoutOf($0).height })
        // The window may have absorbed a top clip (or a whole first row) that
        // an indicator would otherwise have announced — the rows are drawn
        // from ITS position, so the mouse mapping must measure from it too.
        let topClip = window.topClip
        publishMultiLineWindow(handler: handler, range: window.range, context: context)
        // The bar is metered in LINES, like the `List`'s over multi-line rows:
        // its extent is the whole wrapped height and its offset the lines
        // above the window. That total is the one thing this path otherwise
        // never needs (see `heightOf`), so it is summed only when a bar is
        // actually drawn — the same discipline `_ListCore.listScrollbarCells`
        // keeps.
        let bar =
            showsScrollbar
            ? multiLineScrollbarCells(
                window: window, contentHeight: contentHeight,
                height: heightOf, handler: handler, columnWidths: columnWidths, headers: headers,
                context: context, palette: palette)
            : ClaimingColumn()
        let composed = composeMultiLineRows(
            window: window, handler: handler, tableHasFocus: tableHasFocus,
            rows: MultiLineRowLayouts(columnWidths: columnWidths, layout: layoutOf),
            innerWidth: innerWidth,
            contentHeight: contentHeight, bar: bar, context: context)

        // ONE answer, named once, for everything that has to agree with what
        // `composeMultiLineRows` just drew — `window.showsAbove` rather than the
        // handler's `hasContentAbove`, which is false for a top clip inside
        // row 0 while the indicator is on screen.
        let indicatorLines = window.reservesAbove ? 1 : 0
        let bands = multiLineRowBands(
            handler: handler,
            parts: onScreenRowParts(window.range, layout: layoutOf, topClip: topClip),
            // The row block's DRAWN end, not the content area's. The heights are
            // whole rows below the top clip, and the row straddling the budget is
            // drawn short — `ScrollRowWindow.fill` admits it so the viewport fills
            // exactly — so a band trimmed only at `contentHeight` ran on over the
            // "▼ N more rows below" line: a click there selected the cut row, and
            // with `.onMove` a press grabbed it for a `.live` reorder. A push past
            // the top did the same with the rows' slid-off tail. A ceiling rather
            // than per-row drawn heights, because a cut at the bottom moves no row
            // below it; and the ceiling `_ListCore` (`slidRows.count`) and the
            // single-line path (`lines.count + rowLines.count`) already pass.
            indicatorLines: indicatorLines, lineCount: composed.rowsEnd)
        // Built either way — the render state below carries them, and a measure
        // pass's state is thrown away — but PUBLISHED only by the render, for
        // the reason the gate above gives and one more: publishing runs
        // ``ItemListHandler/retargetForAutoScroll()`` in a `defer`, which for a
        // `.live` reorder calls `onMove` — the APP's data, moved from a measure
        // pass, and moved to wherever the parent's proposal happened to put the
        // rows. Two publishes a frame meant two crossings a tick, so an
        // auto-scrolling drag inside a stack invoked `onMove` about twice as
        // often as it moved a row.
        if !context.isMeasuring { handler.publishRowBands(bands) }
        return (
            lines: composed.lines,
            runs: composed.runs,
            claims: composed.claims,
            payload: composed.payload,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: window.range,
                scrollOffsetAbove: indicatorLines,
                drawnBands: bands,
                hasScrollbar: showsScrollbar,
                columnWidths: columnWidths,
                rowContentWidth: tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
            )
        )
    }

    /// The vertical scrollbar cells for a multi-line table — one styled cell per
    /// content line, metered in LINES so the thumb tracks fine wheel steps
    /// through tall rows exactly as the `List`'s does.
    ///
    /// This is the one place that needs the table's TOTAL wrapped height, which
    /// is why it is reached only when a bar is drawn: everything else here works
    /// from a screenful of memoised heights.
    ///
    /// And it doesn't need that total *exactly*. The off-screen rows reach the
    /// screen only as a thumb position and a thumb size, so under the default
    /// ``ScrollExtentPrecision/approximate`` they are sampled rather than
    /// wrapped — the shared ``ScrollExtentEstimator`` does the arithmetic for
    /// both twins, and pins both ends of the travel either way.
    private func multiLineScrollbarCells(
        window: ScrollRowWindow,
        contentHeight: Int,
        height: (Int) -> Int,
        handler: ItemListHandler<Value.ID>,
        columnWidths: [Int],
        headers: [Int],
        context: RenderContext,
        palette: any Palette
    ) -> ClaimingColumn {
        // Everything that shapes a row's wrapped height, so a stale mean
        // cannot outlive the layout that produced it (see `extentProfileCache`)
        // — the section headers' heights too, which are lines of the rows
        // carrying them: a header that changed height and not number left the
        // kept extent stale.
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(headers)
        hasher.combine(context.environment.scrollExtentPrecision)
        for (column, width) in zip(columns, columnWidths) {
            hasher.combine(width)
            hasher.combine(column.lineLimit)
        }
        let signature = hasher.finalize()
        let cachedProfile =
            handler.extentProfileCache.flatMap { $0.signature == signature ? $0.profile : nil }
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: window.range, count: data.count, topClip: window.topClip,
            precision: context.environment.scrollExtentPrecision,
            cached: cachedProfile, height: height)
        if !context.isMeasuring, let profile = metrics.profile {
            handler.extentProfileCache = (signature: signature, profile: profile)
        }
        return ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: metrics.extent, viewport: contentHeight,
            offset: metrics.offset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: .resting(in: palette, flash: handler.indicatorFlash.strength(context: context)),
            width: context.environment.scrollbarWidth, cornerTriangles: context.environment.cornerTrianglesFillTheCell)
    }

    /// The wrapped lines of each cell of a row plus the row's height (its tallest
    /// cell). Each cell is laid out into its column with `TextWrapping`, so an
    /// embedded newline or an over-long value expands within the column up to the
    /// column's line limit and then clips — the same model `Text` uses.
    ///
    /// A row about to be drawn is laid out under the live context, so its view
    /// cells' controls register here, and what they registered comes back as
    /// the layout's payload (``_TableRowPayload``).
    private func cellLayout(
        for item: Value, columnWidths: [Int], context: RenderContext
    ) -> MultiLineRowLayout {
        var cells: [[String]] = []
        cells.reserveCapacity(columns.count)
        var height = 1
        var payload = _TableRowPayload()
        for (index, (column, width)) in zip(columns, columnWidths).enumerated() {
            let wrapped: [String]
            if case .view = column.cell, !context.isMeasuring {
                let buffer = viewCell(column, for: item, width: width, context: context)
                wrapped = Self.cellLines(buffer, limit: column.lineLimit)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(column.lineLimit).map(String.init)
                absorbPayload(
                    of: buffer, column: index, columnWidths: columnWidths, context: context,
                    into: &payload)
            } else {
                wrapped = cellLines(column, for: item, width: width, context: context)
            }
            height = max(height, wrapped.count)
            cells.append(wrapped)
        }
        return MultiLineRowLayout(cells: cells, height: height, payload: payload)
    }

    /// One cell's lines on a multi-line row: a string wrapped into its column
    /// with `TextWrapping`, or a view's own lines, clipped to the column.
    private func cellLines(
        _ column: _TableColumnSpec<Value>, for item: Value, width: Int, context: RenderContext
    ) -> [String] {
        // A plain `Text`'s lines go straight to the row: through
        // ``cellValue(_:for:width:context:)`` they were joined into one string
        // only to be split here again, which on table-multiline was most of
        // what that path cost.
        if let text = cascadedTextCell(column, for: item, context: context) {
            context.renderCache?.rowWork.cellValues += 1
            return renderedCell(text, column, for: item, width: width, context: context)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(column.lineLimit).map(String.init)
        }
        if case .text(let make) = column.cell {
            context.renderCache?.rowWork.cellValues += 1
            let text = make(item, context)
            if let lines = Self.plainLines(of: text, in: column, width: width) { return lines }
            return renderedCell(text, column, for: item, width: width, context: context)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(column.lineLimit).map(String.init)
        }
        let value = cellValue(column, for: item, width: width, context: context)
        guard column.laysOutItsOwnLines else {
            return TextWrapping.fit(
                value, width: max(1, width), maxLines: column.lineLimit,
                mode: column.truncationMode)
        }
        return value.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(column.lineLimit).map(String.init)
    }

    // MARK: - Section headers

    /// The lines each section header takes across `columnWidths`, measured —
    /// empty for a table without sections, which is what keeps the row walks
    /// below from asking anything of one.
    private func sectionHeaderHeights(columnWidths: [Int], context: RenderContext) -> [Int] {
        guard sections != nil, !sectionHeaders.isEmpty else { return [] }
        let width = sectionHeaderWidth(columnWidths)
        let probe = Self.probing(context)
        return sectionHeaders.indices.map { index in
            let size = measureChild(
                sectionHeaders[index].view, proposal: ProposedSize(width: width, height: nil),
                context: sectionHeaderContext(
                    index, width: width, height: max(1, context.availableHeight), context: probe))
            // An empty header (a `Text("")`) still holds its row's line, as
            // macOS's group row does: the sections are told apart by it.
            return max(1, size.height)
        }
    }

    /// The width a section header is drawn across: the cells', from the first
    /// column's leading edge to the last's trailing one.
    private func sectionHeaderWidth(_ columnWidths: [Int]) -> Int {
        let total: Int = columnWidths.reduce(0, +)
        return max(1, total + columnSpacing * max(0, columnWidths.count - 1))
    }

    /// The context section header `index` is measured or drawn under: its own
    /// identity, so a collapsible header's control keeps its state; the cells'
    /// span as its width, and `height` lines; and a `List`'s section-header
    /// styling.
    private func sectionHeaderContext(
        _ index: Int, width: Int, height: Int, context: RenderContext
    ) -> RenderContext {
        var header = sectionChromeContext(
            context
                .withChildIdentity(erasedType: _TableSectionHeader.self, index: index)
                .withAvailableSize(width: width, height: height),
            .sectionHeader)
        // Drawn among the rows, which cast a shadowed style's shadows.
        Self.castingNoShadows(&header)
        return header
    }

    /// What a table with no rows draws where the rows would be: its
    /// placeholder — or, for a table of sections with no rows, their headers,
    /// since a collapsed section keeps its header, and the header is the only
    /// control that expands it again.
    ///
    /// The headers go across the cells' span, padded to the rows' width — as
    /// many as the content area holds whole, and the first one clipped to it
    /// when not even that does. With no row to carry them there is nothing to
    /// scroll; a header that does not fit is not drawn, so its control (a
    /// collapsible section's triangle) is not a Tab stop nobody can see.
    private func emptyContent(
        columnWidths: [Int], rowArea: Int, innerWidth: Int, context: RenderContext
    ) -> (lines: [String], payload: _TableRowPayload) {
        guard let indices = sections?.headersAfterLastRow, !indices.isEmpty else {
            return ([emptyPlaceholder], _TableRowPayload())
        }
        let contentWidth = tableContentWidth(
            columnWidths, within: innerWidth, gutter: selectionGutter(context.environment))
        let heights = sectionHeaderHeights(columnWidths: columnWidths, context: context)
        var fitting: [Int] = []
        var used = 0
        for index in indices where heights.indices.contains(index) {
            guard fitting.isEmpty || used + heights[index] <= rowArea else { break }
            fitting.append(index)
            used += heights[index]
        }
        let drawn = renderedSectionHeaders(
            fitting, heights: heights, columnWidths: columnWidths, context: context)
        let lines = drawn.lines.prefix(max(1, rowArea)).map { line in
            line + String.spaces(max(0, contentWidth - line.strippedLength))
        }
        return (lines, drawn.payload.clipped(toRows: 0..<lines.count))
    }

    /// The height of row `index` with the section headers drawn with it — its
    /// cells' lines, and the lines of the headers above it (and, for the last
    /// row, below it). `headers` is ``sectionHeaderHeights(columnWidths:context:)``.
    private func entryHeight(
        _ index: Int, columnWidths: [Int], context: RenderContext, headers: [Int]
    ) -> Int {
        let cells = rowHeight(of: data[index], columnWidths: columnWidths, context: context)
        guard let sections, !headers.isEmpty else { return cells }
        let above = sections.headers(above: index).reduce(0) { $0 + headers[$1] }
        let below = sections.headers(below: index).reduce(0) { $0 + headers[$1] }
        return above + cells + below
    }

    /// Row `index` laid out to be drawn, with the section headers drawn with
    /// it rendered — under the live context, so a collapsible header's
    /// disclosure control registers and its regions travel in the payload —
    /// at the heights `headers` measured them at
    /// (``sectionHeaderHeights(columnWidths:context:)``).
    ///
    /// `raised` — the focused, selected row — raises the CELLS' background
    /// prominence and nothing else: the headers carried with the row are not
    /// on its fill, and drawn under the raise, one changed colour whenever the
    /// cursor came to rest on its section's first selected row.
    private func entryLayout(
        _ index: Int, columnWidths: [Int], raised: Bool, context: RenderContext, headers: [Int]
    ) -> MultiLineRowLayout {
        var layout = cellLayout(
            for: data[index], columnWidths: columnWidths, context: raised ? Self.raised(context) : context)
        guard let sections else { return layout }
        let aboveIndices = sections.headers(above: index)
        let belowIndices = sections.headers(below: index)
        guard !aboveIndices.isEmpty || !belowIndices.isEmpty else { return layout }
        let above = renderedSectionHeaders(
            aboveIndices, heights: headers, columnWidths: columnWidths, context: context)
        let below = renderedSectionHeaders(
            belowIndices, heights: headers, columnWidths: columnWidths, context: context)
        let cellHeight = layout.height
        var payload = above.payload
        payload.append(layout.payload.shifted(byX: 0, y: above.lines.count))
        payload.append(below.payload.shifted(byX: 0, y: above.lines.count + cellHeight))
        layout.payload = payload
        layout.above = above.lines
        layout.below = below.lines
        layout.height = above.lines.count + cellHeight + below.lines.count
        return layout
    }

    /// Section headers drawn: each across the cells' span, past the selection
    /// gutter — in line with the first column, as the row's cells are — under
    /// a `List`'s section-header styling, with what their controls registered
    /// placed on their lines.
    ///
    /// Each is drawn in exactly the lines `heights` measured it at, which is
    /// what the window, the scroll and the hit bands count it as: offered the
    /// table's whole height instead, a header that grows (a `Spacer` under its
    /// title) drew as tall as the table while every count said one line.
    private func renderedSectionHeaders(
        _ indices: [Int], heights: [Int], columnWidths: [Int], context: RenderContext
    ) -> (lines: [String], payload: _TableRowPayload) {
        let width = sectionHeaderWidth(columnWidths)
        let gutter = selectionGutter(context.environment)
        let indent = String.spaces(gutter)
        var lines: [String] = []
        var payload = _TableRowPayload()
        for index in indices {
            let height = heights.indices.contains(index) ? heights[index] : 1
            let buffer = TUIkitView.renderToBuffer(
                sectionHeaders[index].view,
                context: sectionHeaderContext(index, width: width, height: height, context: context))
            var placed = _TableRowPayload()
            placed.absorb(buffer, atColumn: gutter, width: width, lines: height, alignment: .leading)
            payload.append(placed.shifted(byX: 0, y: lines.count))
            let drawn = buffer.lines.prefix(height)
            lines += drawn.map { indent + $0.truncatedToWidth(width, mode: .tail) }
            lines += Array(repeating: "", count: height - drawn.count)
        }
        return (lines, payload)
    }

    /// The height in lines of one row — its tallest cell wrapped into its column.
    /// Height-only (the wrapped lines are discarded), so the off-screen rows the
    /// scroll arithmetic has to measure are wrapped without also allocating their
    /// cell content; ``cellLayout(for:columnWidths:)`` returns the cells too, for
    /// the rows actually rendered.
    private func rowHeight(
        of item: Value, columnWidths: [Int], context: RenderContext
    ) -> Int {
        var height = 1
        // A height is a measurement, asked of rows that are not drawn too.
        let probe = Self.probing(context)
        for (column, width) in zip(columns, columnWidths) {
            let lineCount = cellLines(column, for: item, width: width,
                context: column.laysOutItsOwnLines ? probe : context
            ).count
            height = max(height, lineCount)
        }
        return height
    }

    /// Whether the "N more above / below" lines are this table's indicator:
    /// not when a scrollbar marks the hidden rows instead, and not when the
    /// view's indicators are hidden outright.
    ///
    /// Asked at `overflowing: true` because whether the rows DO overflow is
    /// itself decided using this answer (see `maxScrollOffset`), so it cannot
    /// also be an input to it — and under the default `.automatic` a table that
    /// turns out to fit reserves nothing either way, having nothing hidden to
    /// announce. Under `.scrollIndicators(.visible)` it reserves both lines
    /// whatever is hidden (`d1c54212`), which is a reservation this answer gates
    /// — see `alwaysReservesIndicatorLines` below — but does not decide.
    ///
    /// `contentHeight` is the CONTENT AREA, and it must not be the row area.
    /// The two differ by the drag landing slot, so gating on the row area would
    /// blink the "N more" lines out mid-drag on a three-line table — where the
    /// compose had three lines to spend and never overflowed anything.
    private func drawsTextIndicators(
        _ showsScrollbar: Bool, _ context: RenderContext, contentHeight: Int
    ) -> Bool {
        !showsScrollbar
            && context.environment.verticalScrollIndicators(overflowing: true)
                .fitting(contentHeight: contentHeight).text
    }

    /// The multi-line path's indicator chrome, published to the handler, and
    /// the furthest scroll offset the wrapped heights allow — the one number
    /// both flags depend on, handed back for the overscroll settle below.
    ///
    /// Sync both chrome flags in case the rows switch between the single-line
    /// and multi-line paths across frames (the single-line resolve sets them
    /// from ITS chrome; stale values would mis-budget the focus-reveal
    /// arithmetic). Same divergence class as the `017683fa` capture notes on
    /// the single-line path.
    private func syncIndicatorChrome(
        _ handler: ItemListHandler<Value.ID>, showsScrollbar: Bool, rowArea: Int,
        contentHeight: Int, context: RenderContext,
        heightOf: @escaping (Int) -> Int
    ) -> Int {
        // `rowArea` budgets the rows; `contentHeight` decides whether the
        // indicators fit at all. See ``drawsTextIndicators(_:_:contentHeight:)``
        // for why the two must not be conflated here.
        let draws = drawsTextIndicators(showsScrollbar, context, contentHeight: contentHeight)
        let furthest = maxScrollOffset(
            count: data.count, contentHeight: rowArea,
            drawsTextIndicators: draws, height: heightOf)
        handler.showsScrollbar = showsScrollbar
        // Not `!showsScrollbar`: a table whose indicators are hidden draws
        // neither, and the "N more" arithmetic must know that.
        // `.visible` asks for the affordance, not for a hint: the lines are drawn
        // even where the rows all fit, so the overflow test does not gate them.
        handler.alwaysReservesIndicatorLines =
            draws && !showsScrollbar && context.environment.alwaysShowsVerticalTextIndicators
        handler.drawsScrollIndicators =
            draws && (furthest > 0 || handler.alwaysReservesIndicatorLines)
        return furthest
    }

    /// The furthest the table can scroll: the largest first-visible row such that
    /// the remaining rows still fill the content area (reserving a line for the
    /// "above" indicator that shows whenever the first visible row isn't row 0 —
    /// a table drawing no such line, because it has a bar or no indicator at
    /// all, reserves nothing and can reach its true last screenful).
    private func maxScrollOffset(
        count: Int, contentHeight: Int, drawsTextIndicators: Bool = true,
        height: (Int) -> Int
    ) -> Int {
        var used = 0
        var offset = count
        while offset > 0 {
            let aboveReserve = (drawsTextIndicators && (offset - 1) > 0) ? 1 : 0
            let rowH = height(offset - 1)
            if used + rowH + aboveReserve > contentHeight { break }
            used += rowH
            offset -= 1
        }
        return offset
    }
    /// Whether a multi-line table's wrapped rows are taller than its row area —
    /// stopping the moment they are, so a tall table sums a screenful rather
    /// than all of it, and a table that fits has at most `rowArea` rows to sum.
    /// The same early-exit shape as `_ListCore.rowsOverflow`.
    ///
    /// Measured at the width a bar WOULD leave, where rows wrap taller and so
    /// overflow soonest: if they don't overflow even there they cannot overflow
    /// at the full width either, so answering "no bar" is final and the real
    /// column widths are then computed without the reservation.
    private func multiLineOverflows(
        rowArea: Int, innerWidth: Int, gutter: Int, context: RenderContext
    ) -> Bool {
        let widths = calculateColumnWidths(
            availableWidth: max(1, innerWidth), spacing: columnSpacing, gutter: gutter,
            context: context)
        var lines = 0
        let headers = sectionHeaderHeights(columnWidths: widths, context: context)
        for index in data.indices {
            lines += entryHeight(index, columnWidths: widths, context: context, headers: headers)
            if lines > rowArea { return true }
        }
        return false
    }

    /// Stitches the visible multi-line rows together with whichever chrome marks
    /// the hidden ones: a scrollbar down the right-hand column when `bar` is
    /// non-empty, "N more above/below" lines when the handler says those are
    /// this table's indicator, and nothing at all when they are hidden. Never
    /// both — the bar says everything the indicators would, and takes no line
    /// to say it.
    ///
    /// `rowsEnd` is where the row block's DRAWN lines stop, in the band space —
    /// the "N more above" line counted in, the "▼ N more below" line and any
    /// padding after it not. It is the ceiling the hit bands are trimmed to; see
    /// its one caller.
    private func composeMultiLineRows(
        window: ScrollRowWindow,
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        rows: MultiLineRowLayouts,
        innerWidth: Int,
        contentHeight: Int,
        bar: ClaimingColumn,
        context: RenderContext
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        payload: _TableRowPayload, rowsEnd: Int
    ) {
        let palette = context.environment.palette
        let gutter = selectionGutter(context.environment)
        // Every line — focused-row backgrounds and indicators included — is padded
        // to the *content* width (the columns), not the full interior, so a focused
        // row or a scroll indicator is never wider than the header and rows; that
        // width mismatch is what made the wrapping VStack centre the header.
        let showsBar = !bar.isEmpty
        // …and, before a bar, the cells the rows keep clear of it, which the
        // columns were laid out without (`View.scrollbarSpacing(_:)`).
        let contentWidth = min(
            innerWidth - (showsBar ? bar.width : 0),
            tableContentWidth(rows.columnWidths, within: innerWidth, gutter: gutter)
                + context.environment.rowScrollbarSpacing(showsBar: showsBar))
        // Whether the "N more" lines are this table's indicator — false for a
        // bar AND for hidden indicators, which is why it is the handler's
        // resolved answer rather than `!showsBar`.
        let drawsText = handler.drawsScrollIndicators
        // A focused table with no scrollbar pulses its "N more" indicators.
        // Resolve the emphasis ONLY when an indicator will actually be drawn.
        // Resolving consults the cursor clock, and that read is what tells the
        // demand-driven loop the frame consumed it — so asking before knowing
        // whether anything will be painted re-renders the whole page ~20 times
        // a second to draw nothing. Same class as the Stepper's ungated
        // `pulsePhase` read (8ebc3385).
        let drawsIndicator = drawsText && (window.showsAbove || window.showsBelow)
        let indicatorCycle =
            drawsIndicator
            ? scrollIndicatorCycle(isFocused: tableHasFocus, context: context) : nil
        // A flash (`scrollIndicatorsFlash`), asked only when a line is drawn.
        let indicatorFlash = drawsIndicator ? handler.indicatorFlash.strength(context: context) : nil
        let numberLocale = context.environment.locale
        let indicatorSurface = context.environment.enclosingSurface
        var lines: [String] = []
        /// The indicators' own runs. They are chrome — the rows slide past them
        /// — so each sits at the assembled line it was appended to, whatever
        /// the rows did.
        var chromeRuns: [AnimatedCellRun] = []
        /// …and their claims, placed the same way (§53).
        var chromeClaims: [OpacityRegion] = []
        // Drawn iff a line was RESERVED — see `ScrollRowWindow.reservesAbove`. The
        // count is legitimately 0 under `alwaysShowsVerticalTextIndicators`.
        if window.reservesAbove {
            let indicator = renderScrollIndicator(
                // At least one whenever anything IS hidden — a top clip hides
                // part of the first row, so the whole-row count can be 0 with a
                // row genuinely off screen. See the `List` twin.
                direction: .up,
                count: window.showsAbove ? max(1, window.range.lowerBound) : 0,
                unit: .rows,
                width: contentWidth, palette: palette, cycle: indicatorCycle, flash: indicatorFlash,
                over: indicatorSurface, locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // The content area fills EXACTLY: the bottom row may be partially
        // clipped (the top row already can be, via `scrollTopClipLines`), so
        // the table's height never changes with which rows happen to be
        // visible. Under EITHER granularity — a whole-row viewport underfills
        // whenever the visible rows don't sum to the budget, and the blank
        // lines that left at the bottom read as the table truncating itself.
        let rowLineBudget =
            max(1, contentHeight - lines.count - (window.reservesBelow ? 1 : 0))
        var rowLinesEmitted = 0
        // The rows are collected apart from the indicator chrome so that only
        // they take an overscroll slide (§1.5).
        var slidableRows: [String] = []
        /// The breathing row's lines and every frame of each, at their position
        /// among `slidableRows` — see `collect`.
        var pulseRuns: [PulseRun] = []
        var rowOpacity: [OpacityRegion] = []
        /// The rows' cell payloads, at their position among `slidableRows`.
        var rowPayload = _TableRowPayload()
        let rowRamp = cellRamp(rowWidth: contentWidth, context: context)
        let rowStripe = Self.frameStripe(context: context, palette: palette)
        for rowIndex in window.range {
            let rendered = renderMultiLineRow(
                layout: rows.layout(rowIndex),
                paint: RowPaint(row: rowIndex, ramp: rowRamp, stripe: rowStripe, width: contentWidth),
                isFocused: handler.isFocused(at: rowIndex) && tableHasFocus,
                isSelected: handler.drawsSelected(at: rowIndex),
                columnWidths: rows.columnWidths, context: context, palette: palette)
            var row = rendered
            // A top clip means the top row enters partially, its first lines
            // scrolled off above the viewport. Clip by the WINDOW's resolved
            // origin, not the handler's raw state — the window may have
            // absorbed a one-line clip (drawing the line instead of a "▲ 1
            // more" indicator), and clipping it here anyway made that line
            // silently vanish while every row sat one line above its hit band.
            if rowIndex == window.range.lowerBound, window.topClip > 0 {
                // Total by `max(0, …)`: the same guard `_ListCore.clipRow` carries,
                // for the same reason — `clampTopClip()` keeps a zero-line row's clip at
                // zero, and `removeFirst(-1)` would trap if that ever stopped holding.
                row = row.droppingFirst(min(window.topClip, max(0, row.lines.count - 1)))
            }
            // …and the bottom row leaves partially, clipped at the budget.
            let remaining = rowLineBudget - rowLinesEmitted
            if remaining <= 0 { break }
            if row.lines.count > remaining { row = row.keepingFirst(remaining) }
            if !row.payload.isEmpty {
                rowPayload.append(row.payload.shifted(byX: 0, y: slidableRows.count))
            }
            collect(row, into: &slidableRows, runs: &pulseRuns, claims: &rowOpacity)
            rowLinesEmitted += row.lines.count
        }
        // The rows' own coordinates start below whatever indicator lines are
        // already in `lines`; `slid` shifts them by −excursion, exactly as the
        // bands are shifted elsewhere.
        let rowsTop = lines.count
        lines.append(contentsOf: handler.overscrollState.slid(
            slidableRows, blank: String.spaces(max(0, contentWidth))))
        // `slid` keeps the count, so this is the block's end whatever the
        // excursion — short of `contentHeight` by the "▼ N more below" line
        // appended next and by any padding after that.
        let rowsEnd = rowsTop + slidableRows.count
        let runs = rowRuns(
            pulseRuns, slide: -handler.overscrollState.excursion, topOffset: rowsTop,
            lineCount: rowsEnd)
        let claims = rowClaims(
            rowOpacity, slide: -handler.overscrollState.excursion, topOffset: rowsTop,
            lineCount: rowsEnd)
        let payload = rowPayloads(
            rowPayload, slide: -handler.overscrollState.excursion, topOffset: rowsTop,
            lineCount: rowsEnd)
        if window.reservesBelow {
            let indicator = renderScrollIndicator(
                direction: .down, count: data.count - window.range.upperBound,
                unit: .rows,
                width: contentWidth, palette: palette, cycle: indicatorCycle, flash: indicatorFlash,
                over: indicatorSurface, locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // A scrolled/overflowing table fills its content area EXACTLY,
        // whatever the granularity: whole rows can underfill under row
        // granularity, so pad the shortfall — a fixed-height table's frame
        // must not breathe as rows of different heights scroll through.
        // A non-overflowing table keeps its natural, content-sized height, unless
        // it was GIVEN one — which `renderToBuffer` handles for both paths at once.
        if window.showsAbove || window.showsBelow || window.topClip > 0
            || window.reservesAbove || window.reservesBelow
        {
            while lines.count < contentHeight {
                lines.append(String.spaces(contentWidth))
            }
        }
        guard showsBar else {
            return (lines, runs + chromeRuns, claims + chromeClaims, payload, rowsEnd)
        }
        // The bar is the rightmost interior column, merged in by absolute line
        // index so an overscroll slide moves the rows and leaves it where it
        // is (§1.5) — the same composition the single-line path uses, claims
        // included: plain track below a bar shorter than the lines, and the
        // bar's claims on its own column, unslid.
        while lines.count < contentHeight {
            lines.append(String.spaces(contentWidth))
        }
        var bar = bar
        bar.fit(toCount: lines.count, field: ScrollbarColors.track(in: palette))
        return (
            zip(lines, bar.lines).map { $0 + $1 },
            runs + chromeRuns, claims + chromeClaims + bar.claims(atColumn: contentWidth), payload,
            rowsEnd)
    }

    /// Renders one (possibly multi-line) row: the selection indicator on the first
    /// line, each column's wrapped cell lines beneath it, shorter cells padded with
    /// blank lines, and the selection/focus background spanning every line.
    ///
    /// Takes the row's `layout` rather than the row: the caller's window walk had to
    /// wrap the cells to learn the row's HEIGHT before it could decide the row was
    /// visible at all, so wrapping them again here to draw them was the same work a
    /// second time — see `buildMultiLineContent`'s layout memo.
    private func renderMultiLineRow(
        layout: MultiLineRowLayout,
        paint: RowPaint,
        isFocused: Bool,
        isSelected: Bool,
        columnWidths: [Int],
        context: RenderContext,
        palette: any Palette
    ) -> RenderedRow {
        context.renderCache?.rowWork.rendered += 1  // see `renderRow`
        let (row, ramp, rowWidth) = (paint.row, paint.ramp, paint.width)
        let gutter = selectionGutter(context.environment)
        let spacing = asciiSpaces(columnSpacing)
        let visual = rowVisualState(
            isFocused: isFocused, isSelected: isSelected,
            stripe: paint.stripe,
            context: context, palette: palette)
        // See `renderRow`: one step of the ramp per ROW, so every line of a
        // wrapped row shares its colour, and a ramp that varies along the row
        // paints cell by cell instead.
        let bandsAcrossRow = ramp?.variesAcrossRow ?? false
        let foreground = cellColour(row: row, ramp: ramp, context: context, palette: palette)
        let isDimmed = selectionDisabledRows.contains(row)

        // One SGR introducer for every cell of every line — see ``renderRow``,
        // which this is the multi-line twin of. Here it matters more: the
        // per-cell colorize and the per-line array-plus-join ran once per LINE
        // per row, so `table-multiline` was the one table shape that did not
        // move when `renderRow` was rewritten.
        var cellStyle = TextStyle()
        cellStyle.foregroundColor = foreground.opaqueSpelling
        // The cells are text: a tier heavier under a bold legibility weight.
        let boldCells = context.environment.legibilityWeight.drawsPlainBold
        if boldCells { cellStyle.isBold = true }
        let cellSequence = bandsAcrossRow ? nil : ANSIRenderer.styleSequence(for: cellStyle)
        var rampSequences: [String?] = []
        // Each line states the ink once per run of plain cells (`TableRowInk`),
        // and starts with none in force.
        let rowInk = TableRowInk(
            introducer: cellSequence, under: visual.background, bandsAcrossRow: bandsAcrossRow,
            insideListRow: context.environment.listRowEditRestrictions != nil, bold: boldCells)
        let cellCount = min(columns.count, columnWidths.count)
        var claims: [OpacityRegion] = []

        var lines: [String] = []
        lines.reserveCapacity(layout.cellHeight)
        // Only a breathing row needs its lines kept bare: everything else would
        // be an array built per row per frame and thrown away.
        let framePaints = visual.background.framePaints
        // Hoisted out of the per-line loop: `claimableFill` is a switch, and both the
        // claim and the fill below want the same answer for every line of the row.
        let claimableFill = framePaints == nil ? visual.background.claimableFill : nil
        /// The same lines WITHOUT their background, kept so a pulse can be
        /// applied to each of them per step (see the single-line path).
        var bareLines: [String] = []
        for lineIndex in 0..<layout.cellHeight {
            // The indicator shows only on the first line; continuation lines keep
            // the same gutter so the columns line up beneath it. A table with
            // nothing to mark has no gutter at all, and both are empty.
            var content = ""
            content.reserveCapacity(rowWidth * 2)
            var ink = rowInk
            if gutter > 0, lineIndex == 0 {
                ink.appendMark(visual.indicator, in: visual.indicatorColor.opaqueSpelling, into: &content)
                content += " "
            } else if gutter > 0 {
                content.append(contentsOf: asciiSpaces(gutter))
            }

            var cellColumn = gutter
            for index in 0..<cellCount {
                if index > 0 {
                    content.append(contentsOf: spacing)
                    cellColumn += columnSpacing
                }
                let column = columns[index]
                let cellWidth = columnWidths[index]
                let cellLines = layout.cells[index]
                let text = lineIndex < cellLines.count ? cellLines[lineIndex] : ""
                if let ramp, bandsAcrossRow {
                    var walked = cellColumn
                    PaintRenderer.band(
                        alignText(
                            text, width: cellWidth, alignment: column.alignment,
                            truncationMode: column.truncationMode),
                        column: &walked, row: row, style: cellStyle,
                        sampler: ramp, sequences: &rampSequences, into: &content)
                } else {
                    ink.open(before: text, into: &content)
                    appendAligned(
                        text, width: cellWidth, alignment: column.alignment,
                        truncationMode: column.truncationMode, into: &content)
                    ink.close(after: text, into: &content)
                }
                cellColumn += cellWidth
            }
            ink.finish(into: &content)

            // Row-local, and per LINE: the mark is on the first line only, as the
            // badge is — a tall row is one entry in the list, and one entry earns one
            // mark.
            claims += SelectableRowClaims.claims(
                line: lineIndex, width: rowWidth, cells: gutter..<cellColumn,
                ink: bandsAcrossRow ? nil : foreground,
                mark: gutter > 0 && lineIndex == 0 ? visual.indicatorColor : nil,
                fill: claimableFill)
            // A banded row's ink is not one colour, so it is not one rectangle: the
            // ramp answers per cell and the claim is a run per equal alpha across the
            // span the cells actually occupy. Every line of a tall row shares the
            // ramp's row step (see `bandsAcrossRow` above), so they share the runs too.
            if let ramp, bandsAcrossRow {
                claims += ramp.alphaClaims(
                    row: row, line: lineIndex, columns: gutter..<cellColumn)
            }
            // A row that refuses selection draws faint, under whatever
            // background it wears — as a `List` row does.
            if isDimmed { content = ANSIRenderer.applyPersistentDim(content) }
            guard case .none = visual.background else {
                // `cellColumn` IS this line's visible width, as on the single-line
                // path (`renderRowUncached`): the cells loop walked it from the
                // gutter through every spacing and column. Not rescanned — a still
                // background is every other row of a table that stripes — and the
                // padding goes inside the paint, not into a copy of the line.
                assert(cellColumn == content.strippedLength, "a multi-line row's cells drew \(content.strippedLength) cells, not \(cellColumn)")
                let padding = rowWidth - cellColumn
                guard framePaints == nil else {
                    content.append(contentsOf: asciiSpaces(padding))
                    bareLines.append(content)
                    lines.append(visual.background.painting(content))
                    continue
                }
                lines.append(visual.background.painting(content, padding: padding))
                continue
            }
            // To the row's width, which is past its cells before a scrollbar by
            // the spacing kept clear of it (`View.scrollbarSpacing(_:)`).
            if rowWidth > cellColumn { content.append(contentsOf: asciiSpaces(rowWidth - cellColumn)) }
            lines.append(content)
        }
        // Same recolour-the-finished-line trick the single-line path uses: one
        // recolouring per step, not one render of the row per step.
        let rendered = RenderedRow(
            lines: lines,
            pulseFrames: framePaints.map { paints in bareLines.map { bare in paints.map { $0.painting(bare) } } },
            pulseTiming: framePaints == nil ? nil : visual.background.pulseTiming,
            claims: claims, payload: layout.payload)
        return rendered.within(above: layout.above, below: layout.below)
    }

    /// Hands the handler this frame's row actions: one call for both layout
    /// paths, so what a row can do cannot differ between them.
    private func syncRowActions(_ handler: ItemListHandler<Value.ID>, context: RenderContext) {
        handler.primaryAction = rowActivation(handler, context: context)
        handler.openContextMenu = keyboardMenuOpener(handler, context: context)
        handler.outlineActivation = outline
        handler.selectionDisabledRows = selectionDisabledRows
        handler.onMove = moveAction
        handler.onSort = sortKeyAction
        handler.columnEditing = columnEditing(handler, context: context)
        // A picked column that has gone — hidden from its own menu — hands
        // the pick to the first column left, before the header draws it, so
        // the mode the status bar still advertises has a column on screen.
        if !context.isMeasuring, let focus = handler.columnFocus {
            let shown = handler.columnEditing?.columns ?? []
            if !shown.contains(focus) { handler.columnFocus = shown.first }
        }
    }

    // MARK: - Row menus

    /// The selection menu around this table, when it is this table's.
    private func selectionMenu(_ environment: EnvironmentValues) -> SelectionContextMenu? {
        RowContextMenuHost.selectionMenu(in: environment, rowsIdentifiedBy: Value.ID.self)
    }

    /// The row menu's state, at this table's identity.
    private func rowMenuBox(_ context: RenderContext) -> StateBox<RowMenuState>? {
        RowContextMenuHost.stateBox(context, propertyIndex: StateIndex.rowMenu)
    }

    /// What a secondary click on row `index` — or Shift+F10 with the cursor
    /// on it — opens: the selection menu, by its rule, when there is one;
    /// else the row's own menu; else nothing, `nil`.
    private func rowMenuTarget(
        ofRow index: Int?, handler: ItemListHandler<Value.ID>, selection: SelectionContextMenu?
    ) -> RowMenuTarget? {
        if selection != nil {
            return .selection(RowContextMenuHost.targets(ofRow: index, in: handler))
        }
        guard let index, let traits = rowTraits, traits.indices.contains(index),
            traits[index].contextMenu != nil, let id = handler.id(at: index)
        else { return nil }
        return .row(AnyHashable(id))
    }

    /// The menu `target` opens to, built now — `nil` for a row that has gone.
    private func rowMenuItems(_ target: RowMenuTarget, selection: SelectionContextMenu?) -> AnyView? {
        switch target {
        case .selection(let ids):
            return selection?.menu(for: ids)
        case .row(let id):
            guard let traits = rowTraits,
                let index = data.firstIndex(where: { AnyHashable($0.id) == id }),
                traits.indices.contains(index)
            else { return nil }
            return traits[index].contextMenu?()
        }
    }

    /// What Return and a double-click do to a row — see
    /// ``RowContextMenuHost/activation(for:selection:)``.
    private func rowActivation(
        _ handler: ItemListHandler<Value.ID>, context: RenderContext
    ) -> ((Value.ID) -> Void)? {
        RowContextMenuHost.activation(for: handler, selection: selectionMenu(context.environment))
    }

    /// Shift+F10's half: opens the row menu on the cursor row. `nil` for a
    /// table with no menu, so the chord falls through.
    private func keyboardMenuOpener(
        _ handler: ItemListHandler<Value.ID>, context: RenderContext
    ) -> (() -> Bool)? {
        let selection = selectionMenu(context.environment)
        guard selection != nil || hasRowMenus, let box = rowMenuBox(context) else { return nil }
        let onOpen = context.environment.menuOpenAction
        return { [weak handler] in
            guard let handler,
                let target = rowMenuTarget(
                    ofRow: handler.focusedIndex, handler: handler, selection: selection)
            else { return false }
            RowContextMenuHost.openByKeyboard(box, target: target, onOpen: onOpen)
            return true
        }
    }

    /// The pointer's half: opens the row menu on a row (or on none) at a
    /// press. `nil` for a table with no menu.
    private func pointerMenu(
        handler: ItemListHandler<Value.ID>, context: RenderContext,
        dispatcher: MouseEventDispatcher, contentColumns: Range<Int>, contentLines: Range<Int>,
        opened: @escaping @MainActor () -> Void
    ) -> RowContextMenuHost.PointerMenu? {
        let selection = selectionMenu(context.environment)
        guard selection != nil || hasRowMenus, let box = rowMenuBox(context) else { return nil }
        let onOpen = context.environment.menuOpenAction
        return RowContextMenuHost.PointerMenu(
            open: { index, x, y in
                guard let target = rowMenuTarget(ofRow: index, handler: handler, selection: selection)
                else { return false }
                RowContextMenuHost.openByPointer(
                    box, target: target, x: x, y: y, dispatcher: dispatcher, onOpen: onOpen)
                return true
            },
            isOpen: { box.value.menu.isOpen }, contentColumns: contentColumns,
            contentLines: contentLines, opened: opened)
    }

    /// Draws the open row menu over the table — anchored at the press, or
    /// under the cursor row when the keyboard opened it — or tears down the
    /// section a closed one left.
    private func presentRowMenu(
        over buffer: inout FrameBuffer, state: PopulatedRenderState, context: RenderContext
    ) {
        let selection = selectionMenu(context.environment)
        guard !context.isMeasuring, selection != nil || hasRowMenus, let box = rowMenuBox(context)
        else { return }
        let cursor = state.handler.focusedIndex
        let interiorTopY = borderWidth(context.environment) + headerLines(context.environment)
        let rowLeft =
            borderWidth(context.environment) + Self.containerPadding.leading
            + selectionGutter(context.environment)
        let anchor = state.drawnBands.first {
            if case .row(let index) = $0.entry { return index == cursor }
            return false
        }.map { (x: rowLeft, y: interiorTopY + $0.yStart, height: max(1, $0.height)) }
        RowContextMenuHost.present(
            items: rowMenuItems(box.value.target, selection: selection), over: &buffer,
            stateBox: box, sectionID: "tablemenu-\(context.identity.path)", keyboardAnchor: anchor,
            context: context)
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs.
    /// - Parameter overflows: Whether the rows overflow `contentHeight`, given
    ///   the extra lines they must share it with — 1 while a hovering drag is
    ///   drawing a landing slot, 0 otherwise. A closure rather than a `Bool`
    ///   because the answer depends on ``ItemListHandler/dropSlotAddsRow``,
    ///   which is a question about the handler this call is still resolving.
    /// - Returns: The handler and the overflow answer, which the caller needs
    ///   for its indicator reservation and cannot compute itself.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int,
        overflows: (Int) -> Bool,
        showsScrollbar: Bool = false
    ) -> (handler: ItemListHandler<Value.ID>, overflowing: Bool) {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: data.count,
                // Provisional: replaced below once the overflow answer exists,
                // and again by the caller once the offset is known.
                viewportHeight: contentHeight,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        refresh(handler, context: context)
        // A drag from elsewhere draws its landing slot as an extra line —
        // nothing left this table to make room for it. `Table` has no
        // same-table case to exclude: its rows are built from `data`, so they
        // cannot be `.draggable`.
        // A landing slot occupies a line whoever opened it. A drag of this
        // control's OWN rows pays for it with the lines those rows gave up —
        // but only while those rows are still in the window, which is the
        // question ``ItemListHandler/reorderSlotNeedsALine`` answers.
        handler.dropSlotAddsRow = handler.externalDropSlot != nil || handler.reorderSlotNeedsALine
        handler.syncReturningRows(with: context.environment.dragAndDropSession)
        let overflowing = overflows(handler.dropSlotAddsRow ? 1 : 0)
        // Clamp against the largest possible visible-row count (one
        // indicator, at an end); the exact viewport is finalised by
        // the caller once the offset is known.
        //
        // ROWS, like the exact one — minus the landing slot's line, which the
        // content height still contains. Without that subtraction the two
        // writes to `viewportHeight` mean different things (this one an entry
        // capacity, `reserveIndicatorLines`' a row count) and the bound taken
        // from this one is a row too TIGHT: `clampScrollOffset` then ejected
        // the offset auto-scroll had just reached, every frame, and the drag
        // stopped one row short of the end for ever.
        let provisionalViewport =
            max(1, (overflowing ? contentHeight - 1 : contentHeight)
                - (handler.dropSlotAddsRow ? 1 : 0))
        handler.contentHeight = contentHeight
        // A scrollbar reserves no indicator line, so the focus-reveal / offset
        // arithmetic must claim the full content height (matches the List path).
        handler.showsScrollbar = showsScrollbar
        // …and neither does a table whose indicators are hidden. The bar path
        // passes `showsScrollbar: true` and composes its own rows, so this is
        // the "N more" answer for both.
        let drawsText = drawsTextIndicators(
            showsScrollbar, context, contentHeight: contentHeight)
        // `.visible` asks for the affordance, not for a hint that appears when it
        // has something to say — so the overflow test does not gate it.
        handler.alwaysReservesIndicatorLines =
            drawsText && !showsScrollbar
            && context.environment.alwaysShowsVerticalTextIndicators
        handler.drawsScrollIndicators =
            drawsText && (overflowing || handler.alwaysReservesIndicatorLines)
        // Provisional, and RENDER-ONLY for the reason `reserveIndicatorLines`
        // spells out: a measure pass is handed a height the frame may not get,
        // and this value outlives the pass that wrote it.
        if !context.isMeasuring { handler.viewportHeight = provisionalViewport }
        handler.canBeFocused = !isDisabled(in: context)
        syncRowActions(handler, context: context)
        // BEFORE the rows are composed — see the List's twin call site.
        handler.carryReorderTargetThroughAutoScroll()
        // Everything the handler's EVENTS will read out of the environment, in
        // one shared call — see `ItemListHandler.syncFrameInputs`, which exists
        // because this block used to be hand-copied here, in
        // `buildMultiLineContent` and in `_ListCore`, and a capture added to one
        // of the three was silently dead on the other two.
        //
        // `rowHeight: nil` — uniform single-line rows, so the scroll arithmetic
        // counts rows and the granularity is moot (it is still captured, and any
        // stale clip zeroed below, in case a table's rows switch between this
        // path and the multi-line one across frames).
        //
        // `keyboardMoveIsLive: false` — this path's composer DOES draw a reorder
        // slot, so the faint copy at it is the preview. Stated rather than left
        // alone because the handler persists at one identity: a table whose
        // columns stop reporting `lineLimit > 1` arrives here still carrying the
        // other path's `true`.
        handler.syncFrameInputs(
            environment: context.environment,
            reorderFeedback: context.environment.rowReorderFeedback,
            keyboardMoveIsLive: false,
            rowHeight: nil)
        handler.resolveOverscroll(context: context, contentHeight: contentHeight)
        // Resolve row ids lazily: the selection handler only ever asks for the
        // visible window + the focused row (O(1) each via `data[index].id`), so
        // materialising a full id array here was O(total) waste — and `_TableCore`
        // is render-to-measure, so it ran in *both* the measure and render passes
        // every frame (~30% of the 20k-row frame). All Table rows are content, so
        // an empty `selectableIndices` already means "all selectable". Mirrors the
        // windowed List path (_ListCore.resolvePopulatedHandler).
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        resolveScrollTo(handler, rows: data, context: context)
        // As the multi-line path — see `settleScrollPosition`. Rows here are one
        // line each, so the snap's line-granularity exception can never apply.
        handler.settleScrollPosition(
            measuring: context.isMeasuring, overflowing: overflowing,
            drawsTextIndicators: handler.drawsScrollIndicators,
            firstRowHeight: 1)
        bindSelection(handler, context: context)
        return (handler, overflowing)
    }

    /// Hands the handler the selection it writes, and a collapsed split's way
    /// to its next column where the table is in the column on top of one — the
    /// same on both of the table's paths.
    private func bindSelection(_ handler: ItemListHandler<Value.ID>, context: RenderContext) {
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        handler.compactColumnAdvance = context.environment.compactColumnAdvance
    }

    /// `ScrollViewProxy.scrollTo` reaching the table, as it reaches a `List`:
    /// the handler registered each render with the reader around it, and the
    /// request it parks placed against this frame's rows, found by their ids,
    /// before the offset settles.
    private func resolveScrollTo(_ handler: ItemListHandler<Value.ID>, rows: [Value], context: RenderContext) {
        guard !context.isMeasuring else { return }
        context.environment.scrollToRegistry?.register(
            handler: handler, identity: context.identity, renderCache: context.renderCache)
        guard let request = handler.pendingScrollTo else { return }
        handler.pendingScrollTo = nil
        if let index = rows.firstIndex(where: { identityKey($0.id) == request.key }) {
            handler.scroll(toRow: index, anchor: request.anchor)
        }
    }

    /// The table's content width: the selection gutter plus the columns and their
    /// spacing, clamped to the interior. Focused-row backgrounds and indicators are
    /// padded to *this*, not the full interior, so every line is the same width and
    /// the table neither jumps wider on focus nor centres its header over a lone
    /// full-width row. A `.flexible` column already fills the interior, so there the
    /// two widths coincide and nothing changes.
    private func tableContentWidth(
        _ columnWidths: [Int], within innerWidth: Int, gutter: Int
    ) -> Int {
        let spacing = columnSpacing * max(0, columnWidths.count - 1)
        return min(innerWidth, gutter + columnWidths.reduce(0, +) + spacing)
    }

    /// Reserves a line for each scroll indicator actually present at this
    /// offset so the rows plus indicators fill the content area exactly — no
    /// wasted blank line at the ends (which used to push the "N more below"
    /// indicator one row too high), no overflow in the middle. Mirrors
    /// _ListCore. Shared by the render pass and the analytic measure (both
    /// must agree on which indicators show).
    @discardableResult
    private func reserveIndicatorLines(
        handler: ItemListHandler<Value.ID>, contentHeight: Int, context: RenderContext
    ) -> (viewport: Int, origin: Int, above: Bool, below: Bool) {
        // Nothing is set aside when the "N more" lines are not what this table
        // draws — hidden indicators cost nothing, and the bar path never calls
        // this at all.
        // The shared rule, at uniform height — the same one the multi-line path
        // and `_ListCore` ask, which is what stops the three drifting. Every row
        // is one line here, so what it works out in lines this path reads as a
        // count. It absorbs the top clip too (at offset 1 a "▲ 1 more" line would
        // hide exactly the one row it stands for, so the window draws from row 0
        // instead — the resting settle normally snaps 1 → 0 before render, but
        // deliberately not while steering, which is when offset 1 survives here).
        let window = ScrollRowWindow.resolve(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, topClip: 0,
            drawsTextIndicators: handler.drawsScrollIndicators,
            alwaysDrawsIndicators: context.environment.alwaysShowsVerticalTextIndicators,
            height: { _ in 1 })
        let origin = window.range.lowerBound
        let viewport = max(1, window.range.count)
        // A MEASURE pass must not publish either of these. It is offered a
        // different height than the frame is finally drawn into — the analytic
        // path measures at the full row area while the render subtracts the
        // landing slot's line — so a measure that wrote `viewportHeight` left
        // the NEXT render's `clampScrollOffset` (which asks `maxOffset`, which
        // asks the viewport) working from a viewport belonging to another
        // proposal. Symptom: auto-scroll advanced a row per tick and the very
        // next frame pulled it straight back, so a drag stopped one row short
        // of the end for ever. It is the measure-side-effect class, and it was
        // invisible until the borrowed slot line made the two viewports differ.
        if !context.isMeasuring {
            handler.viewportHeight = viewport
            // Published for the same reason the scrollbar path does — and the
            // indicators and the row window below count from it.
            handler.drawnOffset = origin
        }
        // Which lines the viewport gave up is RETURNED, not published: the
        // composer needs the answer for THIS pass, and the handler is the wrong
        // place to keep it. Latched there it had two failure modes, and both
        // shipped. A measure pass does not publish (see above), so the composer
        // read `(false, false)` and drew no indicator lines — a table measured
        // two lines shorter than it drew, and a container that believed the
        // measurement gave it a viewport two lines too short. And a frame that
        // skips the reservation entirely — the table stopped overflowing, and
        // `scrollOffset` did not change, so its didSet did not clear the latch —
        // read the PREVIOUS frame's answer and drew "▼ 0 more rows below" under
        // a table with nothing below it.
        return (viewport, origin, window.reservesAbove, window.reservesBelow)
    }

    /// The interaction state of a table with no rows: a real handler (its
    /// `itemCount` freshly zeroed, so the count from its last populated frame
    /// cannot leak into a later index), an empty visible range, no rows.
    ///
    /// It registers focus exactly as the populated path does — an empty table is
    /// still a Tab stop, and an enclosing `ScrollView` still has to be able to
    /// find it to reveal it.
    private func emptyRenderState(
        context: RenderContext,
        stateStorage: StateStorage,
        contentHeight: Int
    ) -> PopulatedRenderState {
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "table",
            propertyIndex: StateIndex.focusID
        )
        let (handler, _) = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: contentHeight,
            overflows: { _ in false }
        )
        // The empty path used to be the one that forgot `isFocusEngaged`, so an
        // emptied table kept whatever its last populated frame left. It cannot
        // now: the four statements are one call.
        handler.engageFocus(context: context, focusID: persistedFocusID)
        // Clears the bands the last populated frame left behind, so nothing
        // hit-tests against rows that are no longer drawn.
        handler.publishRowBands([])
        return PopulatedRenderState(
            handler: handler,
            focusID: persistedFocusID,
            visibleRange: 0..<0,
            scrollOffsetAbove: 0,
            drawnBands: []
        )
    }

    /// Stitches scroll indicators around the visible data rows.
    private func composeRowLines(
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        /// Which indicator lines this pass's window set aside — see
        /// `reserveIndicatorLines`, which is the only thing that can answer it.
        indicators: (above: Bool, below: Bool),
        columnWidths: [Int],
        innerWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> (
        lines: [String], rowLines: [String], runs: [AnimatedCellRun],
        claims: [OpacityRegion], payload: _TableRowPayload,
        bands: [ItemListHandler<Value.ID>.DrawnBand]
    ) {
        let gutter = selectionGutter(context.environment)
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
        // Resolve the emphasis ONLY when an indicator will actually be drawn:
        // resolving consults the cursor clock, and that read is what tells the
        // demand-driven loop the frame consumed it. Asking before knowing
        // whether anything will be painted re-renders the whole page ~20 times
        // a second to draw nothing. Same class as the Stepper's ungated
        // `pulsePhase` read (8ebc3385).
        // …and only when they are this table's indicator at all: hidden ones
        // draw nothing, and the bar has its own compose path.
        let drawnAbove = handler.drawnOffset
        let drawnBelow = max(0, handler.itemCount - handler.drawnVisibleRange.upperBound)

        let indicatorCycle =
            indicators.above || indicators.below
            ? scrollIndicatorCycle(isFocused: tableHasFocus, context: context) : nil
        // A flash (`scrollIndicatorsFlash`), asked only when a line is drawn.
        let indicatorFlash =
            indicators.above || indicators.below ? handler.indicatorFlash.strength(context: context) : nil
        let numberLocale = context.environment.locale
        let indicatorSurface = context.environment.enclosingSurface
        // The "N more" indicators are chrome — they describe where the content
        // sits — so the rows are collected separately and only they slide (§1.5).
        var lines: [String] = []
        var rowLines: [String] = []
        /// The indicators' own runs, at the assembled lines they were appended
        /// to — the rows slide past them, so those positions are final.
        var chromeRuns: [AnimatedCellRun] = []
        /// …and their claims, placed the same way (§53).
        var chromeClaims: [OpacityRegion] = []
        if indicators.above {
            let indicator = renderScrollIndicator(
                direction: .up, count: drawnAbove, unit: .rows, width: contentWidth,
                palette: palette, cycle: indicatorCycle, flash: indicatorFlash, over: indicatorSurface,
                locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        let visibleRange = handler.drawnVisibleRange
        // A reorder drag takes the dragged row out and opens a slot where it
        // would land, so what is DRAWN is the order a drop would produce. The
        // sequence (and the arithmetic behind it) is the handler's, shared with
        // `List`; outside a drag it is just the visible range.
        let drawn = handler.reorderDrawnRows(visibleRange)
        // Heights, not entries, drive the bands: the slot stands for every row
        // in hand, so a multi-row drag opens a gap several lines tall and the
        // rows after it are no longer one line per entry.
        var drawnHeights: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)] = []
        /// The breathing rows' lines and every frame of each, at their position
        /// among `rowLines` — see `collect`.
        var pulseRuns: [PulseRun] = []
        var rowOpacity: [OpacityRegion] = []
        /// The rows' cell payloads, at their position among `rowLines`.
        var rowPayload = _TableRowPayload()
        // One sampler for the frame — see the twin in the single-line path.
        let rowRamp = cellRamp(rowWidth: contentWidth, context: context)
        let rowStripe = Self.frameStripe(context: context, palette: palette)
        beginRowMemo(
            handler: handler, columnWidths: columnWidths,
            gutter: selectionGutter(context.environment), rowWidth: contentWidth,
            stripe: rowStripe, context: context, palette: palette)
        for entry in drawn {
            switch entry {
            case .row(let rowIndex):
                let row = renderRow(
                    item: data[rowIndex],
                    paint: RowPaint(row: rowIndex, ramp: rowRamp, stripe: rowStripe, width: contentWidth),
                    columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.drawsSelected(at: rowIndex),
                    isReturningHome: handler.returningRows.contains(rowIndex),
                    context: context,
                    palette: palette,
                    memo: handler
                )
                if !row.payload.isEmpty {
                    rowPayload.append(row.payload.shifted(byX: 0, y: rowLines.count))
                }
                collect(
                    line: row.line, frames: row.pulseFrames, timing: row.pulseTiming, claims: row.claims,
                    into: &rowLines, runs: &pulseRuns, claims: &rowOpacity)
                drawnHeights.append((entry, 1))
            case .slot:
                let slot = reorderSlotLines(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentWidth,
                    context: context, palette: palette)
                collect(slot, into: &rowLines, runs: &pulseRuns, claims: &rowOpacity)
                drawnHeights.append((entry, slot.lines.count))
            }
        }
        // A drag never changes how much is on screen, so an overrun is clipped —
        // but never the SLOT. It overruns when rows in hand have scrolled out of
        // the visible range, and when the slot is the last entry (the "move to
        // the end" destination) the tail IS the slot: clipping it took away the
        // only thing on screen saying where the rows would land, which reads as
        // the selection falling off the bottom of the table.
        // Negated excursion for the same reason as the scrollbar path above:
        // bands must travel WITH the slid rows, not mirror them.
        // Rows PLUS the line the slot borrowed (``dropSlotAddsRow``). Clipping
        // to the row count alone dropped a real row instead: the slot is
        // deliberately never the thing clipped, so the overrun came out of the
        // rows — a full table showed the slot and the indicator and no rows at
        // all, while the reserve arithmetic said one should be visible.
        let drawnBudget = visibleRange.count + (handler.dropSlotAddsRow ? 1 : 0)
        let slide =
            clipOverrun(&rowLines, to: drawnBudget, drawn: drawnHeights)
            - handler.overscrollState.excursion
        // …and a SHORTFALL is filled, for the same reason the overrun is
        // clipped: a drag never changes how much is on screen. `.cursor` drops
        // its gap the moment the pointer leaves the rows while the rows it is
        // carrying stay out of the drawing, so those frames are a line short —
        // and a table that is one line shorter is a table whose bottom border
        // has stepped up over the last row, which is then not where the user is
        // aiming at it. Dragging below the last row and back onto it therefore
        // released onto the BORDER, and `.cursor` reads a release off the rows
        // as a cancel: the row flew home and the reorder was silently lost.
        // Outside a drag the rows are one line each and this adds nothing.
        // (The scrollbar path fills to its own `contentHeight` already.)
        while rowLines.count < drawnBudget {
            rowLines.append(String.spaces(max(0, contentWidth)))
        }
        let bands = publishRowBands(
            handler: handler, drawn: drawnHeights, slide: slide,
            // Whatever chrome is already in `lines` — which at this point is
            // the "N more above" indicator and nothing else, since the rows go
            // in on the next statement and the "below" indicator after them.
            // Counted rather than re-derived from a predicate so it cannot
            // disagree with what was drawn.
            indicatorLines: lines.count, lineCount: lines.count + rowLines.count)
        // The rows start below whatever "N more above" indicator is already in
        // `lines`; their runs take the same slide the bands just did.
        let rowsTop = lines.count
        lines.append(contentsOf: handler.overscrollState.slid(
            rowLines, blank: String.spaces(max(0, contentWidth))))
        let runs = rowRuns(
            pulseRuns, slide: slide, topOffset: rowsTop, lineCount: rowsTop + rowLines.count)
        let claims = rowClaims(
            rowOpacity, slide: slide, topOffset: rowsTop, lineCount: rowsTop + rowLines.count)
        let payload = rowPayloads(
            rowPayload, slide: slide, topOffset: rowsTop, lineCount: rowsTop + rowLines.count)
        if indicators.below {
            let indicator = renderScrollIndicator(
                direction: .down, count: drawnBelow, unit: .rows, width: contentWidth,
                palette: palette, cycle: indicatorCycle, flash: indicatorFlash, over: indicatorSurface,
                locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // The row lines are handed back separately for a `.cursor` drag's
        // floating preview; the press frame is drawn in plain data order, so
        // indexing them by `visibleRange` offset is exact.
        return (
            lines, handler.onMove == nil ? [] : rowLines, runs + chromeRuns, claims + chromeClaims,
            payload, bands)
    }

    // MARK: - Reorder drag

    /// The drop slot's line: a faint copy of the dragged row under
    /// ``RowReorderFeedback/dimmed``, and a gap the row's size under
    /// ``RowReorderFeedback/cursor`` (which has the row itself on the pointer, so
    /// drawing it here too would read as a duplicate).
    private func reorderSlotLines(
        handler: ItemListHandler<Value.ID>,
        columnWidths: [Int],
        rowWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> RenderedRow {
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it: the row you are steering reads as emphasis, not as a hole.
        // (`isFocused` rather than a bespoke colour — the pulse a focused row
        // already uses is exactly the "this one" cue, and it walks the palette
        // ramp so it survives a 256-colour terminal.)
        let held = handler.isKeyboardMove
        // EVERY row in hand: they land as one block, so the slot is one gap the
        // size of all of them. A blank line each under `.cursor` (which carries
        // them on the pointer, where drawing them here too would read as
        // duplicates); a faint copy each under `.dimmed`.
        let sources = handler.reorderRemovedRows.filter { data.indices.contains($0) }
        let blank = String.spaces(max(0, rowWidth))
        guard handler.effectiveReorderFeedback == .dimmed, !sources.isEmpty else {
            // A keyboard move never takes the `.cursor` path: it resolves that
            // to `.dimmed`, precisely because there is no pointer to carry a row.
            return RenderedRow(lines: Array(repeating: blank, count: max(1, sources.count)))
        }
        // The row the cursor is on stays at full strength while the rest of the
        // block goes faint — the slot's pulse covers all of them, so without
        // this a multi-row hold marks no row in particular. `nil` for one row
        // and for every mouse drag: see `reorderPrimaryHeldRow`.
        let primary = handler.reorderPrimaryHeldRow
        let rowRamp = cellRamp(rowWidth: rowWidth, context: context)
        let rowStripe = Self.frameStripe(context: context, palette: palette)
        let rendered = sources.map { source -> (line: String, frames: [String]?, timing: IndicatorCycleTiming?, claims: [OpacityRegion]) in
            let row = renderRow(
                item: data[source],
                paint: RowPaint(row: source, ramp: rowRamp, stripe: rowStripe, width: rowWidth),
                columnWidths: columnWidths,
                isFocused: held, isSelected: held, context: context, palette: palette)
            let line = row.line
            let frames = row.pulseFrames
            guard source != primary else { return (line, frames, row.pulseTiming, row.claims) }
            // ADDITIVE, as it is in `_ListCore`: the emphasis says "you are
            // steering this", the dim says "it is not in the list right now",
            // and both are true at once. Substituting one for the other is why
            // a Table stopped dimming as soon as the move came from the
            // keyboard. Persistent: `renderRow` can reset inside the row —
            // after any cell whose text carries escapes of its own, at the end
            // of its ink where the row has no still fill, and under a reversal
            // after every styled run, starting with the selection mark (see
            // `TableRowInk`) — and a bare wrapper dies at the first reset it
            // meets, as one did at cell one. The dim goes onto every frame of
            // the pulse for the same reason it goes onto the drawn line: a run
            // that replayed the undimmed row would un-dim it on the first tick.
            return (
                ANSIRenderer.applyPersistentDim(line),
                frames.map { $0.map(ANSIRenderer.applyPersistentDim) },
                row.pulseTiming, row.claims)
        }
        return RenderedRow(
            lines: rendered.map(\.line),
            pulseFrames: rendered.contains { $0.frames != nil }
                ? rendered.map { $0.frames ?? [] } : nil,
            // Every copy is held and breathes on the one focus cycle, so any copy's
            // timing is all of theirs.
            pulseTiming: rendered.lazy.compactMap(\.timing).first,
            // Each copy's claims, on its own line of the slot. The dim moves no cell,
            // so they name the cells they did; dropped, a translucent row showed at
            // its opaque spelling for as long as it was held (§52). The claims and
            // not the runs are what the `List` twin's `dimmed(_:)` carries, too.
            claims: rendered.enumerated().flatMap { line, copy in
                copy.claims.map { $0.shifted(byX: 0, y: line) }
            })
    }

    /// Registers the table's rows as a drop destination that reports WHERE —
    /// the ``Table/dropDestination(for:action:)`` half, and the twin of
    /// `_ListCore.registerRowDropDestination`.
    ///
    /// The hovered index goes through the SHARED handler state
    /// (`externalDropSlot`), so the gap it opens is drawn by the same code the
    /// reorder slot uses and lands at the index the drop reports.
    private func registerRowDropDestination(
        zoneID: HitTestRegion.HandlerID,
        state: PopulatedRenderState,
        context: RenderContext,
        interiorTopY: Int
    ) {
        let handler = state.handler
        guard let insertion = dropInsertion,
            let session = context.environment.dragAndDropSession
        else {
            handler.externalDropSlot = nil
            handler.externalDropTakes = nil
            return
        }
        // Where not every slot takes what the rows accept — a hierarchical
        // table whose loops are its branches', say — a slot that does not
        // take the drag in hand opens no gap, and a drop there is refused.
        handler.externalDropTakes = insertion.takes.map { takes in
            { [weak session] slot in session?.active.map { takes(slot, $0.payload) } ?? true }
        }
        // Every move of the slot is reported, as `_ListCore`'s are: the gap is
        // drawn from it, and the drag moves it from outside this render.
        let drawing = HandlerDrawing(context)
        let slot = { handler.externalDropSlot }
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: zoneID,
                accepts: insertion.accepts,
                perform: { payload, _ in
                    // No slot open where the rows refuse the one under the
                    // pointer: refused, and the drag flies home.
                    if insertion.takes != nil, handler.externalDropSlot == nil { return false }
                    drawing.reportingChanges(to: slot) {
                        insertion.perform(handler.takeExternalDropSlot(), [payload])
                    }
                    return true
                },
                setTargeted: { targeted in
                    guard !targeted else { return }
                    drawing.reportingChanges(to: slot) { handler.externalDropSlot = nil }
                },
                hovering: { _, y in
                    // The band under the pointer names the row it would land
                    // BEFORE; past the last row it appends. Measured from the
                    // INTERIOR top, which is the space the bands are in — the
                    // same space `_ListCore` publishes and reads in. Through the
                    // handler so the line is remembered for an auto-scroll tick,
                    // which has no pointer event to go on.
                    drawing.reportingChanges(to: slot) {
                        handler.hoverExternalDrop(atContentY: y - interiorTopY)
                    }
                }),
            in: context)
    }

    /// Appends a rendered row's lines to `lines`, and its pulse frames to
    /// `runs` at the positions those lines landed in.
    ///
    /// One place, because every path that draws rows has to keep the two in
    /// step: a run is spliced over cells by position, so a line appended
    /// without its frames stops breathing, and frames recorded at the wrong
    /// index repaint the row above or below — every tick, until something else
    /// forces a full render.
    ///
    /// `transform` is whatever the path does to each line on the way in (the
    /// scrollbar path pads them to the content width); it is applied to the
    /// frames too, or the run would claim a different span than its line
    /// occupies.
    private func collect(
        line: String, frames: [String]?, timing: IndicatorCycleTiming?,
        claims rowClaims: [OpacityRegion] = [],
        into lines: inout [String], runs: inout [PulseRun],
        claims: inout [OpacityRegion], transform: (String) -> String = { $0 }
    ) {
        if let frames, let timing {
            runs.append((y: lines.count, frames: frames.map(transform), timing: timing))
        }
        // Shifted the way the run's `y` is recorded, and by the same number: a claim
        // at the wrong index fades the row above or below, every frame, exactly as a
        // misrecorded run repaints one. `transform` is not applied — the paths that
        // use it pad on the RIGHT, which adds bare cells a claim does not want.
        //
        // Guarded, because this runs once per drawn row per frame and nearly every
        // row is opaque — the same reason the derivations themselves ask the alphas
        // first.
        if !rowClaims.isEmpty {
            claims += rowClaims.map { $0.shifted(byX: 0, y: lines.count) }
        }
        lines.append(transform(line))
    }

    /// The multi-line form: see the single-line overload above.
    private func collect(
        _ rendered: RenderedRow, into lines: inout [String],
        runs: inout [PulseRun], claims: inout [OpacityRegion],
        transform: (String) -> String = { $0 }
    ) {
        let base = lines.count
        lines.append(contentsOf: rendered.lines.map(transform))
        if !rendered.claims.isEmpty {
            claims += rendered.claims.map { $0.shifted(byX: 0, y: base) }
        }
        guard let pulseFrames = rendered.pulseFrames, let timing = rendered.pulseTiming else { return }
        for (offset, frames) in pulseFrames.enumerated() where !frames.isEmpty {
            runs.append((y: base + offset, frames: frames.map(transform), timing: timing))
        }
    }

    /// Appends a "N more" line to `lines`, with its run and its claims moved to the
    /// row it lands on. Chrome, not a row: the rows slide past it, so the line it is
    /// appended as is where it stays. The one spelling of what all four indicator
    /// sites — two paths, two ends — do.
    private func appendIndicator(
        _ indicator: ScrollIndicatorLine, to lines: inout [String],
        runs: inout [AnimatedCellRun], claims: inout [OpacityRegion]
    ) {
        if let run = indicator.animation { runs.append(run.shifted(byX: 0, y: lines.count)) }
        claims += indicator.claims(atRow: lines.count)
        lines.append(indicator.text)
    }

    /// The collected pulse frames as runs, moved the way the row bands are
    /// moved: by the overscroll `slide`, then past any "N more above" indicator.
    ///
    /// A run whose line was slid off the top, or clipped off the bottom, is
    /// dropped rather than left claiming cells that are no longer its own.
    /// The collected claims, moved exactly as ``rowRuns(_:slide:topOffset:lineCount:)``
    /// moves the runs — the same slide, the same indicator offset, the same drop for a
    /// line that ended up off the top or past the bottom.
    ///
    /// One function beside that one rather than a second spelling of the arithmetic: a
    /// claim and the run on its own row disagreeing about where they are is the same
    /// class of bug as a run and its hit band disagreeing, and that is what `collect`
    /// exists to prevent one level down.
    private func rowClaims(
        _ collected: [OpacityRegion], slide: Int, topOffset: Int, lineCount: Int
    ) -> [OpacityRegion] {
        guard !collected.isEmpty else { return [] }
        return collected.compactMap { claim in
            let y = claim.offsetY + slide + topOffset
            guard y >= topOffset, y < lineCount else { return nil }
            return claim.shifted(byX: 0, y: y - claim.offsetY)
        }
    }

    /// The collected cell payloads, moved exactly as
    /// ``rowClaims(_:slide:topOffset:lineCount:)`` moves the claims: the same
    /// slide, the same indicator offset, and a region trimmed to the lines the
    /// rows still draw — a row slid half off the top answers a click on the
    /// half that is left, as its band does.
    private func rowPayloads(
        _ collected: _TableRowPayload, slide: Int, topOffset: Int, lineCount: Int
    ) -> _TableRowPayload {
        guard !collected.isEmpty else { return collected }
        return collected.shifted(byX: 0, y: slide + topOffset)
            .clipped(toRows: topOffset..<max(topOffset, lineCount))
    }

    @MainActor
    private func rowRuns(
        _ pulseRuns: [PulseRun], slide: Int, topOffset: Int, lineCount: Int
    ) -> [AnimatedCellRun] {
        pulseRuns.compactMap { run in
            let y = run.y + slide + topOffset
            guard y >= topOffset, y < lineCount, let first = run.frames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: y, width: first.strippedLength, frames: run.frames,
                frameTicks: run.timing.frameTicks, clock: run.timing.clock)
        }
    }

    /// Trims `lines` to `budget`, taking the overrun off whichever end is NOT
    /// the drop slot, and reports how far the survivors shifted (negative when
    /// the front was dropped) so the published bands move with them.
    ///
    /// A front clip is reported as a NEGATIVE shift, which `drawnBands` trims
    /// the bands against: a row the clip took entirely is dropped, and one it
    /// cut through keeps a band for the lines it still has. It used to drop both,
    /// which left a partly-clipped row answering no click.
    ///
    /// Reunited with its function; see `publishRowBands` on why that is worth a
    /// commit. WHICH end gives way, and by how much, is
    /// ``ItemListHandler/reorderOverrun(lineCount:budget:endsWithSlot:)`` —
    /// shared with `_ListCore.clipReorderOverrun`, which is the twin. This half
    /// is only the application: the lines are Table's to move, and the caller
    /// carries the shift into the bands.
    private func clipOverrun(
        _ lines: inout [String], to budget: Int,
        drawn: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)]
    ) -> Int {
        let clip = ItemListHandler<Value.ID>.reorderOverrun(
            lineCount: lines.count, budget: budget, endsWithSlot: drawn.last?.entry == .slot)
        if clip.back > 0 { lines.removeLast(clip.back) }
        if clip.front > 0 { lines.removeFirst(clip.front) }
        return -clip.front
    }

    /// Hands this frame's drawn row geometry to the shared publisher.
    ///
    /// `yStart` lands in ``ItemListHandler/DrawnBand/yStart``'s space: lines
    /// from the first CONTENT line of the interior, so `indicatorLines` — the
    /// chrome drawn above the rows — and the overscroll `slide` both go in. The
    /// rows are drawn shifted by the slide, so a drag hit-tests the wrong row
    /// without it.
    ///
    /// This comment spent a while attached to `registerRowDropDestination`
    /// instead, three hundred lines above, having been separated from its
    /// function by an edit that left two doc blocks touching. That is not a
    /// tidiness point: the rule it states — bands must include the slide — is
    /// the one `multiLineRowBands` was written without, and it was written that
    /// way while the rule was sitting on someone else's function where nobody
    /// writing a second publisher would read it. (Fixed in 5d9fbaf2, which put
    /// both views on one band builder; kept here as the reason the rule lives
    /// on the function it governs.)
    @discardableResult
    private func publishRowBands(
        handler: ItemListHandler<Value.ID>,
        drawn: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)],
        slide: Int,
        indicatorLines: Int,
        lineCount: Int
    ) -> [ItemListHandler<Value.ID>.DrawnBand] {
        typealias Handler = ItemListHandler<Value.ID>
        let bands = Handler.drawnBands(
            drawn.map { entry, height in
                switch entry {
                case .row(let rowIndex): return (.row(rowIndex), height)
                case .slot: return (.slot, height)
                }
            },
            slide: slide, rowsTop: indicatorLines, lineCount: lineCount)
        handler.publishRowBands(bands)
        // Handed back as well as published: the frame keeps them on its render
        // state so the click map and the cursor marker read the same geometry
        // the drag does, rather than each deriving its own.
        return bands
    }

    /// Starts the floating preview on the first movement of a `.cursor` drag,
    /// or advances it on every movement after that.
    ///
    /// `begin` samples the cursor once; only `dragMoved` tracks it — and a
    /// reorder drag reaches the view's own mouse closure rather than the
    /// `.draggable` modifier that normally calls it.
    @MainActor
    private func floatCarriedRows(
        session: DragAndDropSession?,
        handler: any RowReorderHosting,
        wasActive: Bool,
        grabX: Int,
        previewLine: @MainActor (Int) -> [String]?
    ) {
        guard let session, !handler.reorderFloatingRows.isEmpty else { return }
        let carried = handler.reorderFloatingRows.compactMap(previewLine)
        guard !wasActive, !carried.isEmpty else {
            session.dragMoved()
            return
        }
        // The rows' own lines, floated at the cursor. No hit regions to strip:
        // they are plain rendered lines. One line per row here, so the grab
        // point moves down the block by however many of its rows sit above the
        // one the pointer took hold of.
        //
        // Each row hands back its whole travel, grid layout first; the block's
        // frame N is every row's frame N, so a block of rows condenses as one
        // picture rather than as a column of independently-timed ones.
        let steady = FrameBuffer(lines: carried.map { $0.last ?? "" })
        let morph = (0..<Self.previewMorphSteps).map { step in
            FrameBuffer(lines: carried.map { $0[min(step, $0.count - 1)] })
        }
        session.begin(
            payload: RowReorderPayload(), preview: steady, morph: morph,
            grabX: grabX, grabY: handler.reorderHeldRowsAboveGrab.count)
    }

    /// The visible rows' bands, in order, with the TOP clip taken off — the
    /// first row's lines are net of the line-granularity top clip, because the
    /// mouse row-mapping walks these from the first visible line and a
    /// full-height first row would put every row below it off its hit band.
    ///
    /// A row in a sectioned table is up to three bands: the section headers
    /// drawn above it, as chrome — a click there selects nothing, and nothing
    /// lands there — then its cells, as the row, then the headers below the
    /// last row, as chrome. The clip eats them from the top.
    ///
    /// NOT net of the bottom clip. The last row keeps its whole height where
    /// `composeMultiLineRows` cut its tail at the line budget; that cut moves no
    /// row below it, so the bands are capped instead, by the row block's drawn
    /// end passed to `multiLineRowBands` as `lineCount`. Read as "as rendered"
    /// all the way down, which it is not there, the last band ran on over the
    /// "▼ N more rows below" line.
    private func onScreenRowParts(
        _ range: Range<Int>, layout: (Int) -> MultiLineRowLayout, topClip: Int
    ) -> [(entry: ItemListHandler<Value.ID>.DrawnBand.Content, height: Int)] {
        var clip = topClip
        /// What is left of `height` lines once the clip has taken its share.
        func taking(_ height: Int) -> Int {
            let taken = min(height, clip)
            clip -= taken
            return height - taken
        }
        var parts: [(entry: ItemListHandler<Value.ID>.DrawnBand.Content, height: Int)] = []
        parts.reserveCapacity(range.count)
        for rowIndex in range {
            let rowLayout = layout(rowIndex)
            let above = taking(rowLayout.above.count)
            var cells = taking(rowLayout.cellHeight)
            let below = taking(rowLayout.below.count)
            // A row the clip took entirely still answers on the line it is
            // drawn from — the `max(1, …)` a row of one band has always had.
            if above + cells + below == 0 { cells = 1 }
            if above > 0 { parts.append((.chrome(rowIndex: rowIndex), above)) }
            if cells > 0 { parts.append((.row(rowIndex), cells)) }
            if below > 0 { parts.append((.chrome(rowIndex: rowIndex), below)) }
        }
        return parts
    }

    /// The window the multi-line path just DREW, handed to the persistent
    /// handler — the multi-line twin of `reserveIndicatorLines`' last two
    /// statements, gated the same way and for the same reason.
    ///
    /// A MEASURE pass must not publish either of these, and this is the ONE
    /// path that could, because it is the one that renders itself to measure:
    /// `analyticMultiLineSize` declines for an overflowing table with no bar,
    /// so `sizeThatFits` falls back to `renderToBuffer`. (The single-line paths
    /// are never reached under `isMeasuring` at all, which is why their own
    /// writes read as unguarded neighbours of a guard.)
    ///
    /// A measure pass is offered whatever height the PARENT proposed, not the
    /// height the frame is drawn into: an eager `VStack` measures every child
    /// at the stack's whole height and then renders each into its distributed
    /// share, so a table sharing a stack with any sibling is measured a line
    /// taller than it is drawn, every frame. Ungated, that measure published a
    /// window belonging to a proposal — a `viewportHeight` counting rows
    /// nothing drew, and a `drawnOffset` the indicators then counted from.
    private func publishMultiLineWindow(
        handler: ItemListHandler<Value.ID>, range: Range<Int>, context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        // The window may have absorbed a top clip (or a whole first row) that an
        // indicator would otherwise have announced, so the indicators must count
        // from ITS position. See ``ItemListHandler/drawnOffset``.
        handler.drawnOffset = range.lowerBound
        // The rows actually on screen — what a page moves by, and what the
        // `List` and the single-line path publish. See the note above
        // `syncIndicatorChrome`'s call site for what used to stand here.
        handler.viewportHeight = max(1, range.count)
    }

    /// The multi-line path's bands: rows of different heights, no slot (that
    /// path forces ``RowReorderFeedback/live``, which moves the data instead of
    /// opening a gap).
    ///
    /// Nothing produced these at all until this function existed, which did not
    /// merely disable drag-reorder there — it made the gesture swallow the click
    /// while doing nothing, since `dropTarget` had no bands to hit-test against.
    ///
    /// Builds them; it does NOT publish them, unlike its single-line twin
    /// `publishRowBands`. This is the path that renders itself to measure, and
    /// handing a measure pass's bands to the handler both replaces the drawn
    /// geometry and fires the auto-scroll retarget — so the caller publishes,
    /// under `!context.isMeasuring`.
    ///
    /// `indicatorLines` must be the DRAWING condition `composeMultiLineRows`
    /// uses (`window.showsAbove && drawsText`), not the handler's
    /// `hasContentAbove`: `showAbove` is also true for a line-granularity top
    /// clip inside row 0, where `hasContentAbove` is false.
    private func multiLineRowBands(
        handler: ItemListHandler<Value.ID>,
        parts: [(entry: ItemListHandler<Value.ID>.DrawnBand.Content, height: Int)],
        indicatorLines: Int,
        lineCount: Int
    ) -> [ItemListHandler<Value.ID>.DrawnBand] {
        typealias Handler = ItemListHandler<Value.ID>
        return Handler.drawnBands(
            parts,
            // The terms this builder never had. It emitted from `yStart = 0`
            // with neither the indicator line the frame had just drawn nor the
            // overscroll excursion, so a scrolled or overscrolling multi-line
            // table hit-tested a drag against geometry its rows were not drawn
            // at.
            slide: -handler.overscrollState.excursion,
            rowsTop: indicatorLines,
            lineCount: lineCount)
    }

    // MARK: - Mouse handler wiring

    /// Registers the table's container-wide mouse handler and
    /// emits its hit-test region. Same shape as _ListCore — scroll-
    /// wheel scrolls, click on a data row selects + focuses,
    /// click anywhere else focuses without changing selection.
    ///
    /// Buffer layout from the container wrap, bordered (`.inset` has no
    /// border lines, and everything below moves up one):
    /// ```
    ///   y=0           top border
    ///   y=1           column header line
    ///   y=2           top scroll indicator (only when hasContentAbove)
    ///   y=2 + offset  first data row (offset = 1 when scroll indicator present)
    ///   …             data rows, one per line
    ///   y=N           bottom scroll indicator / bottom border
    /// ```
    /// The scrollbar's own mouse handler, registered BEFORE the container's so
    /// the container's later `insert(at: 0)` pushes this one to a higher index —
    /// hit-tested ahead of the container (reverse iteration) for its single
    /// column, while the container still wins everywhere else. The bar is the
    /// rightmost interior column (availableWidth − 3: border + padding each
    /// side, minus the bar) over the content rows; it is row-exact (one cell per
    /// row) for the single-line path.
    private func attachScrollbarMouseHandler(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        mouseDispatcher: MouseEventDispatcher,
        firstRowY: Int
    ) {
        guard state.hasScrollbar else { return }
        let barHeight = max(1, context.availableHeight - chromeLines(context.environment))
        let barHandler = ScrollbarRenderer.verticalMouseHandler(
            for: state.handler, length: barHeight,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
            in: context,
            ScrollbarRenderer.focusing(
                barHandler, focusID: state.focusID,
                focusManager: context.environment.focusManager))
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: max(
                    0,
                    context.availableWidth - borderWidth(context.environment)
                        - trailingPadding(context.environment, showsBar: true) - context.environment.scrollbarWidth),
                offsetY: firstRowY,
                width: context.environment.scrollbarWidth, height: barHeight, handlerID: barHandlerID),
            at: 0
        )
        ScrollbarRenderer.driveAutoRepeat(
            state: state.handler,
            token: "table-scrollbar-repeat-\(context.identity.path)", context: context)
    }

    /// Makes the header take the pointer: a click on a sortable column's title
    /// re-sorts; and on a table bound to a ``TableColumnCustomization``,
    /// dragging a title moves its column, and a secondary click opens the
    /// column menu. Returns the frame's header gesture — `nil` for a table
    /// with no header — which the table's own handler takes the gaps between
    /// the titles with (``headerGapEvent(_:gesture:handler:)``).
    ///
    /// One region per title rather than one for the whole header line: which
    /// column was pressed is the entire content of the gesture, and a single
    /// region would have to re-derive it from an x the dispatcher already
    /// knows how to route. A title that nothing can be done to registers
    /// nothing, so clicks there fall through to the table's own handler and
    /// simply focus it — a header that cannot sort or be customized stays as
    /// inert as it looks.
    ///
    /// The header line is `y = 1` under a bordered style — the container's top
    /// border is `y = 0` and the rows start below it (see the layout sketch
    /// above) — and `y = 0` under `.inset`, which has no border.
    @MainActor
    private func attachHeaderHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        mouseDispatcher: MouseEventDispatcher,
        focusManager: FocusManager?
    ) -> _TableHeaderGesture? {
        let customizes = columnCustomization != nil
        // Every table with a header: a column's edge resizes it whether or not
        // anything records the width (decisions B-D4T-7).
        guard !state.columnWidths.isEmpty, headerLines(context.environment) > 0 else { return nil }
        let headerY = borderWidth(context.environment)
        let originX = borderWidth(context.environment) + Self.containerPadding.leading
        let ranges = headerColumnRanges(
            columnWidths: state.columnWidths, originX: originX,
            gutter: selectionGutter(context.environment))
        // Where the columns are on THIS frame, for a header drag that started
        // on an earlier one: a live reorder moves them under the pointer.
        if !context.isMeasuring {
            publishHeaderColumns(ranges, to: state.handler)
            state.handler.headerColumnsWidest = max(1, state.rowContentWidth)
        }
        let gesture = _TableHeaderGesture(
            focusManager: focusManager, focusID: state.focusID, line: headerY,
            titlesX: originX + selectionGutter(context.environment), columnWidths: state.columnWidths,
            widest: max(1, state.rowContentWidth),
            openMenu: customizes ? columnMenuOpener(context: context, dispatcher: mouseDispatcher) : nil)
        fileGapPointerShapes(
            ranges, y: headerY, widest: max(1, state.rowContentWidth), into: &buffer, context: context,
            mouseDispatcher: mouseDispatcher)
        // A title takes the pointer only to sort or to be customized, so a
        // table that does neither walks its titles not at all.
        guard sortModel != nil || customizes else { return gesture }
        for (index, xRange) in ranges where index < columns.count {
            let sortable = sortModel != nil && columns[index].sortComparator != nil
            guard sortable || customizes else { continue }
            let column = columns[index]
            let handlerID = mouseDispatcher.register(in: context) { event in
                headerTitleEvent(
                    event, column: column, at: xRange.lowerBound, y: headerY, sortable: sortable,
                    handler: state.handler, gesture: gesture)
            }
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: xRange.lowerBound, offsetY: headerY,
                    width: xRange.count, height: 1, handlerID: handlerID),
                at: 0
            )
        }
        return gesture
    }

    /// A column's resize arrow over the gap after it, where TUIkit's controls
    /// set their own shapes (decisions O12, B-O12-6): the gaps a drag resizes
    /// — a gap there is, after a column that is not the last and may be
    /// resized. They take no events of their own (the table's handler takes a
    /// press on one, decisions LISTSPERF, B-LISTSPERF-1), so each is a shape
    /// alone, filed as `.pointerStyle(_:)` files one; nothing at all where the
    /// host's own pointer is not trusted to come back.
    private func fileGapPointerShapes(
        _ ranges: [(Int, Range<Int>)], y: Int, widest: Int, into buffer: inout FrameBuffer, context: RenderContext,
        mouseDispatcher: MouseEventDispatcher
    ) {
        guard context.environment.terminalFeatures.controlPointerShapes, !context.isMeasuring, columnSpacing > 0
        else { return }
        // The arrow follows the pointer as it moves, which only motion
        // reporting tells (as `.pointerStyle(_:)` asks for it).
        mouseDispatcher.requestFeature(.motion, in: context)
        for (position, (index, xRange)) in ranges.enumerated()
        where index < columns.count && position < ranges.count - 1 && columns[index].resizeBounds(upTo: widest) != nil {
            let gap = context.withChildIdentity(erasedType: PointerShape.self, index: index)
            let styleID = mouseDispatcher.registerPointerStyle(.columnResize, over: [], in: gap)
            buffer.hitTestRegions.insert(
                HitTestRegion(offsetX: xRange.upperBound, offsetY: y, width: columnSpacing, height: 1, handlerID: styleID),
                at: 0)
        }
    }

    /// Hands `handler` where this frame's header drew each column, out of
    /// `ranges` (``ItemListHandler/headerColumns``) — unless it holds that
    /// already, as it does on every frame the columns hold still: compared
    /// where it would have been built again, on every frame of every table
    /// with a header.
    private func publishHeaderColumns(_ ranges: [(Int, Range<Int>)], to handler: ItemListHandler<Value.ID>) {
        let drawn = handler.headerColumns
        var position = 0
        var unchanged = true
        for (index, x) in ranges where index < columns.count {
            guard position < drawn.count, drawn[position].x == x,
                drawn[position].declaration == columns[index].declarationIndex,
                drawn[position].id == columns[index].customizationID
            else {
                unchanged = false
                break
            }
            position += 1
        }
        guard !unchanged || position != drawn.count else { return }
        var placed: [(id: String?, declaration: Int, x: Range<Int>)] = []
        placed.reserveCapacity(ranges.count)
        for (index, x) in ranges where index < columns.count {
            placed.append((columns[index].customizationID, columns[index].declarationIndex, x))
        }
        handler.headerColumns = placed
    }

    /// A press on a column's title: a click sorts by it, a drag moves it, a
    /// secondary click opens the column menu on it. See
    /// ``attachHeaderHandlers(to:context:state:mouseDispatcher:focusManager:)``.
    @MainActor
    private func headerTitleEvent(
        _ event: MouseEvent, column: _TableColumnSpec<Value>, at originX: Int, y: Int, sortable: Bool,
        handler: ItemListHandler<Value.ID>, gesture: _TableHeaderGesture
    ) -> Bool {
        let x = originX + event.x
        // A secondary click is the column menu's — on a table that has one.
        // Without one, Ctrl-click is a click and sorts, as it did before
        // there was a menu; a right-click goes on to whatever is around.
        if RowContextMenuHost.isSecondary(event), let openMenu = gesture.openMenu {
            // The rest of the gesture is the menu's, as `.contextMenu`'s is.
            if event.phase == .pressed { openMenu(column.customizationID, x, y + 1) }
            return true
        }
        guard event.button == .left else { return false }
        switch event.phase {
        case .pressed:
            gesture.moved = false
            return true
        case .dragged:
            if let target = reorderTarget(for: column, atX: x, handler: handler),
                let id = column.customizationID, let binding = columnCustomization
            {
                binding.wrappedValue.move(
                    id, toPlaceOf: target, declared: declaredColumns.compactMap(\.customizationID))
                gesture.moved = true
            }
            return true
        case .released:
            // A press that moved a column was a drag, not a click: it sorts
            // nothing. Any other release sorts, wherever it lands — the press
            // captured the gesture, and like a `Button`'s, this click does not
            // cancel for sliding off before letting go.
            if !gesture.moved, sortable { toggleSort(column: column) }
            gesture.moved = false
            gesture.focus()
            return true
        default:
            return false
        }
    }

    /// Inside an enabled `textSelection(_:)`, a press on a row's text is the
    /// text's (`PressRole.rows`), as in `_ListCore`. Filed only where one is in
    /// force: around the table, or inside its cells — `Text(name).textSelection(.enabled)`
    /// in a column — which `scopesBefore`, the dispatcher's count of enabled
    /// scopes before the table drew them, tells. A table in an app with no
    /// enabled scope pays one read.
    ///
    /// A cell's scope makes the whole row's text selectable, kept to the row,
    /// as an enabled scope around the table does (B-D4X-7) — but for a press
    /// on the scoped cell itself, which is under the scope's own region (the
    /// table carries a view cell's regions up, ``_TableRowPayload``) and is
    /// kept to the cell. The rest of the row is drawn as text, and the table
    /// knows no rectangle of it to keep a selection to.
    @MainActor
    private func fileSelectableRows(
        for id: HitTestRegion.HandlerID, state: PopulatedRenderState, dispatcher: MouseEventDispatcher,
        interiorTopY: Int, contentColumns: Range<Int>, scopesBefore: Int, context: RenderContext
    ) {
        let cellsSelectText = dispatcher.enabledSelectionScopeCount > scopesBefore
        guard context.environment.textSelectionAllowed == true || cellsSelectText else { return }
        dispatcher.filePressRole(
            .rows(
                rowArea: { [handler = state.handler] localY in
                    handler.contentRowLines(atContentY: localY - interiorTopY).map {
                        (contentColumns, ($0.lowerBound + interiorTopY)..<($0.upperBound + interiorTopY))
                    }
                },
                cellsSelectText: cellsSelectText),
            for: id, in: context)
    }

    /// The column a header dragged to `x` takes the place of, or `nil` while
    /// it stays where it is — over itself, over a column that may not move,
    /// or short of the point past which the swap would put the pointer back
    /// over the column it just passed, which would swap them back on the next
    /// report.
    private func reorderTarget(
        for column: _TableColumnSpec<Value>, atX x: Int, handler: ItemListHandler<Value.ID>
    ) -> String? {
        guard columnCustomization != nil, column.allows(.reorder), let id = column.customizationID
        else { return nil }
        let shown = liveHeaderColumns(handler)
        guard let own = shown.first(where: { $0.id == id })?.x,
            !own.contains(x),
            let over = shown.first(where: { $0.x.contains(x) }),
            let target = over.id, target != id,
            declaredColumns.first(where: { $0.customizationID == target })?.allows(.reorder) == true
        else { return nil }
        // After the swap the dragged column starts where the target started
        // (moving left) or ends where it ended (moving right).
        let movingRight = over.x.lowerBound > own.lowerBound
        let swapped = movingRight ? (over.x.upperBound - own.count)..<over.x.upperBound : over.x.lowerBound..<(over.x.lowerBound + own.count)
        return swapped.contains(x) ? target : nil
    }

    /// Where the shown columns' titles are now: laid out from where the last
    /// frame drew the first, in the order and at the widths the customization
    /// holds at this moment.
    ///
    /// Input is read between frames, a batch at a time (`App` drains up to 128
    /// events a frame), so a move or a resize earlier in the batch has changed
    /// the customization and not the frame's geometry
    /// (``ItemListHandler/headerColumns``). Read from the frame, a second drag
    /// report in the batch found the dragged column back where it started and
    /// swapped it back — whether a move survived came down to how many reports
    /// a frame happened to carry.
    ///
    /// A width the user set is the width drawn — a resized column is laid out
    /// at it, fixed — and any other is the last frame's. A column shown since
    /// that frame has no width to go by and takes one cell until the next.
    private func liveHeaderColumns(_ handler: ItemListHandler<Value.ID>) -> [(id: String?, x: Range<Int>)] {
        let drawn = handler.headerColumns
        guard let binding = columnCustomization, let first = drawn.first else {
            return drawn.map { ($0.id, $0.x) }
        }
        let widths = Dictionary(drawn.map { ($0.declaration, $0.x.count) }, uniquingKeysWith: { first, _ in first })
        var laidOut: [(id: String?, x: Range<Int>)] = []
        var x = first.x.lowerBound
        for column in binding.wrappedValue.shownColumns(declaredColumns) {
            let width = column.resizedWidth ?? widths[column.declarationIndex] ?? 1
            laidOut.append((column.customizationID, x..<(x + width)))
            x += width + columnSpacing
        }
        return laidOut
    }

    /// Where `column`'s width goes when a user resizes it within `bounds`: the
    /// customization, for a column with an identifier in a table bound to
    /// one; the table's own state otherwise
    /// (``ItemListHandler/transientColumnWidths``, decisions B-D4T-7).
    private static func columnResizer(
        for column: _TableColumnSpec<Value>, bounds: ClosedRange<Int>,
        customization: Binding<TableColumnCustomization<Value>>?, handler: ItemListHandler<Value.ID>
    ) -> _TableColumnResizer {
        if let customization, let id = column.customizationID {
            return _TableColumnResizer(
                bounds: bounds, width: { customization.wrappedValue[width: id] },
                set: { customization.wrappedValue[width: id] = $0 })
        }
        let key = column.columnKey
        return _TableColumnResizer(
            bounds: bounds, width: { [weak handler] in handler?.transientColumnWidths[key] },
            set: { [weak handler] in handler?.transientColumnWidths[key] = $0 })
    }

    /// A press on the gap after a column's title — its right edge — and the
    /// drag it starts, which resizes the column, within its bounds, the width
    /// going where ``columnResizer(for:bounds:customization:handler:)`` says:
    /// on every table with a header, where there is a gap, and the column may
    /// be resized (decisions B-D4T-7). `true` for an event of that gesture;
    /// `nil` for any other, which goes on to the rest of the table's handler.
    ///
    /// Run by the table's own handler (``containerMouseHandler(state:context:focusManager:dispatcher:contentColumns:contentLines:rowContentLeft:previewLine:)``),
    /// whose region covers the header line and hears `event` in the table's
    /// own cells — nothing is between it and a gap — with the header as the
    /// frame drew it (`gesture`). A region and a handler of each gap's own,
    /// as there were, were a registration and a region per column of every
    /// table with a header on every frame, which on a table a memo serves
    /// were replayed and moved on every frame too (lane LISTSPERF). The gaps
    /// are found at the press instead.
    @MainActor
    private func headerGapEvent(
        _ event: MouseEvent, gesture: _TableHeaderGesture, handler: ItemListHandler<Value.ID>
    ) -> Bool? {
        guard event.button == .left, !event.ctrl else { return nil }
        let x = event.x
        switch event.phase {
        case .pressed:
            gesture.resizing = nil
            guard event.y == gesture.line, columnSpacing > 0 else { return nil }
            let ranges = headerColumnRanges(columnWidths: gesture.columnWidths, originX: gesture.titlesX, gutter: 0)
            guard
                let (index, title) = ranges.dropLast().first(where: { _, title in
                    (title.upperBound..<(title.upperBound + columnSpacing)).contains(x)
                }),
                index < columns.count, let bounds = columns[index].resizeBounds(upTo: gesture.widest)
            else { return nil }
            gesture.pressX = x
            gesture.startWidth = title.count
            gesture.resizing = Self.columnResizer(
                for: columns[index], bounds: bounds, customization: columnCustomization, handler: handler)
            return true
        case .dragged:
            guard let resize = gesture.resizing else { return nil }
            let wanted = min(
                resize.bounds.upperBound, max(resize.bounds.lowerBound, gesture.startWidth + x - gesture.pressX))
            if wanted != gesture.startWidth || resize.width() != nil, resize.width() != wanted {
                resize.set(wanted)
            }
            return true
        case .released:
            guard gesture.resizing != nil else { return nil }
            gesture.resizing = nil
            gesture.focus()
            return true
        default:
            return nil
        }
    }

    // MARK: - Column customization

    /// The column menu's state, at this table's identity.
    private func columnMenuBox(_ context: RenderContext) -> StateBox<RowMenuState>? {
        RowContextMenuHost.stateBox(context, propertyIndex: StateIndex.columnMenu)
    }

    /// Opens the column menu at a header press, on the column pressed — `nil`
    /// for a press on no column — anchored at the press.
    private func columnMenuOpener(
        context: RenderContext, dispatcher: MouseEventDispatcher
    ) -> ((String?, Int, Int) -> Void)? {
        guard let box = columnMenuBox(context) else { return nil }
        let onOpen = context.environment.menuOpenAction
        return { id, x, y in
            RowContextMenuHost.openByPointer(
                box, target: id.map { .row(AnyHashable($0)) } ?? .selection([]), x: x, y: y,
                dispatcher: dispatcher, onOpen: onOpen)
        }
    }

    /// The column the keyboard has picked (``ItemListHandler/columnFocus``),
    /// by its place among the shown columns, or `nil` when none is.
    private func pickedColumn(_ handler: ItemListHandler<Value.ID>) -> Int? {
        handler.columnFocus.flatMap { key in columns.firstIndex { $0.columnKey == key } }
    }

    /// What the column keys reach (``TableColumnEditing``) — `nil` for a table
    /// with no header; one that lists no column for a table with no column a
    /// user may do anything to. Without a customization binding the keys pick
    /// a column and resize it, and move nothing and open no menu, as the
    /// pointer resizes there and does nothing else (decisions B-D4T-7).
    ///
    /// Made on every pass of every table with a header, and asked only when a
    /// column key arrives, so it works nothing out ahead: its closures hold
    /// this pass's columns, and find the column a key names when it is
    /// pressed. Worked out as it was made — the keys listed, the columns
    /// filed by key — it was 3.1% of a frame of the `table` scenario, which
    /// has no binding and no key pressed (lane LISTSPERF).
    private func columnEditing(
        _ handler: ItemListHandler<Value.ID>, context: RenderContext
    ) -> TableColumnEditing? {
        guard headerLines(context.environment) > 0 else { return nil }
        guard let binding = columnCustomization, columns.contains(where: { $0.customizationID != nil }) else {
            return resizingColumnEditing(handler)
        }
        // Each key asks the customization as it stands, not this frame's
        // columns: a key earlier in the same batch may have moved, resized or
        // hidden one (see ``liveHeaderColumns(_:)``). Two `>` in one batch
        // cancelled out, and `++` grew a column by one.
        let declaredColumns = declaredColumns
        let box = columnMenuBox(context)
        let onOpen = context.environment.menuOpenAction
        return TableColumnEditing(
            // What the keys pick: the identified columns, and those without
            // an identifier that may be resized, which only resizing reaches
            // — kept by the table, as the pointer keeps them (decisions
            // B-D4T-7).
            currentColumns: {
                binding.wrappedValue.shownColumns(declaredColumns)
                    .filter { $0.customizationID != nil || $0.isResizable }.map(\.columnKey)
            },
            move: { id, delta in
                let ids = binding.wrappedValue.shownColumns(declaredColumns).compactMap(\.customizationID)
                guard let position = ids.firstIndex(of: id), ids.indices.contains(position + delta),
                    declaredColumns.first(where: { $0.customizationID == id })?.allows(.reorder) == true,
                    declaredColumns.first(where: { $0.customizationID == ids[position + delta] })?
                        .allows(.reorder) == true
                else { return }
                binding.wrappedValue.move(
                    id, toPlaceOf: ids[position + delta], declared: declaredColumns.compactMap(\.customizationID))
            },
            resize: { [weak handler] id, delta in
                guard let handler else { return }
                if let kept = declaredColumns.first(where: {
                    $0.customizationID == nil && $0.isResizable && $0.columnKey == id
                }) {
                    Self.resizeKeptWidth(of: kept, by: delta, in: handler)
                    return
                }
                // A width the user set is the width drawn; any other, the last
                // frame's.
                guard let current = binding.wrappedValue[width: id]
                        ?? handler.headerColumns.first(where: { $0.id == id })?.x.count,
                    let bounds = declaredColumns.first(where: { $0.customizationID == id })?
                        .resizeBounds(upTo: max(1, handler.headerColumnsWidest))
                else { return }
                binding.wrappedValue[width: id] = min(bounds.upperBound, max(bounds.lowerBound, current + delta))
            },
            openMenu: { id in
                guard let box else { return }
                RowContextMenuHost.openByKeyboard(box, target: .row(AnyHashable(id)), onOpen: onOpen)
            },
            menuIsOpen: { box?.value.menu.isOpen ?? false })
    }

    /// The column keys of a table with no customization binding: every shown
    /// column a user may resize, by its key, resized into the table's own
    /// state; nothing moves, and no menu opens. Lists no column when none may
    /// be resized.
    private func resizingColumnEditing(_ handler: ItemListHandler<Value.ID>) -> TableColumnEditing {
        let columns = columns
        return TableColumnEditing(
            currentColumns: { columns.filter(\.isResizable).map(\.columnKey) },
            move: { _, _ in },
            resize: { [weak handler] key, delta in
                guard let handler, let column = columns.first(where: { $0.isResizable && $0.columnKey == key })
                else { return }
                Self.resizeKeptWidth(of: column, by: delta, in: handler)
            },
            openMenu: { _ in },
            menuIsOpen: { false })
    }

    /// Resizes `column`, whose width the table keeps rather than a
    /// customization (``ItemListHandler/transientColumnWidths``), by `delta`
    /// cells within its bounds: from the width a user gave it, else the one
    /// the last frame drew.
    private static func resizeKeptWidth(
        of column: _TableColumnSpec<Value>, by delta: Int, in handler: ItemListHandler<Value.ID>
    ) {
        let key = column.columnKey
        guard let current = handler.transientColumnWidths[key]
                ?? handler.headerColumns.first(where: { $0.declaration == column.declarationIndex })?.x.count,
            let bounds = column.resizeBounds(upTo: max(1, handler.headerColumnsWidest))
        else { return }
        handler.transientColumnWidths[key] = min(bounds.upperBound, max(bounds.lowerBound, current + delta))
    }

    /// Draws the open column menu over the table — anchored at the press, or
    /// under the picked column's header when the keyboard opened it — or tears
    /// down the section a closed one left.
    private func presentColumnMenu(
        over buffer: inout FrameBuffer, state: PopulatedRenderState, context: RenderContext
    ) {
        guard !context.isMeasuring, let binding = columnCustomization, let box = columnMenuBox(context)
        else { return }
        let target: String? =
            if case .row(let id) = box.value.target { id.base as? String } else { nil }
        let headerY = borderWidth(context.environment)
        let anchor = target.flatMap { id in state.handler.headerColumns.first { $0.id == id } }
            .map { (x: $0.x.lowerBound, y: headerY, height: 1) }
        RowContextMenuHost.present(
            items: AnyView(columnMenu(on: target, binding: binding)), over: &buffer, stateBox: box,
            sectionID: "tablecolumns-\(context.identity.path)", keyboardAnchor: anchor, context: context)
    }

    /// The column menu, as macOS draws a table's (measured on macOS 15.8):
    /// "Hide" for the column it was opened on, then every column in the order
    /// shown, marked when it is visible — a column with no identifier, or one
    /// whose visibility may not change, listed but disabled. The last column
    /// shown cannot be hidden: a table of no columns has nothing to right-click
    /// to bring one back.
    private func columnMenu(
        on target: String?, binding: Binding<TableColumnCustomization<Value>>
    ) -> _TableColumnMenu {
        let shown = Set(columns.map(\.declarationIndex))
        // Every declared column, in the order shown: the customization with
        // every identified column made visible lays them out.
        var everything = binding.wrappedValue
        for id in declaredColumns.compactMap(\.customizationID) { everything[visibility: id] = .visible }
        let ordered = everything.shownColumns(declaredColumns)
        let canHideOne = shown.count > 1
        let entries = ordered.map { column -> _TableColumnMenu.Entry in
            let isShown = shown.contains(column.declarationIndex)
            let toggles = column.allows(.visibility) && (!isShown || canHideOne)
            let id = column.customizationID
            return _TableColumnMenu.Entry(
                title: column.title, isShown: isShown,
                toggle: toggles
                    ? { id.map { binding.wrappedValue[visibility: $0] = isShown ? .hidden : .visible } }
                    : nil)
        }
        let hide = target.flatMap { id in declaredColumns.first { $0.customizationID == id } }.map { column in
            (
                title: LocalizationService.shared.string(for: LocalizationKey.Label.hideColumn)
                    .replacingOccurrences(of: "%@", with: column.title),
                action: column.allows(.visibility) && canHideOne && shown.contains(column.declarationIndex)
                    ? { binding.wrappedValue[visibility: column.customizationID ?? ""] = .hidden } : nil
            )
        }
        return _TableColumnMenu(hide: hide, entries: entries)
    }

    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        scopesBefore: Int
    ) {
        guard !isDisabled(in: context), !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        // The table's interior: past the top border (when the style draws one)
        // and the column header (when it is drawn) — nothing else sits between
        // it and the content.
        //
        // THIS is the origin the drag geometry works in, matching `_ListCore`'s
        // `topInset`: `DrawnBand.yStart` counts from the first CONTENT line, so
        // the "N more above" indicator's line is inside the band space rather
        // than subtracted out before it. Anything that hit-tests a BAND —
        // `ReorderHost.topInset`, the drop destination, the session-less
        // `dragContentY` — measures from here.
        let interiorTopY = borderWidth(context.environment) + headerLines(context.environment)
        // …and the first ROW line, which is one lower when an indicator is
        // drawn. Only the scrollbar wants this now: its cells are one per ROW,
        // so the bar's region has to start where the rows do. Everything that
        // hit-tests a LINE — the click map, the cursor marker, the drag —
        // works in the band space above instead.
        let firstRowY = interiorTopY + state.scrollOffsetAbove

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column, while the container
        // still wins everywhere else. The bar is the rightmost interior column
        // (availableWidth − 3: border + padding each side, minus the bar) over the
        // content rows; it is row-exact (one cell per row) for the single-line path.
        attachScrollbarMouseHandler(
            to: &buffer, context: context, state: state,
            mouseDispatcher: mouseDispatcher, firstRowY: firstRowY)

        // The header's titles, for the same reason and by the same trick as
        // the scrollbar above: registered first so the container's later
        // `insert(at: 0)` leaves these at a higher index, where the reverse
        // hit-test finds them before the table's own catch-all, which takes
        // the gaps between them.
        var state = state
        state.headerGesture = attachHeaderHandlers(
            to: &buffer, context: context, state: state, mouseDispatcher: mouseDispatcher, focusManager: focusManager)

        // The border columns are chrome: a click there (however row-aligned its
        // y) must not select — see the x-guard in the handler. Tables always
        // render inside a bordered container, so one column each side. (The
        // List sibling got this guard in a6ba424d; this is its Table mirror.)
        let border = borderWidth(context.environment)
        let contentColumns = border..<max(border, buffer.width - border)
        // The row, rendered as its own object: no selection background, no
        // padding out to the grid's interior. Built on demand — only a drag
        // that actually starts pays for it.
        let palette = context.environment.palette
        let columnWidths = state.columnWidths
        let previewLine: @MainActor (Int) -> [String]? = { index in
            guard data.indices.contains(index), !columnWidths.isEmpty else { return nil }
            return previewMorphLines(
                item: data[index], row: index, columnWidths: columnWidths,
                steps: Self.previewMorphSteps, context: context, palette: palette)
        }
        // Where a ROW LINE's first cell sits in the buffer: past the border and
        // past the container's own padding. Not the same as the first clickable
        // column — the padding column is clickable but belongs to no row — and
        // measuring the reorder grab point from the wrong one of the two put
        // the floating row a cell off the pointer. `_ListCore` passes the
        // equivalent `rowContentLeft`.
        let rowContentLeft = contentColumns.lowerBound + Self.containerPadding.leading
        // The wheel scrolls a table that does not hold the focus: reported, as
        // in `_ListCore`, or the row around it is served unscrolled.
        let mouseHandlerID = mouseDispatcher.register(
            in: context, reportingChangesTo: { [handler = state.handler] in handler.drawnPosition },
            containerMouseHandler(
                state: state,
                context: context,
                focusManager: focusManager,
                dispatcher: mouseDispatcher,
                contentColumns: contentColumns,
                // The rows' lines: below the header, above the bottom border.
                contentLines: interiorTopY..<max(interiorTopY, buffer.height - border),
                rowContentLeft: rowContentLeft,
                previewLine: previewLine
            )
        )
        fileSelectableRows(
            for: mouseHandlerID, state: state, dispatcher: mouseDispatcher, interiorTopY: interiorTopY,
            contentColumns: contentColumns, scopesBefore: scopesBefore, context: context)
        // Insert at the back so interactive children inside a
        // row still win the dispatcher's reverse-iteration
        // match. See the parallel comment in _ListCore.
        // The table's focusID rides on this region: it is how an enclosing
        // ScrollView locates the focused table to scroll it into view
        // (`snapViewportToFocusedControl` scans regions by focusID).
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: buffer.width, height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: state.focusID
            ),
            at: 0
        )

        registerDragTargets(
            handlerID: mouseHandlerID, state: state, context: context, interiorTopY: interiorTopY,
            contentColumns: contentColumns)

        registerRowHoverObservers(
            to: &buffer, state: state, context: context, mouseDispatcher: mouseDispatcher,
            interiorTopY: interiorTopY, contentColumns: contentColumns)
        if let rowTraits {
            _TableRowDragRegions.register(
                to: &buffer,
                rows: state.drawnBands.compactMap { band in
                    guard case .row(let index) = band.entry else { return nil }
                    return _TableRowDragRegions.DrawnRow(
                        index: index, y: interiorTopY + band.yStart, height: band.height)
                },
                traits: rowTraits, handler: state.handler, columns: contentColumns, context: context,
                preview: previewLine)
        }

        // A one-row region at the keyboard cursor's on-screen line, ahead of
        // the whole-table region so an enclosing ScrollView follows the
        // cursor row — not just the table's top — through a table taller than
        // the outer viewport. Mirrors the marker in _ListCore, and now takes
        // its rectangle the same way: straight off the band the row was drawn
        // as. The band already carries the indicator's offset and the
        // overscroll slide, so there is nothing left to re-derive — the sum of
        // per-row heights, and the excursion correction that used to follow it,
        // were both this arithmetic done a second time.
        let cursor = state.handler.focusedIndex
        if let band = state.drawnBands.first(where: {
            if case .row(let index) = $0.entry { return index == cursor }
            return false
        }) {
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: 0, offsetY: interiorTopY + band.yStart,
                    width: buffer.width, height: max(1, band.height),
                    handlerID: mouseHandlerID,
                    focusID: state.focusID
                ),
                at: 0
            )
        }
    }

    /// A hover observer over each drawn row an `.onHover(perform:)` reached,
    /// telling its actions when the pointer comes onto the row's lines and
    /// leaves them.
    ///
    /// Observers, not ordinary regions, so the clicks and the wheel still
    /// reach the table beneath them — see
    /// `MouseEventDispatcher.registerHoverObserver(in:_:)`.
    private func registerRowHoverObservers(
        to buffer: inout FrameBuffer, state: PopulatedRenderState, context: RenderContext,
        mouseDispatcher: MouseEventDispatcher, interiorTopY: Int, contentColumns: Range<Int>
    ) {
        guard let rowTraits, context.environment.isEnabled else { return }
        var askedForMotion = false
        for band in state.drawnBands {
            guard case .row(let index) = band.entry, rowTraits.indices.contains(index) else {
                continue
            }
            let actions = rowTraits[index].hoverActions
            guard !actions.isEmpty else { continue }
            if !askedForMotion {
                mouseDispatcher.requestFeature(.motion, in: context)
                askedForMotion = true
            }
            let handlerID = mouseDispatcher.registerHoverObserver(in: context) { event in
                switch event.phase {
                case .entered:
                    for action in actions { action(true) }
                    return true
                case .exited:
                    for action in actions { action(false) }
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: contentColumns.lowerBound, offsetY: interiorTopY + band.yStart,
                    width: contentColumns.count, height: max(1, band.height),
                    handlerID: handlerID))
        }
    }

    /// Registers the table's own rectangle — the region `mouseHandlerID`
    /// names — with the drag-and-drop session: a landing place for a reorder
    /// of its rows, a destination for a drop from elsewhere, and a zone a drag
    /// near its edges scrolls.
    private func registerDragTargets(
        handlerID mouseHandlerID: HitTestRegion.HandlerID, state: PopulatedRenderState, context: RenderContext,
        interiorTopY: Int, contentColumns: Range<Int>
    ) {
        // A landing place for a reorder of its own rows, on the container's
        // rectangle. Registered unconditionally (not under `isScrollEnabled`,
        // as the auto-scroll zone below is): a drop is not a scroll, and a
        // table that did not register is one a gesture cannot land in.
        if state.handler.onMove != nil {
            context.environment.dragAndDropSession?.registerReorderHost(
                DragAndDropSession.ReorderHost(
                    focusID: state.focusID,
                    handlerID: mouseHandlerID,
                    // The INTERIOR top, not the first row line: the session
                    // resolves a drag through `DragAndDropSession.contentY`
                    // (`event.y - localOriginY - topInset`) and hit-tests the
                    // published bands with it, so this has to name the same
                    // origin the bands do. `_ListCore` passes its content
                    // `topInset` here for exactly that reason.
                    topInset: interiorTopY,
                    contentColumns: contentColumns,
                    handler: state.handler),
                in: context)
        }

        // The external drop destination is registered unconditionally too, for
        // the same reason as the reorder host above: a drop is not a scroll,
        // and a pinned `.scrollDisabled` staging table must still take drops —
        // as the List twin already does (`_ListCore.registerRowTargets`, which
        // gates only its auto-scroll zone). This sat inside the
        // `isScrollEnabled` gate below, so a non-scrolling table silently
        // refused every external drag: no slot opened, and release flew home.
        registerRowDropDestination(
            zoneID: mouseHandlerID, state: state, context: context,
            interiorTopY: interiorTopY)

        // Register the table as a drag auto-scroll zone (sharing the container
        // region id): a drag hovering near its top/bottom edge scrolls the rows
        // to reveal an off-screen drop target. Auto-scroll is a gesture, so
        // `.scrollDisabled` withholds the zone entirely.
        if context.environment.isScrollEnabled {
            context.environment.dragAndDropSession?.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: mouseHandlerID,
                    vertical: state.handler,
                    horizontal: nil,
                    delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds,
                    // The column header is not part of the scrollable band. Left
                    // in, it ate the whole upward hot margin: the border and the
                    // header were the two hot rows, so the "▲ N more above" line
                    // — the one place a user aims to scroll up — was inert.
                    topInset: headerLines(context.environment),
                    shiftStep: context.environment.shiftStepMultiplier),
                in: context)
        }
    }

    /// The data row drawn on the table's line `y`, out of a frame's `bands`
    /// — `nil` for a line no row is on.
    ///
    /// One lookup for both layouts. It used to walk `visibleRange`
    /// (single-line) or a per-row height array (multi-line) from a
    /// `firstRowY` recomputed on every event, undoing the overscroll
    /// slide by hand on the way. Every one of those terms is already
    /// in the band, and re-deriving them is how the click map came
    /// to disagree with the drawing: its "is an indicator drawn?"
    /// test was `hasContentAbove`, while the multi-line path draws
    /// by `showAbove`, which is also true for a line-granularity
    /// clip inside row 0. Scrolled one line into the first row, the
    /// indicator was on screen and every click landed a row low.
    private static func drawnRow(
        atLine y: Int, interiorTopY: Int, bands: [ItemListHandler<Value.ID>.DrawnBand]
    ) -> Int? {
        let contentY = y - interiorTopY
        for band in bands where contentY >= band.yStart && contentY < band.yStart + band.height {
            if case .row(let rowIndex) = band.entry { return rowIndex }
            return nil
        }
        return nil
    }

    /// The closure invoked by the container-wide hit-test
    /// region. Routes wheel to the handler's scroll position
    /// (never the selection), left-release to row hit-testing
    /// + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        context: RenderContext,
        focusManager: FocusManager?,
        dispatcher: MouseEventDispatcher,
        contentColumns: Range<Int>,
        contentLines: Range<Int>,
        rowContentLeft: Int,
        previewLine: @escaping @MainActor (Int) -> [String]?
    ) -> @MainActor (MouseEvent) -> Bool {
        // The rows start on the interior's first line, below the header.
        let interiorTopY = contentLines.lowerBound
        let headerGesture = state.headerGesture
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        // The press frame's geometry, captured: a press and its release
        // describe one unchanging layout, and it is the CLICK path that needs
        // it. The reorder path deliberately reads the handler's freshly
        // published bands instead — `.live` feedback moves the rows out from
        // under this copy as the drag goes. Same split as `_ListCore`.
        let drawnBands = state.drawnBands
        // `data` itself, not `data.map(\.id)`: this closure is rebuilt every
        // render pass, and materialising every row's id each time cost O(rows)
        // per frame for a lookup that is made once per click.
        let rows = data
        // The row menu, when there is one to open — `nil` leaves a secondary
        // click to whatever is around the table. A press that opens it takes
        // the focus for the table, so the keyboard reaches the menu's rows.
        let menu = pointerMenu(
            handler: captureHandler, context: context, dispatcher: dispatcher,
            contentColumns: contentColumns, contentLines: contentLines,
            opened: { focusManager?.focus(id: captureFocusID) })
        let triangleHit = outlineTriangleHit(
            columnWidths: state.columnWidths,
            firstColumnLeft: rowContentLeft + selectionGutter(context.environment),
            context: context)
        let dragSession = context.environment.dragAndDropSession
        // Where inside the grabbed row the press landed — the cell a `.cursor`
        // drag keeps under the pointer. Held in the closure because the closure
        // IS the gesture (see RowReorderGrabPoint).
        let grab = RowReorderGrabPoint()
        /// The clicked line's data row, from the press frame's bands.
        func rowAt(y: Int) -> Int? { Self.drawnRow(atLine: y, interiorTopY: interiorTopY, bands: drawnBands) }
        return { event in
            // A gap between the header's titles first, as a region of its own
            // in front of this one would have it.
            //
            // Wheel scrolls the viewport, never the selection — see the
            // matching comment in _ListCore for the model, routed through the
            // shared ScrollableOffsetState helper so the math lives in one
            // place. A secondary click opens the row menu: on the row under
            // it, or on none for the table's empty space (the border and the
            // column header are neither); a right press with nothing to open
            // goes on to a menu around the table, and a Ctrl-click with
            // nothing to open is still a click.
            let spent = headerGesture.flatMap { headerGapEvent(event, gesture: $0, handler: captureHandler) }
                ?? RowContextMenuHost.preflight(
                    event, wheel: { captureHandler.handleWheelEvent($0) }, menu: menu, row: { rowAt(y: event.y) })
            if let spent { return spent }

            if event.button == .left {
                /// The drag's position in the handler's band space — lines from
                /// the interior's first CONTENT line, the same origin
                /// ``ItemListHandler/DrawnBand/yStart`` counts from — or `nil`
                /// once the cursor leaves the rows, in either axis. The session
                /// path asks the same two questions of the same shared rule,
                /// having localised the cursor itself.
                var dragContentY: Int? {
                    captureHandler.rowSpaceContentY(
                        x: event.x, y: event.y, contentColumns: contentColumns,
                        topInset: interiorTopY)
                }

                switch event.phase {
                case .pressed:
                    // Pick up the row for a possible reorder (only when the table
                    // is reorderable). Claim the press either way so the matching
                    // drag / release routes back here.
                    if captureHandler.onMove != nil, contentColumns.contains(event.x),
                        let index = rowAt(y: event.y)
                    {
                        captureHandler.beginReorder(grabbing: index)
                        // Which control the gesture belongs to is the session's
                        // to know from here on — see the twin in `_ListCore`.
                        captureHandler.armReorderSession(
                            dragSession, focusID: captureFocusID)
                        // Focus follows the gesture, so the keyboard reaches
                        // this list for the length of it — that is what lets the
                        // navigators scroll a list that was not focused before
                        // the drag began.
                        focusManager?.focus(id: captureFocusID)
                        // Relative to the ROW LINE, which is what the preview
                        // is — not to the first clickable column.
                        grab.x = max(0, event.x - rowContentLeft)
                        grab.y = 0  // one line per row on every reorderable path
                    }
                    return true

                case .dragged:
                    // Edge auto-scroll, armed on the first MOTION rather than
                    // at the press — see the twin in `_ListCore` for why (a
                    // motionless long-press near an edge must not scroll).
                    dragSession?.armReorderAutoScrollOnMotion(owner: captureHandler)
                    // Any motion during a grab is a reorder, not a click. What it
                    // looks like is the feedback mode's business — and `.cursor`'s
                    // reaches outside the table: its row rides the pointer above
                    // every other view, which only the drag session can draw.
                    // Tracked through the session — see the twin in `_ListCore`
                    // for why, and for what the session-less fallback is.
                    let wasActive = (dragSession?.reorderHandler ?? captureHandler).isReordering
                    if let dragSession {
                        dragSession.trackReorder()
                    } else {
                        captureHandler.dragReorder(toContentY: dragContentY)
                    }
                    floatCarriedRows(
                        session: dragSession,
                        handler: dragSession?.reorderHandler ?? captureHandler,
                        wasActive: wasActive, grabX: grab.x, previewLine: previewLine)
                    return true

                case .released:
                    // Whatever this turns out to be — a drop, or a click that
                    // never moved — the gesture is over, so let go of the edge
                    // auto-scroll. (`end()` below only runs for a real drop.)
                    dragSession?.disarmAutoScroll()
                    // A cancel already put the rows back and ended the drag; the
                    // release that follows is the tail of a cancelled gesture,
                    // not a click on whatever is under the pointer. Session
                    // first, for the adopted-handler reason the List twin
                    // documents (`DragAndDropSession.cancelReorder`).
                    if dragSession?.consumeReorderCancellation() == true { return true }
                    let releasing = dragSession?.reorderHandler ?? captureHandler
                    if releasing.reorderCancelled {
                        releasing.noteReorderCancelled(false)
                        return true
                    }

                default:
                    return false
                }

                // A reorder drop, if this gesture was one. Committed through
                // the session — see the twin in `_ListCore`.
                if dragSession?.performReorderDrop()
                    ?? captureHandler.dropReorder(atContentY: dragContentY)
                {
                    focusManager?.focus(id: captureFocusID)
                    return true
                }

                // Border columns are chrome: a click there shares a row's y but
                // nobody clicking the frame means "select that row" — focus the
                // table (below) and stop. Mirrors _ListCore's x-guard.
                guard contentColumns.contains(event.x) else {
                    focusManager?.focus(id: captureFocusID)
                    return true
                }
                if let index = rowAt(y: event.y), let triangleHit, triangleHit(index, event.x) {
                    // The triangle discloses, and moves the cursor to its row
                    // without selecting it — the selection is the text's.
                    captureHandler.focusedIndex = index
                } else if let index = rowAt(y: event.y) {
                    // A double-click fires the row's primary action ("open");
                    // a single click selects with macOS semantics (plain =
                    // sole selection, shift = range, ctrl/option = toggle) —
                    // see ItemListHandler.handleClickSelection.
                    if captureHandler.completesMultiClick(on: index, clickCount: event.clickCount),
                        let action = captureHandler.primaryAction,
                        index >= 0, index < rows.count
                    {
                        captureHandler.focusedIndex = index
                        // Spent — see the twin in `_ListCore`.
                        dispatcher.endMultiClickSequence()
                        action(rows[index].id)
                    } else {
                        captureHandler.handleClickSelection(at: index, event: event)
                    }
                }
                focusManager?.focus(id: captureFocusID)
                return true
            }
            return false
        }
    }

    /// Whether a click at column `x` of row `index` lands on that row's
    /// disclosure triangle — and when it does, opens or closes the branch.
    /// `nil` for a table that is not a tree.
    ///
    /// The triangle sits where the first column's cell put it: at the cell's
    /// leading edge, or wherever its alignment moved the cell's text.
    private func outlineTriangleHit(
        columnWidths: [Int], firstColumnLeft: Int, context: RenderContext
    ) -> (@MainActor (Int, Int) -> Bool)? {
        guard let outline, let column = columns.first, let width = columnWidths.first else {
            return nil
        }
        let rows = data
        let probe = Self.probing(context)
        return { index, x in
            guard rows.indices.contains(index),
                let triangle = outline.triangleColumns(for: rows[index].id)
            else { return false }
            let firstLine =
                cellValue(column, for: rows[index], width: width, context: probe)
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let start =
                firstColumnLeft
                + column.alignment.childOffset(
                    childWidth: min(width, firstLine.strippedLength), in: width)
            guard (start + triangle.lowerBound..<start + triangle.upperBound).contains(x) else {
                return false
            }
            return outline.setExpanded(
                AnyHashable(rows[index].id), to: nil, includingDescendants: false)
        }
    }

    // MARK: - Column Width Calculation

    private func calculateColumnWidths(
        availableWidth: Int, spacing: Int, gutter: Int, context: RenderContext
    ) -> [Int] {
        guard !columns.isEmpty else { return [] }

        let totalSpacing = spacing * (columns.count - 1)
        let contentWidth = max(0, availableWidth - totalSpacing - gutter)

        // Single-line cells are CLIPPED to their column, so once a `.fit`
        // column's widest-so-far already spans the whole interior, no later
        // row can change anything visible — stop scanning. Multi-line cells
        // instead WRAP at the column width, so there the true maximum
        // matters and the scan must run to the end.
        let fitScanCap =
            columns.contains(where: { $0.lineLimit > 1 }) ? nil : Optional(contentWidth)

        var widths = [Int](repeating: 0, count: columns.count)
        var usedWidth = 0
        var flexibleIndices: [Int] = []
        var flexibleBounds: [(min: Int?, ideal: Int?, max: Int?)] = []

        for (index, column) in columns.enumerated() {
            switch column.effectiveWidth {
            case .fixed(let fixedWidth):
                widths[index] = fixedWidth
                usedWidth += fixedWidth
            case .ratio(let ratio):
                // `.ratio` takes an unvalidated Double from public API, and a
                // ratio is usually computed (`part / whole`) — so NaN and ±infinity
                // arrive in practice, and `Int(Double)` traps on both, as it does
                // on any value past Int's range. Treat a non-finite ratio as zero
                // and clamp the rest to the space actually available: a bad ratio
                // should render a degenerate column, not kill the app.
                // Clamped in Double space, BEFORE the conversion: `Int(_: Double)`
                // traps on NaN, on ±infinity, and on any finite value past Int's
                // range (`1e30` is finite and still traps), so no post-conversion
                // clamp can save it. A column can never be wider than the content
                // area anyway, so bounding to that is both safe and correct.
                let scaled = Double(contentWidth) * ratio
                let ratioWidth = scaled.isFinite ? Int(min(max(0, scaled), Double(contentWidth))) : 0
                widths[index] = ratioWidth
                usedWidth += ratioWidth
            case .fit:
                let fitted = fitWidth(of: column, cappedAt: fitScanCap, context: context)
                widths[index] = fitted
                usedWidth += fitted
            case .flexible(let minimum, let ideal, let maximum):
                flexibleIndices.append(index)
                flexibleBounds.append((minimum, ideal, maximum))
            }
        }

        if !flexibleIndices.isEmpty {
            let shared = TableFlexibleWidths.widths(
                flexibleBounds, sharing: max(0, contentWidth - usedWidth))
            for (offset, index) in flexibleIndices.enumerated() {
                widths[index] = shared[offset]
            }
        }

        return widths.map { max(1, $0) }
    }

    /// One column's value for one row, counted.
    ///
    /// Every `column.value(for:)` in this file goes through here so that the
    /// number of times a `Table` calls into an APP's own closures is reportable
    /// — it is the app's code, not the framework's, and it is what a per-row
    /// memo would exist to stop repeating. `RenderCache.rowWork` is where it
    /// lands, beside the cache statistics a harness already reads.
    ///
    /// A view cell is rendered here, at `width` and the column's line limit,
    /// and its lines come back joined by newlines: the rest of the table reads
    /// every cell as a string, and a column that ``_TableColumnSpec/laysOutItsOwnLines``
    /// is split on those newlines instead of being wrapped. Only a cell that
    /// is DRAWN may be rendered under the caller's own context — a measure, a
    /// fit scan or an off-screen row's height must pass a measuring one, or a
    /// control in the cell would register for focus from a row nobody sees.
    private func cellValue(
        _ column: _TableColumnSpec<Value>, for item: Value, width: Int, context: RenderContext
    ) -> String {
        context.renderCache?.rowWork.cellValues += 1
        if let text = cascadedTextCell(column, for: item, context: context) {
            return renderedCell(text, column, for: item, width: width, context: context)
        }
        switch column.cell {
        case .string(let extract):
            return extract(item)
        case .text(let make):
            let text = make(item, context)
            // The one-line case without the array: this is the single-line
            // table's every cell.
            if column.lineLimit == 1, text.drawsAsPlainString { return text.content }
            if let lines = Self.plainLines(of: text, in: column, width: width) {
                return lines.joined(separator: "\n")
            }
            return renderedCell(text, column, for: item, width: width, context: context)
        case .view(let render):
            return Self.cellLines(
                render(
                    item,
                    cellContext(column, for: item, width: width, context: context)),
                limit: column.lineLimit)
        }
    }

    /// One drawn row's single-line composition, and what its cells' controls
    /// registered (``_TableRowPayload``).
    private typealias DrawnSingleLineRow = (
        line: String, pulseFrames: [String]?, pulseTiming: IndicatorCycleTiming?,
        claims: [OpacityRegion], payload: _TableRowPayload
    )

    /// A plain `Text` cell's lines, or `nil` for a text that must be rendered.
    ///
    /// A plain `Text` says exactly what a `String` key path's value says, and
    /// is drawn the same way — which keeps the commonest content closure on
    /// the string path, and keeps its bytes identical to the key-path column it
    /// most often replaces. On one line that is its string (a line break makes
    /// it two, so it is rendered); on several, its string laid out as `Text`
    /// lays itself out — `TextWrapping.fit` at the cell's width and the
    /// column's limit and truncation. Rendering it as a view instead drew the
    /// same lines at about a third of the frame (table-multiline,
    /// table-churn-wrapped: −29% and −31% without it).
    private static func plainLines(
        of text: Text, in column: _TableColumnSpec<Value>, width: Int
    ) -> [String]? {
        if column.lineLimit == 1 {
            return text.drawsAsPlainString ? [text.content] : nil
        }
        guard text.isUnstyled else { return nil }
        return TextWrapping.fit(
            text.content, width: max(1, width), maxLines: column.lineLimit, mode: column.truncationMode)
    }

    /// A `String` or plain `Text` cell as the `Text` it would be, when the
    /// style cascade has something to say to a cell's text — `.bold()` or
    /// `.textCase(_:)` on the table, `.style(.control(.table))`: drawn as that
    /// `Text` it takes the cascade as any `Text` does, where the string path,
    /// which draws the characters in the table's own ink, took none of it.
    /// `nil` for a view cell, which renders its own `Text`s, and wherever the
    /// cascade is silent to a cell's text — every table without such a
    /// modifier above it, and every one whose cascade speaks only to other
    /// scopes (a theme's `.control(.button)` styles), which pays a stored
    /// flag's read per cell for the question, ahead of anything else: the
    /// pass answers it once (``cascadesCellText``). The cell's kind is asked
    /// after it, as it is a generic enum's case, which this unspecialised
    /// type asks of the runtime. A copy of the table no pass prepared asks
    /// the cascade itself.
    ///
    /// Every reader of a cell's characters asks this — the fit scan, a row's
    /// height and its drawing alike — so a cascaded `textCase` that turns "ß"
    /// into "SS" is measured as it is drawn.
    ///
    /// `@inline(__always)`: asked of every cell, and on almost every table
    /// answered by the flag alone, which was cheaper than the call made to
    /// read it (0.2% of a frame of the `table` scenario, lane LISTSPERF).
    @inline(__always)
    private func cascadedTextCell(
        _ column: _TableColumnSpec<Value>, for item: Value, context: RenderContext
    ) -> Text? {
        guard cascadesCellText ?? (Self.cellTextAttributes(context.environment) != StyleAttributes()) else {
            return nil
        }
        switch column.cell {
        case .string(let extract): return Text(verbatim: extract(item))
        case .text(let make): return make(item, context)
        case .view: return nil
        }
    }

    /// Claims the table's text in `context` for `.control(.table)`: a
    /// `.style(.control(.table)) { … }` entry names the text of the table's
    /// cells, as `.control(.toggle)` names a toggle's label — unless the table
    /// sits inside a control that has claimed its text already (a `Picker`),
    /// whose kind it keeps. One environment write per table per pass, made
    /// in place: the entry points' context usually holds its environment
    /// alone, ``RowSelectionIndicator/resolvingForTable(_:)`` having just
    /// written to it, where a copy of the context to write to copied the
    /// environment's storage every time.
    private static func claimCellText(in context: inout RenderContext) {
        guard context.environment.controlKind == nil else { return }
        context.environment.controlKind = .table
    }

    /// What the style cascade gives a string cell's text: what a `Text` in the
    /// cell resolves, but for the scopes a string has no part in — a font, a
    /// semantic colour, a chrome role. Empty, without resolving anything,
    /// where the cascade is empty.
    static func cellTextAttributes(_ environment: EnvironmentValues) -> StyleAttributes {
        let cascade = environment.styleCascade
        guard !cascade.isEmpty else { return StyleAttributes() }
        var scopes: Set<StyleScope> = [.all, .text]
        if let kind = environment.controlKind {
            scopes.insert(.control(kind))
            if let variant = environment.controlVariant { scopes.insert(.controlVariant(kind, variant)) }
        }
        return cascade.resolve(for: scopes)
    }

    /// A `Text` cell rendered as the view it is, its lines joined by newlines.
    private func renderedCell(
        _ text: Text, _ column: _TableColumnSpec<Value>, for item: Value, width: Int,
        context: RenderContext
    ) -> String {
        Self.cellLines(
            TUIkitView.renderToBuffer(
                text, context: cellContext(column, for: item, width: width, context: context)),
            limit: column.lineLimit)
    }

    /// Notes which rows this walk drew (`drawn`), for a live sheet docked
    /// over the page to ask whether its presenter was left out
    /// (`StateStorage.noteWindowedRows`) — its row found among the rows'
    /// identities (``rowIdentity(of:context:)``).
    private func noteDrawnRows(_ drawn: Range<Int>, stateStorage: StateStorage, context: RenderContext) {
        guard !context.isMeasuring, stateStorage.notesWindowedRows else { return }
        let data = data
        stateStorage.noteWindowedRows(
            WindowedRows(
                root: context.identity, count: data.count,
                identity: { rowIdentity(of: data[$0], context: context) },
                isDrawn: { drawn.contains($0) }))
    }

    /// The identity `item`'s row renders at, below this table's (`context`'s):
    /// every view cell of the row renders below it (``cellContext(_:for:width:context:)``).
    private func rowIdentity(of item: Value, context: RenderContext) -> ViewIdentity {
        rowContext(of: item, context: context).identity
    }

    /// `context` one identity step in, at `item`'s row.
    private func rowContext(of item: Value, context: RenderContext) -> RenderContext {
        context.withChildIdentity(erasedType: _TableColumnSpec<Value>.self, key: identityKey(item.id))
    }

    /// The context a view cell renders under: its own identity — the row's,
    /// then the column's — so a view with `@State` in a cell keeps it per row
    /// and per column; the cell's rectangle as the space on offer; and the
    /// column's line limit and truncation as the environment's, so a `Text`
    /// cell clips and wraps as the column says.
    ///
    /// And no carried geometry origin. The cell is composed as text, and the
    /// markers it drew come up with its regions (``_TableRowPayload``), so the
    /// frame's owners find a view in it where the row draws it (decisions D5G,
    /// B-D5G-2): a reader there predicts the origin and is corrected on its
    /// first frame, then reads what was found. Carried, the table's own
    /// origin reached every cell — no row or column placed — and every
    /// container in a cell worked out placements no better than the origin.
    /// A space declared inside the cell starts an origin of its own, and is
    /// answered exactly.
    ///
    /// And a shadowed foreground style without its shadows: the rows cast them
    /// from their glyphs, a view cell's among them, all at once
    /// (`_TableContentView`), so a cell's views cast none of their own — one
    /// shadow a glyph, as a text column's has.
    private func cellContext(
        _ column: _TableColumnSpec<Value>, for item: Value, width: Int, context: RenderContext
    ) -> RenderContext {
        var cellContext =
            rowContext(of: item, context: context)
            .withChildIdentity(
                erasedType: _TableColumnSpec<Value>.self, index: column.declarationIndex)
            .withAvailableSize(width: max(1, width), height: column.lineLimit)
        cellContext.environment.lineLimit = .lines(column.lineLimit)
        cellContext.environment.truncationMode = column.truncationMode
        if cellContext.carriesGeometryOrigin { cellContext.geometryOrigin = nil }
        Self.castingNoShadows(&cellContext)
        RowContextMenuHost.yieldSecondaryClicks(in: &cellContext.environment, rowsIdentifiedBy: Value.ID.self)
        return cellContext
    }

    /// `context` with a shadowed foreground style's shadows taken off: what a
    /// view drawn among the rows renders under, the rows casting the shadows
    /// from every glyph they hold at once (`_TableContentView`).
    private static func castingNoShadows(_ context: inout RenderContext) {
        if let paint = context.environment.foregroundStyle, paint.hasShadows {
            context.environment.foregroundStyle = paint.unshadowed
        }
    }

    /// Raises the background prominence of the focused, selected row — the row
    /// under the cursor while the table has the focus, when it is selected — and
    /// returns its index, or `nil` when no row is raised.
    ///
    /// The same rule as `_ListCore.raiseBackgroundProminence`, for the same
    /// reason: the raise reaches the row's view cells through their
    /// environment, which no memo below the row compares, so the frame the
    /// raised row changes clears both rows' cached renders — the row's
    /// identity, which every cell of it renders below (``cellContext(_:for:width:context:)``).
    @discardableResult
    private func raiseBackgroundProminence(
        handler: ItemListHandler<Value.ID>, tableHasFocus: Bool, context: RenderContext
    ) -> Int? {
        let index = handler.focusedIndex
        let raised =
            tableHasFocus && index < data.count && handler.isCursorRow(index)
                && handler.isSelected(at: index)
            ? index : nil
        let identity = raised.map { rowIdentity(of: data[$0], context: context) }
        guard !context.isMeasuring, identity != handler.raisedProminenceRow else { return raised }
        if let cache = context.renderCache {
            for row in [handler.raisedProminenceRow, identity].compactMap(\.self) {
                cache.clearAffected(by: row)
            }
        }
        handler.raisedProminenceRow = identity
        return raised
    }

    /// What both handler resolutions do first each frame: the row count, the
    /// drawing inputs, and — before anything is drawn from the cursor — the
    /// row a prefix typed since the last frame names.
    private func refresh(_ handler: ItemListHandler<Value.ID>, context: RenderContext) {
        handler.itemCount = data.count
        handler.drawing = HandlerDrawing(context)
        handler.resolvePendingTypeSelect(measuring: context.isMeasuring) {
            typeSelectText(of: data[$0], context: context)
        }
    }

    /// The text a typed prefix matches a row by: its first column's — the
    /// value of a key-path column, the text a view cell states with
    /// `typeSelectEquivalent(_:)`, or else the view cell's first line drawn as
    /// a measure, which registers nothing (the row may be far out of sight).
    private func typeSelectText(of item: Value, context: RenderContext) -> String? {
        guard let column = columns.first else { return nil }
        var probe = Self.probing(context)
        probe.environment.isTypeSelectProbe = true
        let value = cellValue(column, for: item, width: max(1, context.availableWidth), context: probe)
        return value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { String($0).stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// `context` over a raised background: what the focused, selected row's
    /// cells render under (``BackgroundProminence``).
    private static func raised(_ context: RenderContext) -> RenderContext {
        var raised = context
        raised.environment.backgroundProminence = .increased
        return raised
    }

    /// A rendered cell's lines, at most `limit` of them, as one string.
    private static func cellLines(_ buffer: FrameBuffer, limit: Int) -> String {
        guard buffer.height > 1 else { return buffer.lines.first ?? "" }
        return buffer.lines.prefix(limit).joined(separator: "\n")
    }

    /// `context` as a measure pass: what a cell drawn under it may not do —
    /// register a control for focus, publish a hit region — it does not do.
    private static func probing(_ context: RenderContext) -> RenderContext {
        var probe = context
        probe.isMeasuring = true
        return probe
    }

    /// The rows boxed for comparison, when the row type can be compared —
    /// `nil` when it cannot, which is what makes the memo below decline rather
    /// than guess. The same question, and the same answer, as
    /// `ForEach.listRowsSignature`.
    ///
    /// Takes the rows as ONE opaque generic parameter rather than reading
    /// `data` — or taking `[Row]` — because of a compiler bug, not a design
    /// choice. Wherever `Foundation` is imported, 6.2.4 warns "conditional cast
    /// from `[T]` to `any Equatable` always succeeds" for any array type; it
    /// does not always succeed, and at runtime it correctly fails for an
    /// element type that is not `Equatable`. Reduced and pinned in
    /// `Tools/CompilerBugs/ArrayEquatableCastWarning`, and the behaviour the
    /// memo depends on is pinned again by `TableFitColumnMemoTests`, which
    /// renders a table of un-comparable rows and counts the scans.
    private static func rowsSignature<Rows>(of rows: Rows) -> AnyEquatableBox? {
        (rows as? any Equatable).map { AnyEquatableBox($0) }
    }

    /// The width a `.fit` column needs: the widest of its header and every one
    /// of its cell values, kept across frames for as long as the rows have not
    /// changed.
    ///
    /// The scan is O(rows) — all of them, not just the visible ones, so the
    /// column does not change width as the table scrolls — and it runs more
    /// than once a frame, because the analytic size and the render each ask.
    /// On five thousand rows that is 324 µs a frame for ONE column (2026-09-21),
    /// whether or not anything about the table moved.
    ///
    /// This is the question `_ListCore.widestRowWidth` asks of a `List`, so it
    /// is answered the same way and with the same four guards, rather than with
    /// a second set of rules: a size entry under the table's own identity,
    /// compared against the rows' DATA; the table marks itself active or the
    /// entry dies at the end of the pass it was stored in; a value read from a
    /// per-frame source declines the store; and so does an environment carrying
    /// something that cannot be compared.
    ///
    /// Invalidation comes from the cache's own rules, which is why there is
    /// none here: a `@State` write clears the identity that owns it together
    /// with everything above and below it, so a write anywhere between the app
    /// root and a cell's closure takes this entry with it — including the
    /// `sortOrder` a click on a header writes, which changes the header text
    /// this measures.
    ///
    /// It inherits the row memo's captured-data hole too (see
    /// `foreach-memo-captured-data-hole`): a cell closure whose answer changes
    /// without the data changing and without any write the cache sees is not
    /// noticed. Unchanged data whose *rendering* silently changed is the same
    /// bargain a `ForEach` row already makes.
    ///
    /// Data that cannot be compared — a row type that is not `Equatable` — has
    /// no signature, so it scans every frame exactly as before.
    private func fitWidth(
        of column: _TableColumnSpec<Value>, cappedAt cap: Int?, context: RenderContext
    ) -> Int {
        // The cap is in the key: a scan that stopped early answers for the
        // interior it stopped against, and a wider table wants the real width.
        // The height fields carry the column INDEX rather than a height — a fit
        // width has no height to depend on, and one entry per column has to be
        // told from the next.
        let key = RenderCache.SizeKey(
            identityHash: context.identity.structuralHash,
            proposalWidth: cap, proposalHeight: nil,
            availableWidth: cap ?? -1, availableHeight: column.declarationIndex,
            hasExplicitWidth: false, hasExplicitHeight: false,
            measureGeneration: context.measureGeneration)
        let memo: (cache: RenderCache, signature: AnyEquatableBox)? =
            if let cache = context.renderCache, let signature = Self.rowsSignature(of: data) {
                (cache, signature)
            } else {
                nil
            }
        if let memo {
            // The table is not a memoising view, so nothing else marks it.
            memo.cache.markActive(context.identity)
            if let cached = memo.cache.lookupSize(key: key, view: memo.signature) {
                guard RenderCache.verifiesMeasureMemo else { return cached.width }
                // Scanned again, on the check's own tracker, and the fresh
                // width is the one laid out: the check the value memo's sizes
                // get, for the size this table keeps in the same store.
                return verifyServedSize(
                    cached, label: "\(Self.self) column \(column.declarationIndex) fit width",
                    proposal: ProposedSize(width: cap, height: nil), context: context
                ) {
                    ViewSize.fixed(
                        scanForFitWidth(of: column, cappedAt: cap, context: $0), 0)
                }.width
            }
        }

        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        let unsafeBefore = tracker.cacheUnsafeCount
        // What the scan observed lives as long as the width it found is kept
        // (see `ObservationLeases`). Cells are `String` closures, and one that
        // reads an `@Observable` is read here and nowhere a body is: observed
        // at the table, so a write drops the width it fitted.
        let leaseMark = context.renderCache?.leases.beginComputation()
        let fitted = observingKeptResult(of: Self.self, kind: .keptMeasure, context: context) {
            scanForFitWidth(of: column, cappedAt: cap, context: context)
        }
        let lease = context.renderCache?.leases.endComputation(leaseMark)

        if let memo, tracker.cacheUnsafeCount == unsafeBefore,
            !context.environment.hasUncomparableEnvironmentValue
        {
            memo.cache.storeSize(
                key: key, identity: context.identity, view: memo.signature,
                size: ViewSize.fixed(fitted, 0), lease: lease)
        }
        return fitted
    }

    /// The widest of `column`'s header and cells, stopping at `cap` — the scan
    /// ``fitWidth(of:at:cappedAt:context:)`` keeps the answer of.
    private func scanForFitWidth(
        of column: _TableColumnSpec<Value>, cappedAt cap: Int?, context: RenderContext
    ) -> Int {
        // The header measured here is the one that will be DRAWN, sort
        // indicator and all: measuring the bare title instead fitted the
        // column two cells short and truncated its own header ("Track…").
        var fitted =
            headerLines(context.environment) > 0 ? headerTitle(for: column).strippedLength : 0
        // A view cell is measured at the widest the column could be, under a
        // measuring context: this walks every row, drawn or not.
        let probe = column.laysOutItsOwnLines ? Self.probing(context) : context
        let probeWidth = cap ?? context.availableWidth
        // A one-line column's cell is one line however it arrived — a view
        // cell keeps its first — so only a taller one has lines to compare.
        let mayHaveLines = column.laysOutItsOwnLines && column.lineLimit > 1
        for item in data {
            let value = cellValue(column, for: item, width: probeWidth, context: probe)
            fitted = max(fitted, Self.widestLine(of: value, laidOut: mayHaveLines))
            if let cap, fitted >= cap { break }
        }
        return fitted
    }

    /// A cell's width in cells: its widest line when it arrived laid out.
    private static func widestLine(of value: String, laidOut: Bool) -> Int {
        guard laidOut, value.containsLineFeed else { return value.strippedLength }
        return value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).strippedLength }.max() ?? 0
    }

    // MARK: - Header Rendering

    /// - Parameter emphasised: Whether the titles take the primary ink rather
    ///   than the secondary — under `.tableStyle(.surface)`, whose header is a
    ///   step stronger.
    private func renderHeader(
        columnWidths: [Int], gutter: Int, palette: any Palette,
        picking handler: ItemListHandler<Value.ID>? = nil, emphasised: Bool = false
    ) -> ClaimingRow {
        let ink = emphasised ? palette.foreground : palette.foregroundSecondary
        let pickedColumn = handler.flatMap(pickedColumn)
        // Through `ClaimingRow` so the header's own colour states its opaque spelling
        // and sends its alpha up as a region. `foregroundSecondary` is a re-spelling of
        // the palette's foreground and carries its alpha, so a faded theme reaches here
        // — and the row is what knows which columns each cell occupies, gutter and
        // spacing included. Adjacent cells owe one alpha, so it coalesces to a single
        // rectangle across the titles.
        var row = ClaimingRow()
        row.skip(cells: gutter)
        for (offset, index) in columns.indices.enumerated() where offset < columnWidths.count {
            if offset > 0 { row.skip(cells: columnSpacing) }
            let column = columns[index]
            let width = columnWidths[offset]
            let aligned = alignText(
                headerTitle(for: column, fittingWidth: width),
                width: width,
                alignment: column.alignment,
                truncationMode: column.truncationMode
            )
            guard offset == pickedColumn else {
                row.append(aligned, cells: width, ink: ink, bold: true)
                continue
            }
            // The picked column: the still fill a selected row wears, in the
            // palette's own colours — or the pair reversed where the fill
            // cannot be measured — so it reads as chosen, as a row in hand
            // does, rather than as a header that is merely focused.
            switch palette.selectedRowFill().stillFill {
            case .fill(let field):
                row.append(aligned, cells: width, ink: palette.foreground, field: field, bold: true)
            case .reversed(let ink, let field), .reversingPulse(_, _, let ink, let field):
                row.append(aligned, cells: width, ink: ink, field: field, bold: true, inverted: true)
            case .pulse(_, let bright):
                row.append(aligned, cells: width, ink: palette.foreground, field: bright, bold: true)
            }
        }
        return row
    }

    /// A column's header text, with the sort indicator when the table sorts.
    ///
    /// Every SORTABLE column reserves the indicator's width, not just the one
    /// being sorted by: a slot that appeared and disappeared would re-measure
    /// `.fit` columns on every click, so the table would change width as you
    /// sorted it. Columns that cannot sort — and every column of a table with
    /// no `sortOrder` binding — reserve nothing, so an existing table renders
    /// exactly as it did.
    ///
    /// - Parameter width: The cells the header cell will actually get, when the
    ///   caller is about to draw it. Omit it (the measuring path) for the
    ///   natural width, which ALWAYS reserves the slot — that reservation is
    ///   what keeps a column from resizing when you sort it.
    ///
    /// Passing the width changes two things, both about what is DRAWN rather
    /// than how wide the column is:
    ///
    /// - An unsorted column draws its bare title, with no trailing blank. The
    ///   slot is still reserved in the width, but padding the text into it
    ///   pushed a `.trailing` header two cells off its column's right edge —
    ///   misaligning the common case (no sort on this column) to reserve room
    ///   for the rare one. The text shifts left when an arrow actually appears.
    /// - When there is an arrow and the column is too narrow for both, the TITLE
    ///   gives way first: `Tra… ▼`, not `Track…`. The arrow is the part you
    ///   cannot reconstruct by guessing, and one that vanishes exactly when the
    ///   table is cramped hides which column you just sorted by.
    private func headerTitle(for column: _TableColumnSpec<Value>, fittingWidth width: Int? = nil)
        -> String
    {
        guard sortModel != nil, column.sortComparator != nil else { return column.title }
        let indicator = sortIndicator(for: column)
        let suffix = " " + indicator
        guard let width else { return column.title + suffix }
        guard indicator != Self.noSortIndicator else {
            return column.title.truncatedToWidth(width, mode: column.truncationMode)
        }
        let room = width - suffix.strippedLength
        // Narrower than the indicator's own slot: drop the separating space and
        // the title, and keep the arrow alone. Truncating `suffix` here would
        // keep the SPACE and lose the arrow, which is the wrong end.
        guard room > 0 else { return indicator.truncatedToWidth(width, mode: .tail) }
        return column.title.truncatedToWidth(room, mode: column.truncationMode) + suffix
    }

    /// What ``sortIndicator(for:)`` returns for a sortable column that is not
    /// the one being sorted by — a blank the width calculation still reserves.
    private static var noSortIndicator: String { " " }

    /// `▲` / `▼` for the column the rows are currently ordered by, a space for
    /// any other sortable column.
    ///
    /// Only the PRIMARY comparator is marked. Later ones in the sort order are
    /// real — they break the primary's ties — but marking them would say the
    /// rows are ordered by them, which they are not, and macOS marks one too.
    private func sortIndicator(for column: _TableColumnSpec<Value>) -> String {
        guard let comparator = column.sortComparator,
            let order = sortModel?.primaryOrder(comparator)
        else { return Self.noSortIndicator }
        return order == .forward ? "▲" : "▼"
    }

    /// The x range each column's header occupies within the table's buffer,
    /// paired with the column's index.
    ///
    /// Derived from the same widths and spacing `renderHeader` lays the titles
    /// out with, so a click lands on the title it is under. `originX` is where
    /// the header line starts inside the buffer: past the border and the
    /// container's padding, then past the indicator indent.
    private func headerColumnRanges(
        columnWidths: [Int], originX: Int, gutter: Int
    ) -> [(Int, Range<Int>)] {
        var ranges: [(Int, Range<Int>)] = []
        ranges.reserveCapacity(columnWidths.count)
        var x = originX + gutter
        for (index, width) in zip(columnWidths.indices, columnWidths) {
            ranges.append((index, x..<(x + width)))
            x += width + columnSpacing
        }
        return ranges
    }

    /// Which column the rows are currently ordered by, or `nil` when the sort
    /// order is empty or names a key path no column carries.
    ///
    /// The same predicate `sortIndicator(for:)` draws the arrow from, so the
    /// arrow and the chords cannot disagree about which column is primary.
    private var primarySortColumnIndex: Int? {
        guard let sortModel else { return nil }
        return columns.firstIndex { column in
            column.sortComparator.flatMap(sortModel.primaryOrder) != nil
        }
    }

    /// The keyboard half of the header click, handed to the handler each frame
    /// (see `ItemListHandler.onSort`).
    ///
    /// `.sortNextColumn` runs `toggleSort(column:)` on the next sortable column,
    /// wrapping — with exactly ONE sortable column that is the primary itself,
    /// so the chord flips its direction, precisely as clicking the one clickable
    /// header twice does. `.reverseSortOrder` runs it on the primary, which
    /// reverses it, and does nothing while the sort order is empty: there is no
    /// direction to reverse yet, and Ctrl-S establishes one.
    ///
    /// `nil` — leaving both chords to the app — for a table with no `sortOrder`
    /// binding or no sortable column, which is exactly when no header takes a
    /// click either.
    private var sortKeyAction: ((RowAction) -> Void)? {
        // NOT a convenience ordering: the binding is tested first, and with
        // `contains(where:)` rather than a `filter`, because this property runs
        // on every pass of every table — measure passes included, which is why
        // `viewportHeight` above is gated on `isMeasuring`. Building the index
        // list here charged an array allocation per pass to tables that have no
        // `sortOrder` binding at all, which is most of them.
        guard sortModel != nil, columns.contains(where: { $0.sortComparator != nil })
        else { return nil }
        return { action in
            // Walked when a key actually arrives rather than once per pass: a
            // keystroke is rare and this allocates. Non-empty, per the guard.
            let sortable = columns.indices.filter { columns[$0].sortComparator != nil }
            let index: Int?
            switch action {
            case .sortNextColumn:
                let current = primarySortColumnIndex
                index = current.flatMap { c in sortable.first { $0 > c } } ?? sortable.first
            case .reverseSortOrder:
                index = primarySortColumnIndex
            // The handler passes only the two sort actions; every other row verb
            // is the handler's own business. Written out rather than defaulted so
            // the next `RowAction` has to be answered here too.
            case .selectAll, .extendSelection, .pickUpRow, .placeRow, .cancelMove, .customizeColumns,
                .moveRowUp, .moveRowDown, .moveRowToTop, .moveRowToBottom,
                .moveRowPageUp, .moveRowPageDown:
                index = nil
            }
            guard let index else { return }
            toggleSort(column: columns[index])
        }
    }

    /// Applies a click on `column`'s header to the bound sort order.
    ///
    /// Clicking the column already sorted by flips its direction; clicking any
    /// other sortable column makes it the primary sort, ascending, and pushes
    /// what was there down behind it — so the previous sort survives as the
    /// tie-break, which is what a macOS table does and what makes a two-key
    /// sort reachable by clicking two headers in turn.
    private func toggleSort(column: _TableColumnSpec<Value>) {
        guard let sortModel, let comparator = column.sortComparator else { return }
        sortModel.toggle(comparator)
    }

    // MARK: - Row Rendering

    /// The half of a row's key that the FRAME settles — see `TableRowMemo.swift`.
    private func rowFrameKey(
        columnWidths: [Int], gutter: Int, rowWidth: Int, stripe: Color?, context: RenderContext,
        palette: any Palette
    ) -> TableRowFrameKey {
        TableRowFrameKey(
            columnWidths: columnWidths,
            columnSpacing: columnSpacing,
            gutter: gutter,
            rowWidth: rowWidth,
            ink: cellColour(row: 0, ramp: nil, context: context, palette: palette),
            selectedMark: RowSelectionIndicator.forRow(
                isFocused: false, isSelected: true, context: context, palette: palette),
            unselectedMark: RowSelectionIndicator.forRow(
                isFocused: false, isSelected: false, context: context, palette: palette),
            stripe: stripe,
            alignments: columns.map(\.alignment),
            truncations: columns.map(\.truncationMode),
            lineLimits: columns.map(\.lineLimit),
            colorDepth: ColorDepth.current,
            colorGeneration: TerminalColors.generation,
            widthGeneration: TerminalWidthTraits.generation,
            cellText: cascadesCellText == false ? StyleAttributes() : Self.cellTextAttributes(context.environment))
    }

    /// Whether this table's rows may be kept across frames at all.
    ///
    /// Every column has to NAME its value rather than compute one. A key path
    /// cannot capture the search term, the formatter or the units toggle that a
    /// closure column captures and that no row value would ever show — so where
    /// every column is a key path, an equal row draws equal text, and where any
    /// column is a closure it does not and the memo stands aside. See
    /// `TableRowMemo.swift`; this is the whole of the soundness argument.
    private var columnsNameTheirValues: Bool {
        !columns.isEmpty && columns.allSatisfy(\.namesAProperty)
    }

    /// Opens the row store for a frame, or empties it if this table may not keep
    /// rows at all. Called once per frame by each row-composing path.
    ///
    /// - Parameter stripe: What this frame's striped rows wear
    ///   (`frameStripe(context:palette:)`), which the key carries.
    private func beginRowMemo(
        handler: ItemListHandler<Value.ID>, columnWidths: [Int], gutter: Int, rowWidth: Int,
        stripe: Color?, context: RenderContext, palette: any Palette
    ) {
        guard !context.isMeasuring else {
            handler.tableRowMemo.removeAll()
            return
        }
        handler.tableRowMemo.begin(
            frame: rowFrameKey(
                columnWidths: columnWidths, gutter: gutter, rowWidth: rowWidth, stripe: stripe,
                context: context, palette: palette),
            viewportHeight: handler.viewportHeight,
            namesItsValues: columnsNameTheirValues)
    }

    private func renderRow(
        item: Value,
        paint: RowPaint,
        columnWidths: [Int],
        isFocused: Bool,
        isSelected: Bool,
        isReturningHome: Bool = false,
        context: RenderContext,
        palette: any Palette,
        memo handler: ItemListHandler<Value.ID>? = nil
    ) -> DrawnSingleLineRow {
        /// What the cells' controls registered this frame. Fresh whichever
        /// line is drawn, kept or composed: see ``_TableRowPayload``.
        var payload = _TableRowPayload()
        /// Hands back a kept row, counted and — under the verifier — checked,
        /// with the payload its cells produced on THIS frame, never a kept one:
        /// see ``_TableRowPayload``.
        func serve(_ kept: TableRowDrawnLine) -> DrawnSingleLineRow {
            context.renderCache?.rowWork.served += 1
            verifyRowServe(
                kept.line, item: item, paint: paint, columnWidths: columnWidths,
                isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
            return (kept.line, nil, nil, kept.claims, payload)
        }
        /// `kept` as drawn at the stripe parity this row has NOW: as kept at
        /// that parity, or drawn there again from the cells it kept and kept
        /// there for the next time — no cell closure runs. `nil` for a line
        /// that would breathe, which is never kept. See
        /// ``TableRowMemoLine/drawn(striped:)``.
        func atParity(_ kept: TableRowMemoLine, isStriped: Bool) -> TableRowDrawnLine? {
            if let drawn = kept.drawn(striped: isStriped) { return drawn }
            let again = renderRowUncached(
                cells: kept.cells, item: item, paint: paint, columnWidths: columnWidths,
                isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
            guard again.pulseFrames == nil else { return nil }
            context.renderCache?.rowWork.repainted += 1
            let drawn = TableRowDrawnLine(line: again.line, claims: again.claims)
            var both = kept
            both.keep(drawn, striped: isStriped)
            handler?.tableRowMemo.keep(both, for: item.id)
            return drawn
        }
        func compose(_ cells: [String]) -> DrawnSingleLineRow {
            // Composed from scratch, which for a `Table` without a memo is
            // every drawn row of every frame — the asymmetry with `List`, whose
            // rows reach `_MemoizedRow` and can be SERVED, in one number. See
            // ``RenderCache/RowWork``.
            context.renderCache?.rowWork.rendered += 1
            let row = renderRowUncached(
                cells: cells, item: item, paint: paint, columnWidths: columnWidths,
                isFocused: isFocused, isSelected: isSelected, isReturningHome: isReturningHome,
                context: context, palette: palette)
            // A row walking home draws a blank, and a blank has nothing to click.
            return (row.line, row.pulseFrames, row.pulseTiming, row.claims, isReturningHome ? _TableRowPayload() : payload)
        }
        // A ramp colours a row by its ORDINAL, which moves when the table
        // scrolls while the row does not, so a ramped table keeps nothing.
        //
        // Nor is the CURSOR row of a focused table ever kept or served: how it
        // looks answers to more than the row — whether it breathes is the
        // indicator style's to say, and nothing about the style is in the frame
        // key — so a cursor row kept while it was still, under `.none`, was
        // served still again once the style asked it to breathe. Every other
        // row's look is its data and its selection. It is one row a frame, and
        // one that was never kept while it breathed anyway.
        guard let handler, handler.tableRowMemo.isOpen, !isReturningHome, paint.ramp == nil,
            !isFocused
        else {
            // The focused, selected row's cells render over a raised background.
            let cellContext = isFocused && isSelected ? Self.raised(context) : context
            return compose(
                rowCells(
                    for: item, columnWidths: columnWidths, context: cellContext, payload: &payload))
        }
        let kept = handler.tableRowMemo.entry(for: item.id)
        let rowBox = Self.rowsSignature(of: item)
        // A row that moved to the other parity changes its stripe, which
        // neither its cells nor its selection say — and which `atParity`
        // serves as kept at that parity, or draws there again from the cells
        // it kept, rather than running its cells again.
        let isStriped = paint.stripe != nil
        // And one that came to refuse selection draws faint, which its cells
        // do not say either.
        let isDimmed = selectionDisabledRows.contains(paint.row)

        // The cheapest hit there is: every column names its value, so the cells
        // are a pure function of the row, and an equal row needs no cells built
        // at all. Only available to a comparable row type. Nothing is lost by
        // not running the cells: a column that names its value is never a view,
        // so there is no control in the row to register.
        if let kept, let rowBox, handler.tableRowMemo.namesItsValues,
            kept.answers(row: rowBox, isSelected: isSelected, isDimmed: isDimmed),
            let atThisParity = atParity(kept, isStriped: isStriped)
        {
            return serve(atThisParity)
        }

        // Otherwise the closures have to run — that is the app's own cost and
        // nothing can skip it — but what they produced settles the question
        // outright, for any row type and any column.
        let cells = rowCells(
            for: item, columnWidths: columnWidths, context: context, payload: &payload)
        if let kept,
            kept.answers(cells: cells, isSelected: isSelected, isDimmed: isDimmed),
            let atThisParity = atParity(kept, isStriped: isStriped)
        {
            // Re-point the entry at THIS row, or a row that changed in a way its
            // columns do not show would take this path for ever — see
            // `TableRowMemoStore.refresh(row:for:)`.
            if handler.tableRowMemo.namesItsValues, let rowBox, kept.row != rowBox {
                handler.tableRowMemo.refresh(row: rowBox, for: item.id)
            }
            // The kept line, and the payload of the cells that just ran: their
            // controls registered on THIS frame, under ids the line's regions
            // must name.
            return serve(atThisParity)
        }

        let tracker = context.environment.volatileReadTracker
        let unsafeBefore = tracker?.cacheUnsafeCount ?? 0
        let result = compose(cells)
        // A row that BREATHES is one frame of a cycle, and a row that consulted
        // a per-frame value said so — neither may be kept, by the rule every
        // other memo in the framework states as "never a time-varying subtree".
        guard result.pulseFrames == nil, tracker?.cacheUnsafeCount ?? 0 == unsafeBefore else {
            return result
        }
        handler.tableRowMemo.keep(
            TableRowMemoLine(
                row: rowBox, cells: cells, isSelected: isSelected, isStriped: isStriped,
                isDimmed: isDimmed, drawn: TableRowDrawnLine(line: result.line, claims: result.claims)),
            for: item.id)
        return result
    }

    /// Re-composes a served row and reports a disagreement, under
    /// `TUIKIT_VERIFY_RENDER_MEMO`.
    ///
    /// The value memo gets this from `verifyServe`; a store that lives outside
    /// the render cache has to say it, and saying it is the price of living
    /// outside. It costs more than the memo saves, so it is never on in an app
    /// — the flag is for the standing CI lane and the contract suite, both of
    /// which now cover rows.
    private func verifyRowServe(
        _ servedLine: String,
        item: Value, paint: RowPaint, columnWidths: [Int], isFocused: Bool, isSelected: Bool,
        context: RenderContext, palette: any Palette
    ) {
        guard RenderCache.verifiesRenderMemo, let cache = context.renderCache else { return }
        // The check compares lines; what the cells registered is the served
        // row's, already.
        var unused = _TableRowPayload()
        let fresh = renderRowUncached(
            cells: rowCells(
                for: item, columnWidths: columnWidths, context: context, payload: &unused),
            item: item, paint: paint, columnWidths: columnWidths, isFocused: isFocused,
            isSelected: isSelected, isReturningHome: false, context: context, palette: palette)
        guard fresh.line != servedLine else { return }
        cache.noteRenderMemoMismatch(
            viewType: "\(Self.self) row", served: FrameBuffer(lines: [servedLine]),
            fresh: FrameBuffer(lines: [fresh.line]), identity: identityKey(item.id))
    }

    /// The display string of every column for one row, in column order, asked
    /// exactly once each.
    ///
    /// Split out of the compose loop so that a row's cells can be compared with
    /// the ones a kept line was built from. That comparison is the whole of the
    /// memo's soundness for a closure column: the closure may capture anything,
    /// but once it has RUN, what it produced is not a proxy for the row's text
    /// — it is the row's text.
    ///
    /// A view cell drawn under a live context leaves what its controls
    /// registered in `payload`, placed in the row — see ``_TableRowPayload``.
    private func rowCells(
        for item: Value, columnWidths: [Int], context: RenderContext,
        payload: inout _TableRowPayload
    ) -> [String] {
        let count = min(columns.count, columnWidths.count)
        var cells: [String] = []
        cells.reserveCapacity(count)
        for index in 0..<count {
            let column = columns[index]
            guard case .view = column.cell, !context.isMeasuring else {
                cells.append(
                    cellValue(column, for: item, width: columnWidths[index], context: context))
                continue
            }
            let buffer = viewCell(column, for: item, width: columnWidths[index], context: context)
            cells.append(Self.cellLines(buffer, limit: column.lineLimit))
            absorbPayload(
                of: buffer, column: index, columnWidths: columnWidths, context: context,
                into: &payload)
        }
        return cells
    }

    /// A view cell's buffer, counted as ``cellValue(_:for:width:context:)``
    /// counts it — the one place a view cell is rendered.
    private func viewCell(
        _ column: _TableColumnSpec<Value>, for item: Value, width: Int, context: RenderContext
    ) -> FrameBuffer {
        guard case .view(let render) = column.cell else { return FrameBuffer() }
        context.renderCache?.rowWork.cellValues += 1
        return render(item, cellContext(column, for: item, width: width, context: context))
    }

    /// Places a drawn view cell's payload in its row: at the column's start,
    /// past the selection gutter and every column and gap before it. Asked
    /// only of a cell that carries something, so the gutter and the walk are
    /// never paid by a row that has nothing to place.
    private func absorbPayload(
        of buffer: FrameBuffer, column index: Int, columnWidths: [Int], context: RenderContext,
        into payload: inout _TableRowPayload
    ) {
        guard !buffer.hitTestRegions.isEmpty || !buffer.overlays.isEmpty else { return }
        var x = selectionGutter(context.environment)
        for previous in 0..<index { x += columnWidths[previous] + columnSpacing }
        payload.absorb(
            buffer, atColumn: x, width: columnWidths[index], lines: columns[index].lineLimit,
            alignment: columns[index].alignment)
    }

    private func renderRowUncached(
        cells: [String],
        item: Value,
        paint: RowPaint,
        columnWidths: [Int],
        isFocused: Bool,
        isSelected: Bool,
        isReturningHome: Bool = false,
        context: RenderContext,
        palette: any Palette,
    ) -> (
        line: String, pulseFrames: [String]?, pulseTiming: IndicatorCycleTiming?,
        claims: [OpacityRegion]
    ) {
        let (row, ramp, rowWidth) = (paint.row, paint.ramp, paint.width)
        // A row whose picture is still walking back to it keeps its space and
        // draws nothing in it — see ``ItemListHandler/returningRows``, and
        // `_ListCore.renderRow`, which does the same for the same reason.
        // Nothing animates: a run would paint over the blank on its next tick.
        guard !isReturningHome else {
            return (String.spaces(max(0, rowWidth)), nil, nil, [])
        }
        let visualState = rowVisualState(
            isFocused: isFocused,
            isSelected: isSelected,
            stripe: paint.stripe,
            context: context,
            palette: palette
        )

        let gutter = selectionGutter(context.environment)

        // Every cell of every row is coloured the same, so derive its SGR
        // introducer ONCE rather than rebuilding an identical `TextStyle` and
        // re-joining its codes per cell (`ANSIRenderer.render` was 18.1%
        // inclusive of a `tables-scroll` frame, `buildStyleCodes` 6.8%) — and
        // state it once per run of plain cells, not per cell (`TableRowInk`).
        // A ramp that varies ALONG the row cannot have one introducer for the
        // whole row, so that case paints cell by cell instead — through the
        // same walk `Text` uses, so the two cannot disagree about where a
        // colour changes. Every other case, ramp or not, keeps the single
        // introducer this comment is about.
        let bandsAcrossRow = ramp?.variesAcrossRow ?? false
        let cellInk = cellColour(row: row, ramp: ramp, context: context, palette: palette)
        var cellStyle = TextStyle()
        // Opaque on both arms. A banded row's cells take their colour from the ramp
        // rather than from this style, so what is spelled here only reaches the
        // single-introducer arm — but a `TextStyle` carrying a translucent colour into
        // `band` at all is the shape §18.3 warns about, and the answer is the same
        // either way now that both arms claim (§36).
        cellStyle.foregroundColor = cellInk.opaqueSpelling
        // The cells are text: a tier heavier under a bold legibility weight.
        let boldCells = context.environment.legibilityWeight.drawsPlainBold
        if boldCells { cellStyle.isBold = true }
        let cellSequence = bandsAcrossRow ? nil : ANSIRenderer.styleSequence(for: cellStyle)
        var rampSequences: [String?] = []
        var ink = TableRowInk(
            introducer: cellSequence, under: visualState.background, bandsAcrossRow: bandsAcrossRow,
            insideListRow: context.environment.listRowEditRestrictions != nil, bold: boldCells)

        // One buffer for the whole row. The previous form built a `[String]` of
        // styled cells, `joined` them, and concatenated the indicator and the
        // padding — an array plus a fresh String per cell and per join, thrown
        // away immediately. Table rendering was spending **26% of the frame
        // inside the allocator** (`tiny_free_*` / `tiny_malloc_*`), and rows
        // are the bulk of it. Spacing and padding come from the shared
        // `asciiSpaces` run, so neither allocates either.
        let spacing = asciiSpaces(columnSpacing)
        var content = ""
        content.reserveCapacity(rowWidth * 2)
        // The mark is only drawn into a gutter, so only spelled where there is
        // one: a table without a selection, or whose marks are hidden, has none
        // (`selectionGutter`).
        if gutter > 0 {
            ink.appendMark(visualState.indicator, in: visualState.indicatorColor.opaqueSpelling, into: &content)
            content += " "
        }

        let cellCount = min(columns.count, columnWidths.count)
        // Where the cells start, for a ramp that varies along the row: the
        // indicator and the gap after it, or column zero when there is neither.
        var cellColumn = gutter
        for index in 0..<cellCount {
            if index > 0 {
                content.append(contentsOf: spacing)
                cellColumn += columnSpacing
            }
            let column = columns[index]
            let cellWidth = columnWidths[index]
            // Asked for once, by `rowCells(for:count:context:)`, before this
            // loop — so the column's value closure still runs exactly once and
            // in the same order whichever branch below draws it.
            let cellText = cells[index]
            if let ramp, bandsAcrossRow {
                var walked = cellColumn
                PaintRenderer.band(
                    alignText(
                        cellText, width: cellWidth, alignment: column.alignment,
                        truncationMode: column.truncationMode),
                    column: &walked, row: row, style: cellStyle,
                    sampler: ramp, sequences: &rampSequences, into: &content)
            } else {
                ink.open(before: cellText, into: &content)
                appendAligned(
                    cellText, width: cellWidth, alignment: column.alignment,
                    truncationMode: column.truncationMode, into: &content)
                ink.close(after: cellText, into: &content)
            }
            cellColumn += cellWidth
        }
        ink.finish(into: &content)

        // The background is applied to the FINISHED line, so a pulse is one
        // recolouring of it per step rather than one render of the row per step
        // — the same trick the menu row's bar uses. It works only because the
        // row itself paints no background of its own: an inner one would beat
        // the outer paint for the cells it covers.
        /// What this row's line owes, from the one derivation `_ListCore` also calls.
        ///
        /// The cells' rectangle stops at `cellColumn`, which the loop above has walked
        /// to the end of the last column — not at `rowWidth`, because the padding past
        /// it is bare and an ink claim on a cell with no ink of its own lets what is
        /// behind it through.
        func claims(fill: Color?) -> [OpacityRegion] {
            var stated = SelectableRowClaims.claims(
                line: 0, width: rowWidth, cells: gutter..<cellColumn,
                ink: bandsAcrossRow ? nil : cellInk,
                mark: gutter > 0 ? visualState.indicatorColor : nil, fill: fill)
            if let ramp, bandsAcrossRow {
                stated += ramp.alphaClaims(
                    row: row, line: 0, columns: gutter..<cellColumn)
            }
            return stated
        }
        // A row that refuses selection draws faint, under whatever background
        // it wears — as a `List` row does.
        if selectionDisabledRows.contains(row) {
            content = ANSIRenderer.applyPersistentDim(content)
        }
        guard case .none = visualState.background else {
            // `cellColumn` IS this line's visible width, so nothing rescans it:
            // the loop above walked it from `gutter` through every spacing and
            // every column, `appendAligned` puts exactly `cellWidth` cells in
            // each, and the mark is one cell by ``RowSelectionIndicator``'s
            // documented invariant (a mark of another width would move the
            // row's content, which is why it has one). A `strippedLength` here
            // was a second walk of the whole assembled row — escapes and all,
            // so the general path rather than the byte one — for every
            // selected, striped or focused row of every frame.
            let fill = visualState.background.claimableFill
            // A still background — a selected row's tint, a stripe — pads the
            // line inside its paint rather than in a copy of the line first.
            guard let paints = visualState.background.framePaints else {
                return (visualState.background.painting(content, padding: rowWidth - cellColumn), nil, nil, claims(fill: fill))
            }
            content.append(contentsOf: asciiSpaces(rowWidth - cellColumn))
            let frames = paints.map { $0.painting(content) }
            // The pulse's own frames need no spelling and earn no fill claim: both
            // ends of `accentFillPulse` spend a translucent tint's alpha against the
            // page, so every frame states a concrete colour (§29). The INK claim
            // still applies — the run repaints the field, not the glyphs, and
            // `resolvingOpacity` re-blends every frame through it.
            return (
                frames[visualState.background.stepNow], frames,
                visualState.background.pulseTiming, claims(fill: nil))
        }
        // A bare line, not a one-element array: a table renders every visible
        // row every frame, and the allocator is where its time goes (see the
        // one-SGR-introducer notes above). The multi-line and slot paths do
        // produce several lines, and say so with `RenderedRow`.
        return (content, nil, nil, claims(fill: nil))
    }

    /// A breathing line and every frame of it, at its position among the lines being
    /// assembled, with the frame duration and clock its cycle is laid out on.
    private typealias PulseRun = (y: Int, frames: [String], timing: IndicatorCycleTiming)

    /// A row's rendered lines, plus — when its background breathes — every frame
    /// of each line, ready to become an ``AnimatedCellRun`` once the caller
    /// knows where among the content lines it ended up.
    ///
    /// The twin of `_ListCore.RenderedRow`, for the same reason and with the
    /// same contract: `pulseFrames[line][step]`, index-aligned with `lines`, so
    /// whatever clipping the caller applies to one it applies to the other.
    private struct RenderedRow {
        var lines: [String]
        var pulseFrames: [[String]]?

        /// The frame duration and clock `pulseFrames` step on: the cycle's, carried
        /// to where the runs are built rather than assumed there.
        var pulseTiming: IndicatorCycleTiming?

        /// The cells this row's lines owe a blend, with `offsetY` an index into
        /// ``lines`` — the same frame `pulseFrames` is indexed in, so whatever
        /// clipping the caller applies to one it applies to all three.
        var claims: [OpacityRegion] = []

        /// What the row's view cells registered, `offsetY` an index into
        /// ``lines`` like the claims', and clipped with them.
        var payload = _TableRowPayload()

        /// This row between section headers' lines: `above` before its own lines
        /// and `below` after them, everything indexed by line moved past the
        /// lines above. A header line draws no background and never breathes.
        func within(above: [String], below: [String]) -> Self {
            guard !above.isEmpty || !below.isEmpty else { return self }
            var row = self
            row.lines = above + lines + below
            row.pulseFrames = pulseFrames.map {
                Array(repeating: [], count: above.count) + $0 + Array(repeating: [], count: below.count)
            }
            row.claims = claims.map { $0.shifted(byX: 0, y: above.count) }
            return row
        }

        /// This row with its first `count` lines taken off: what a top clip
        /// leaves of it. Everything indexed by line goes with them — the
        /// frames, so `pulseFrames[i]` stays the frames of `lines[i]`, and the
        /// claims and the cells' payload, whose lines taken off the FRONT move
        /// every survivor's index down by as many.
        func droppingFirst(_ count: Int) -> Self {
            guard count > 0 else { return self }
            var row = self
            row.lines.removeFirst(count)
            row.pulseFrames?.removeFirst(count)
            row.claims = claims.compactMap { claim in
                guard claim.offsetY >= count else { return nil }
                return claim.shifted(byX: 0, y: -count)
            }
            row.payload = payload.shifted(byX: 0, y: -count).clipped(toRows: 0..<row.lines.count)
            return row
        }

        /// This row cut to its first `count` lines: what the line budget leaves
        /// of a row leaving the bottom of the viewport.
        func keepingFirst(_ count: Int) -> Self {
            guard lines.count > count else { return self }
            var row = self
            let dropped = lines.count - count
            row.lines.removeLast(dropped)
            row.pulseFrames?.removeLast(dropped)
            row.claims = claims.filter { $0.offsetY < count }
            row.payload = payload.clipped(toRows: 0..<count)
            return row
        }
    }

    /// A multi-line row laid out: each cell's wrapped lines, the row's height
    /// (its tallest cell), and what its view cells registered.
    struct MultiLineRowLayout {
        let cells: [[String]]
        /// The row's whole height: its section headers' lines and its cells'.
        var height: Int
        var payload = _TableRowPayload()
        /// The lines of the section headers drawn above the row.
        var above: [String] = []
        /// The lines of the section headers drawn below it — the last row's.
        var below: [String] = []

        /// The lines the row's cells take.
        var cellHeight: Int { height - above.count - below.count }
    }

    /// How many frames a row's travel is cut into.
    ///
    /// The flights ask for 30 fps and run for 120 ms (out) and 200 ms (back),
    /// so eight frames is more than either can show — which is the right side
    /// to err on: a frame nobody draws costs one string, and a step nobody
    /// interpolates is a visible jump.
    static var previewMorphSteps: Int { 8 }

    /// One row's picture on its way from the GRID to the HAND: `steps` lines,
    /// the first laid out as the table draws the row and the last as a carried
    /// row is drawn. One step asks for the hand layout alone.
    ///
    /// Not `renderRow`. What makes a grid row as wide as the table is not the
    /// spacing between columns — it is that every cell is padded out to its
    /// layout width, and a `.flexible` column's width is all the room left
    /// over. A row in your hand is not a slice of the grid, so it takes each
    /// value clipped to its column (a pathological value still cannot out-grow
    /// the row it came from) and joins them with two cells, with no padding and
    /// no per-column alignment — there is no column to align within.
    ///
    /// The two layouts place the SAME clipped text and differ only in where.
    /// Interpolating the x of each cell's text between them is the whole
    /// animation — the difference used to happen between two frames, so the
    /// cells appeared to jump.
    ///
    /// Each cell is placed no further left than the end of the one before it,
    /// which cannot bind for any spacing the table allows but costs one
    /// comparison to guarantee — two cells overlapping would corrupt the line
    /// rather than merely look wrong.
    private func previewMorphLines(
        item: Value,
        row: Int,
        columnWidths: [Int],
        steps: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        // The morph is a transient animation of ONE row, so it takes that row's
        // colour from the ramp and does not band along itself — the cells are
        // sliding, and a colour that moved with them would read as a second
        // animation.
        let foregroundColor = cellColour(
            row: row, ramp: cellRamp(rowWidth: columnWidths.reduce(0, +), context: context),
            context: context, palette: palette)
        let count = min(columns.count, columnWidths.count)
        // The row in the hand keeps whatever gutter the grid gave it, so the
        // grab point — measured from the row line's first cell — still lands in
        // the column it was taken from.
        let gutter = selectionGutter(context.environment)
        let pad = String.spaces(gutter)
        guard count > 0, steps > 0 else { return Array(repeating: pad, count: max(0, steps)) }

        // The picture is of the row's FIRST line, as the hand carries it, and
        // it is a picture: measured, never drawn as live cells.
        let clipped = (0..<count).map {
            let value = cellValue(columns[$0], for: item, width: columnWidths[$0],
                context: Self.probing(context))
            let firstLine =
                value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            return firstLine.truncatedToWidth(columnWidths[$0], mode: columns[$0].truncationMode)
        }
        let widths = clipped.map(\.strippedLength)
        // The cells are text: a tier heavier under a bold legibility weight, as
        // the rows they are a picture of are.
        let bold = context.environment.legibilityWeight.drawsPlainBold

        var gridX: [Int] = []
        var cursor = gutter
        for index in 0..<count {
            gridX.append(
                cursor
                    + columns[index].alignment.childOffset(
                        childWidth: widths[index], in: columnWidths[index]))
            cursor += columnWidths[index] + columnSpacing
        }
        var handX: [Int] = []
        cursor = gutter
        for index in 0..<count {
            handX.append(cursor)
            cursor += widths[index] + Self.previewColumnSpacing
        }

        return (0..<steps).map { (step: Int) -> String in
            // A single step IS the hand layout — that is how `previewRow` asks
            // for the steady picture.
            let phase: Double = steps > 1 ? Double(step) / Double(steps - 1) : 1
            var line = pad
            var column = gutter
            for index in 0..<count {
                let travel: Double = Double(handX[index] - gridX[index]) * phase
                let target = gridX[index] + Int(travel.rounded())
                let start = max(column, target)
                line += String.spaces(start - column)
                line += ANSIRenderer.colorize(clipped[index], foreground: foregroundColor, bold: bold)
                column = start + widths[index]
            }
            return line
        }
    }

    /// Determines indicator symbol, indicator color, and background for a table row.
    /// Everything a row renderer needs in order to colour its cells: which row
    /// it is, the ramp running down the table, and how wide the row is.
    ///
    /// One value rather than three parameters because they are one question —
    /// "what colour is this row, and where does it change?" — and because the
    /// renderers were already at the limit of what a signature should carry.
    struct RowPaint {
        /// The row's ordinal in `data`.
        let row: Int

        /// The ramp, or `nil` to paint flat. See ``Table/cellRamp(rowWidth:context:)``.
        let ramp: RampSampler?

        /// The row's full width in cells — what the ramp was measured across.
        let width: Int

        /// The stripe this row wears, or `nil` for none: the frame's stripe
        /// (`frameStripe(context:palette:)`) on every other row, counting from
        /// the first however far the table has scrolled, so the stripes stay on
        /// their rows.
        ///
        /// The SECOND row and every other after it, the first left plain — the
        /// phase a macOS table draws (measured on macOS 15.8 by sampling each
        /// row's background in an offscreen `NSHostingView`, under `.automatic`,
        /// `.inset` and `.bordered` alike: rows 1, 3 and 5 tinted, 0, 2 and 4 the
        /// base; `Tools/SwiftUIProbes/List pinned headers and row stripes/phase.swift`).
        let stripe: Color?

        /// - Parameter frameStripe: What this frame's striped rows wear, or `nil`
        ///   where nothing stripes — see `frameStripe(context:palette:)`.
        init(row: Int, ramp: RampSampler?, stripe frameStripe: Color?, width: Int) {
            self.row = row
            self.ramp = ramp
            self.width = width
            self.stripe = row.isMultiple(of: 2) ? nil : frameStripe
        }
    }

    /// The laid-out cells of the rows a multi-line render is about to draw, and the
    /// column widths they were laid into.
    ///
    /// One value rather than two parameters for the reason ``RowPaint`` is one: the
    /// widths and the cells wrapped to them are a single fact — a row's cells and
    /// the widths they were measured against must never come from different frames —
    /// and `composeMultiLineRows` was already at the parameter count a signature
    /// should carry.
    struct MultiLineRowLayouts {
        /// The resolved width of each column, in cells.
        let columnWidths: [Int]

        /// The wrapped cells and height of the row at an index, memoised for the
        /// whole render — see `buildMultiLineContent`.
        let layout: (Int) -> MultiLineRowLayout
    }

    /// The ramp the cells are painted with, or `nil` when the paint is a plain
    /// colour — which is the ordinary case, and the one that keeps a table's
    /// row at a single SGR introducer.
    ///
    /// A table's unit is the ROW: the ramp steps once per row, so row *i* sits
    /// at *i* of `data.count`. Nothing inside a row can disagree with that,
    /// because a table paints its own cells rather than hosting views — which
    /// is what makes the ordinal safe here and not in a `List`, where a row's
    /// content offsets itself by lines. A row that wraps to several lines is
    /// therefore one step of the ramp.
    ///
    /// Built once per frame rather than once per row: the sampler does the
    /// divisions in its initialiser and answers per cell.
    ///
    /// - Parameters:
    ///   - rowWidth: The width the ramp runs across, for a horizontal one.
    ///   - context: The render context.
    /// - Returns: The sampler, or `nil` to paint flat.
    private func cellRamp(rowWidth: Int, context: RenderContext) -> RampSampler? {
        guard let paint = context.environment.foregroundStyle else { return nil }
        let extent =
            context.gradientContentFrame(width: rowWidth, height: max(1, data.count))
            ?? GradientFrame(width: rowWidth, height: max(1, data.count))
        return RampSampler(
            paint: paint, extent: extent, depth: ColorDepth.current,
            cellAspect: context.environment.imageCellAspect)
    }

    /// The colour a row's cells take: the ramp's answer at that row, or the
    /// flat foreground. Never asks the ramp when it varies ALONG the row —
    /// that case paints per cell, through ``PaintRenderer/band(_:column:row:style:sampler:sequences:into:)``.
    private func cellColour(
        row: Int, ramp: RampSampler?, context: RenderContext, palette: any Palette
    ) -> Color {
        guard let ramp else {
            return context.environment.foregroundStyle?.representative ?? palette.foreground
        }
        return ramp.colour(row: row).resolve(with: palette)
    }

    private func rowVisualState(
        isFocused: Bool,
        isSelected: Bool,
        stripe: Color?,
        context: RenderContext,
        palette: any Palette
    ) -> (indicator: String, indicatorColor: Color, background: RowBackground) {
        // The glyph is ``RowSelectionIndicator``'s answer, not a fourth copy of
        // the rules: `_ListCore` asks the same thing for the same gutter.
        let indicator = RowSelectionIndicator.forRow(
            isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
        let background: RowBackground =
            if isFocused && isSelected {
                // The cursor row of a focused table breathes. As a CYCLE, not a
                // live phase: the phase read marks the frame as having consulted
                // the clock, so the whole page was re-rendered on every tick to
                // recolour one row. The caller turns the cycle into
                // ``AnimatedCellRun``s over the row's own lines. Same colour
                // pair as `_ListCore`'s cursor row, from the same place.
                .focusedSelection(in: context, palette: palette)
            } else if isFocused {
                // The cursor on a row the selection does not include breathes too,
                // in the neutral focus wash rather than the accent. A reversal where
                // the wash cannot be measured — the same answer `_ListCore` takes for
                // the same row, from the same place.
                .focused(in: context, palette: palette)
            } else if isSelected && context.environment.unfocusedSelectionVisibility != .hidden {
                // A selected row the cursor is not on: the still tint of the accent a
                // `List` gives it, from the same place, and nothing where that tint
                // cannot be measured (``RowBackground/tint(_:)``) — the ● beside it
                // says it is selected. A table used to draw no fill here, so under
                // `.rowSelectionIndicator(.hidden)` its selected rows showed nothing
                // at all. `unfocusedSelectionVisibility(.hidden)` suppresses it, as it
                // does the List's.
                .tint(palette.selectedRowFill())
            } else if let stripe {
                // Every other row, under `.alternatingRowBackgrounds()` — the
                // tint a striped `List` draws, from the same place
                // (``RowPaint/stripe``).
                .fixed(stripe)
            } else {
                .none
            }
        return (indicator.glyph, indicator.color, background)
    }

    /// What this frame's striped rows paint behind themselves: the stripe over
    /// the surface the table sits on (``RowBackground/alternatingStripe(palette:over:)``'s
    /// colour), or `nil` where no row stripes — under
    /// `.alternatingRowBackgrounds(.disabled)`, or at a depth that draws none. A
    /// table stripes by default, as a macOS `Table` does under every style
    /// (measured; decisions A29).
    ///
    /// Derived ONCE per frame, by each path that composes rows, and handed to
    /// every row in its ``RowPaint`` and to the row memo's frame key — one
    /// derivation for both, which the key needs, since it has to change
    /// whenever this does. Not per striped row: the derivation reads the
    /// environment and the palette and weighs the stripe's contrast, the same
    /// answer for every row of the frame, and asking it per row was 18 calls a
    /// frame where 1 does on a 35-row table drawn cold. Not at all where
    /// nothing stripes.
    private static func frameStripe(context: RenderContext, palette: any Palette) -> Color? {
        guard context.environment.alternatingRowBackgrounds.stripes(byDefault: true) else { return nil }
        return palette.stripeFill(over: context.environment.enclosingSurface)
    }

    // MARK: - Text Alignment

    /// A cell's text clipped and padded into its column, written straight into
    /// the row buffer the caller is already assembling.
    ///
    /// This is the whole rule; `alignText` below is a wrapper for the two
    /// callers that need the cell as a value. It runs once per CELL per drawn
    /// line per frame — 1,040 times a frame on the `tables-scroll` shape (8
    /// tables x 25 rows x 5 columns, plus the headers) — and the previous form
    /// built two pad strings and a third for the `+`-chain result, only for the
    /// caller to copy that result into `content` and drop it. Appending instead
    /// reuses the two pieces every other pad site in the framework uses: the
    /// borrowed `asciiSpaces` run, and a buffer that was already reserved. Same
    /// reason the row itself stopped building a `[String]` of cells (see the
    /// one-buffer note in `renderRow`): a table's time goes to the allocator.
    private func appendAligned(
        _ text: String,
        width: Int,
        alignment: HorizontalAlignment,
        truncationMode: TruncationMode,
        into content: inout String
    ) {
        // Clip the value to the column width *first*: a cell that is wider
        // than its column would otherwise shove every column to its right
        // out of alignment. An over-long value is shown truncated with an
        // ellipsis so the loss of content is visible.
        let clipped = text.truncatedToWidth(width, mode: truncationMode)
        let visibleLength = clipped.strippedLength
        let padding = max(0, width - visibleLength)

        // Guide arithmetic, same as every other placement: the cell's visible
        // text is a `visibleLength`-wide child inside a `width`-wide column.
        let leftPad = alignment.childOffset(childWidth: visibleLength, in: width)
        let rightPad = padding - leftPad
        // Not a `String(repeating:)` pair. `childOffset(childWidth:in:)` clamps
        // its answer to `0...max(0, width - visibleLength)`, so both pads are
        // non-negative and both runs are plain ASCII U+0020 — byte-for-byte what
        // the `+` chain produced, minus the three temporaries.
        content += asciiSpaces(leftPad)
        content += clipped
        content += asciiSpaces(rightPad)
    }

    /// `appendAligned` as a value, for the two callers that cannot append.
    ///
    /// A banded cell goes to
    /// ``PaintRenderer/band(_:column:row:style:sampler:sequences:into:)`` whole
    /// — that call emits one SGR introducer per ramp entry across its argument,
    /// so splitting the cell into pad/text/pad would restart the run at each
    /// piece and change the bytes. The header wraps its cell in
    /// `ANSIRenderer.colorize`. Both share the body above rather than keeping a
    /// second copy of the clip-and-pad rule.
    ///
    /// Deliberately no `reserveCapacity`: reserving on an empty String forces
    /// native heap storage, and a header title or a narrow cell padded to its
    /// column usually fits the 15-byte small-string form, which the appends
    /// below keep. Reserving here would make this wrapper allocate where the
    /// `+` chain it replaces did not.
    private func alignText(
        _ text: String,
        width: Int,
        alignment: HorizontalAlignment,
        truncationMode: TruncationMode
    ) -> String {
        var aligned = ""
        appendAligned(
            text, width: width, alignment: alignment, truncationMode: truncationMode,
            into: &aligned)
        return aligned
    }
}

// MARK: - Column customization gestures

/// One header gesture in flight: what a drag over the header needs to keep
/// between its reports, and where the frame drew the header. Made each frame
/// and captured by that frame's header handlers — the titles' and the
/// table's own, which takes the gaps — so the press's handler, which the
/// dispatcher keeps for the rest of its gesture, keeps the press's.
@MainActor
private final class _TableHeaderGesture {
    /// What gives the table the focus, as a click anywhere on it does, and
    /// the table's focus identifier: stored, where a closure doing the same
    /// was an allocation of its own on every frame of every table.
    let focusManager: FocusManager?
    let focusID: String

    /// The header's line in the table's cells.
    let line: Int

    /// Where the first title starts on ``line``, past the border, the
    /// container's padding and the selection gutter.
    let titlesX: Int

    /// The frame's column widths, and the widest a column may be made — its
    /// row content's width: where the gaps between the titles are, and how
    /// far a drag on one may take its column.
    let columnWidths: [Int]
    let widest: Int

    /// Opens the column menu at a press, on a column (by identifier) or none,
    /// at a cell; `nil` for a table with no customization binding.
    let openMenu: ((String?, Int, Int) -> Void)?

    /// Where a resize drag was pressed, in the table's columns.
    var pressX = 0

    /// The column's width when the resize drag was pressed.
    var startWidth = 0

    /// Where the column a resize drag was pressed on takes its width, `nil`
    /// but between a press on a gap and its release.
    var resizing: _TableColumnResizer?

    /// Whether the drag has moved a column — then its release sorts nothing.
    var moved = false

    init(
        focusManager: FocusManager?, focusID: String, line: Int, titlesX: Int, columnWidths: [Int], widest: Int,
        openMenu: ((String?, Int, Int) -> Void)?
    ) {
        self.focusManager = focusManager
        self.focusID = focusID
        self.line = line
        self.titlesX = titlesX
        self.columnWidths = columnWidths
        self.widest = widest
        self.openMenu = openMenu
    }

    /// Gives the table the focus, as a click anywhere on it does.
    func focus() {
        focusManager?.focus(id: focusID)
    }
}

/// Where a column a user resizes takes its width, and the widths it may
/// take: `width` reads the one set, `nil` while none is, and `set` sets one.
private struct _TableColumnResizer {
    let bounds: ClosedRange<Int>
    let width: () -> Int?
    let set: (Int) -> Void
}

/// A table's column menu: "Hide" for the column it was opened on, then every
/// column with a mark while it is shown.
private struct _TableColumnMenu: View {
    /// One column's row: its title, whether it is shown, and what choosing it
    /// does — `nil` for a column whose visibility may not change.
    struct Entry {
        let title: String
        let isShown: Bool
        let toggle: (() -> Void)?
    }

    /// The "Hide" row, when the menu was opened on a column; its action is
    /// `nil` when that column may not be hidden.
    let hide: (title: String, action: (() -> Void)?)?

    let entries: [Entry]

    var body: some View {
        if let hide {
            Button(hide.title) { hide.action?() }
                .disabled(hide.action == nil)
            Divider()
        }
        ForEach(entries.indices, id: \.self) { index in
            let entry = entries[index]
            Toggle(entry.title, isOn: Binding(get: { entry.isShown }, set: { _ in entry.toggle?() }))
                .disabled(entry.toggle == nil)
        }
    }
}

extension _TableCore {
    /// `lines`, padded with blank lines as wide as the widest to `rows` where
    /// that is more, and each line's visible width — measured once, here: the
    /// content view sizes itself and builds its buffer from these rather than
    /// measuring every line again for each.
    static func filled(_ lines: [String], toRows rows: Int?) -> (lines: [String], widths: [Int]) {
        let widths = lines.map(\.strippedLength)
        guard let rows, lines.count < rows else { return (lines, widths) }
        let padWidth = widths.max() ?? 0
        let blanks = rows - lines.count
        return (
            lines + Array(repeating: String.spaces(padWidth), count: blanks),
            widths + Array(repeating: padWidth, count: blanks)
        )
    }
}

// MARK: - Table Content View

/// Simple view that renders pre-computed lines.
private struct _TableContentView: View, Renderable, Layoutable {
    let lines: [String]

    /// Each line's visible width, as the table measured it once making them:
    /// `lines.map(\.strippedLength)`.
    let lineWidths: [Int]

    /// The breathing row's cells, already positioned among `lines` — the header
    /// above and the container around shift them along with the lines.
    var runs: [AnimatedCellRun] = []

    /// The rows' opacity claims, positioned the same way and travelling the same
    /// route: a `Table` paints its rows' ink, its selection marks and its still
    /// backgrounds itself, and a translucent one of any of those owes a blend.
    var claims: [OpacityRegion] = []

    /// What the rows' view cells registered — their controls' hit regions and
    /// any overlay one raised — positioned the same way, so the container
    /// carries them to where the cells are drawn. See ``_TableRowPayload``.
    var payload = _TableRowPayload()

    var body: Never {
        fatalError("_TableContentView renders via Renderable")
    }

    /// The size the rows draw at, without drawing them: each line a cell
    /// wider for the inset (`TableRowInset`), and none at all for no lines.
    /// The container that holds them measures them every frame, and measured
    /// by rendering, every line was inset — a new string — only to be counted.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard !lines.isEmpty else { return ViewSize.fixed(0, 0) }
        return ViewSize.fixed((lineWidths.max() ?? 0) + 1, lines.count)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The table's leading inset cell, drawn as part of each row
        // (`TableRowInset`): everything here moves one cell along. The inset
        // adds exactly one cell to every line, so the widths are known.
        let widths = lineWidths.map { $0 + 1 }
        let width = widths.max() ?? 0
        var buffer = FrameBuffer(
            lines: lines.map(TableRowInset.inset), width: width,
            uniformWidth: widths.allSatisfy { $0 == width }, lineWidths: widths)
        // A measure pass draws nothing, so a run left on it would describe
        // cells that were never on screen — and keep the clock alive from a
        // pass that produced no frame. A claim on a measure buffer is harmless
        // by comparison, but it is the same statement about cells nobody drew.
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = runs.map(TableRowInset.inset)
        buffer.opacityRegions = claims.map(TableRowInset.inset)
        buffer.hitTestRegions = payload.hitTestRegions.map { $0.shifted(byX: 1, y: 0) }
        buffer.overlays = payload.overlays.map { $0.shifted(byX: 1, y: 0) }
        // The rows' text is inked in the foreground style, so a shadowed one's
        // shadows are cast from the rows' glyphs — not from a focused row's
        // fill (`ShapeStyle.shadow(_:)`).
        guard let paint = context.environment.foregroundStyle else { return buffer }
        return buffer.castingShadows(of: paint, context: context, owner: Self.self, glyphsOnly: true)
    }
}

// MARK: - Table Header View

/// Simple view that renders the header line.
private struct _TableHeaderView: View, Renderable {
    /// The header line, or `nil` when the headers are hidden — which draws no
    /// line at all, so the rows begin under the top border.
    let line: String?

    /// What the header's own colours owe, in the line's columns.
    ///
    /// The header is painted in `foregroundSecondary`, which is a re-SPELLING of the
    /// palette's foreground and carries its alpha — so a theme that fades its text
    /// fades the header, and the claim has to travel with the line rather than being
    /// derived from it later. `_TableContentView`'s twin, added for the same reason
    /// (§33) one commit apart.
    let claims: [OpacityRegion]

    var body: Never {
        fatalError("_TableHeaderView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let line else { return FrameBuffer(lines: []) }
        // The leading inset cell, as the rows draw it (`TableRowInset`).
        var buffer = FrameBuffer(lines: [TableRowInset.inset(line)])
        buffer.opacityRegions += claims.map(TableRowInset.inset)
        return buffer
    }
}

/// A fixed-size stand-in for the table's content lines, used only by the
/// analytic measure path: it reports the size the real lines would occupy
/// without building them, so measuring the table's ``ContainerView`` chrome
/// is O(chrome) instead of O(rows × cells).
private struct _TableSizeStub: View, Renderable, Layoutable {
    let width: Int
    let height: Int

    var body: Never {
        fatalError("_TableSizeStub renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(width, height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Only reached if a parent measures by rendering; blank lines of the
        // reported size keep that path dimension-accurate too.
        FrameBuffer(
            lines: Array(
                repeating: String.spaces(width), count: height))
    }
}

// MARK: - Disabled state

extension _TableCore {
    /// Whether this table is disabled, counting an ancestor's
    /// `.disabled(true)`.
    ///
    /// The same hole `_ListCore` had, for the same reason: `Table`'s concrete
    /// `disabled(_:) -> Self` overload wins overload resolution, so
    /// `Table(…).disabled(true)` sets ``isDisabled`` directly — but
    /// `VStack { Table(…) }.disabled(true)` publishes `\.isEnabled` and
    /// nothing here read it, so the table stayed focusable, selectable and
    /// sortable inside a disabled subtree. See ``_ListCore/isDisabled(in:)``.
    func isDisabled(in context: RenderContext) -> Bool {
        isDisabled || !context.environment.isEnabled
    }
}
