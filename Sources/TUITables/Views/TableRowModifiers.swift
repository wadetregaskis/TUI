//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowModifiers.swift
//
//  Modifiers on table rows: what a modifier records about the rows of the
//  content it wraps, the `ModifiedContent` that carries one, and the
//  modifiers themselves.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUILists
import TUIView

// MARK: - What a row carries

/// What the row modifiers around a row said about it: the parts of a row that
/// are not its value.
struct _TableRowTraits {
    /// Whether the row refuses to be selected, when a modifier said;
    /// `.selectionDisabled(_:)` nearest the row wins.
    var selectionDisabled: Bool?

    /// What to tell when the pointer comes onto the row and leaves it, from
    /// every `.onHover(perform:)` around it, nearest first.
    var hoverActions: [(Bool) -> Void] = []

    /// What a drag of the row carries, when a `.draggable(_:)` or
    /// `.itemProvider(_:)` said; the one nearest the row wins. A payload that
    /// is `nil` starts no drag.
    var dragPayload: (() -> Any?)?

    /// The drops the row takes onto itself, from every
    /// `.dropDestination(for:action:)` around it, nearest first.
    var dropActions: [_TableRowDrop] = []

    /// The row's own menu, built when it opens, from a
    /// `.contextMenu(menuItems:)`; the one nearest the row wins.
    var contextMenu: (() -> AnyView)?

    /// Whether no modifier said anything.
    var isEmpty: Bool {
        selectionDisabled == nil && hoverActions.isEmpty && dragPayload == nil && dropActions.isEmpty
            && contextMenu == nil
    }
}

// MARK: - The modifier protocol

/// A modifier that you apply to table row content.
///
/// You don't conform to this protocol: the row modifiers —
/// `TableRowContent.selectionDisabled(_:)` and its siblings — return
/// `ModifiedContent` values whose modifier is one of TUI's own.
@MainActor
public protocol _TableRowContentModifier {}

/// A row modifier this framework defines, which records what it says in the
/// traits of every row its content declares.
@MainActor
protocol _TableRowTraitModifier: _TableRowContentModifier {
    /// Records this modifier in one row's traits.
    func apply(to traits: inout _TableRowTraits)
}

/// A row modifier this framework defines that says something of its
/// content's rows TOGETHER — a loop's insertion between them — rather than
/// of each row.
@MainActor
protocol _TableRowListModifier: _TableRowContentModifier {
    /// Records this modifier on the rows its content declares.
    func apply<Value>(to rows: inout _TableRowList<Value>)
}

// MARK: - ModifiedContent of rows

extension ModifiedContent: _TableRowValued
where Content: TableRowContent, Modifier: _TableRowContentModifier {
    public typealias TableRowValue = Content.TableRowValue
}

extension ModifiedContent: TableRowContent
where Content: TableRowContent, Modifier: _TableRowContentModifier {
    public typealias TableRowBody = Never

    /// Never called: modified rows hand themselves to the table directly.
    public var tableRowBody: Never { fatalError("ModifiedContent renders its rows directly") }
}

extension ModifiedContent where Content: TableRowContent, Modifier: _TableRowContentModifier {
    /// Appends the modified rows, with the modifier applied to them.
    @MainActor
    public static func _appendRows(_ rowContent: Self, to rows: inout _TableRowList<Content.TableRowValue>) {
        let modifier = rowContent.modifier
        var own = tableRows(of: rowContent.content)
        if let modifier = modifier as? any _TableRowTraitModifier {
            own.modifyTraits { modifier.apply(to: &$0) }
        }
        if let modifier = modifier as? any _TableRowListModifier {
            modifier.apply(to: &own)
        }
        rows.append(contentsOf: own)
    }
}

extension ModifiedContent: DynamicTableRowContent
where Content: DynamicTableRowContent, Modifier: _TableRowContentModifier {
    /// The type of the underlying collection of data.
    public typealias Data = Content.Data

    /// The collection of underlying data: the modified content's.
    public var data: Content.Data { content.data }
}

// MARK: - selectionDisabled

/// What `.selectionDisabled(_:)` records on a row.
struct _SelectionDisabledTableRowModifier: _TableRowTraitModifier {
    let isDisabled: Bool

    func apply(to traits: inout _TableRowTraits) {
        // The modifier nearest the row has already spoken.
        if traits.selectionDisabled == nil { traits.selectionDisabled = isDisabled }
    }
}

extension TableRowContent {
    /// Adds a condition that controls whether users can select this row.
    ///
    /// A row whose selection is disabled cannot become the table's selection:
    /// a click or Space on it does nothing, Up and Down step over it, and it
    /// draws faint — as a `List` row under `.selectionDisabled(_:)` does.
    ///
    /// ```swift
    /// Table(of: Item.self, selection: $selection) {
    ///     TableColumn("Name", value: \.name)
    /// } rows: {
    ///     ForEach(items) { item in
    ///         TableRow(item)
    ///             .selectionDisabled(item.isLocked)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter isDisabled: Whether selection is disabled. Applied to rows
    ///   that hold `.selectionDisabled(_:)` themselves, the one nearest the
    ///   row wins.
    public func selectionDisabled(_ isDisabled: Bool = true) -> some TableRowContent<TableRowValue> {
        ModifiedContent(content: self, modifier: _SelectionDisabledTableRowModifier(isDisabled: isDisabled))
    }
}

// MARK: - onHover

/// What `.onHover(perform:)` records on a row.
struct _HoverTableRowModifier: _TableRowTraitModifier {
    let action: (Bool) -> Void

    func apply(to traits: inout _TableRowTraits) {
        traits.hoverActions.append(action)
    }
}

extension TableRowContent {
    /// Adds an action to perform when the pointer enters or exits this row.
    ///
    /// ```swift
    /// ForEach(items) { item in
    ///     TableRow(item)
    ///         .onHover { hovering in hovered = hovering ? item.id : nil }
    /// }
    /// ```
    ///
    /// The action is called with `true` when the pointer comes onto any line
    /// of the row and `false` when it leaves, as `View.onHover(perform:)` is
    /// for a view; it asks the terminal for motion reports while the row is
    /// on screen. A hover action on a view around the whole table takes the
    /// pointer from its rows, as an outer `.onHover` does from the views
    /// inside it.
    ///
    /// - Parameter action: The action to perform: `true` on entering the row,
    ///   `false` on leaving it.
    public func onHover(perform action: @escaping (Bool) -> Void) -> some TableRowContent<TableRowValue> {
        ModifiedContent(content: self, modifier: _HoverTableRowModifier(action: action))
    }
}
