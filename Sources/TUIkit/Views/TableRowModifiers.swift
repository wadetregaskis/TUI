//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowModifiers.swift
//
//  Modifiers on table rows: what a modifier records about the rows of the
//  content it wraps, the `ModifiedContent` that carries one, and the
//  modifiers themselves.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - What a row carries

/// What the row modifiers around a row said about it: the parts of a row that
/// are not its value.
struct _TableRowTraits {
    /// Whether the row refuses to be selected, when a modifier said;
    /// `.selectionDisabled(_:)` nearest the row wins.
    var selectionDisabled: Bool?

    /// Whether no modifier said anything.
    var isEmpty: Bool { selectionDisabled == nil }
}

// MARK: - The modifier protocol

/// A modifier that you apply to table row content.
///
/// You don't conform to this protocol: the row modifiers —
/// `TableRowContent.selectionDisabled(_:)` and its siblings — return
/// `ModifiedContent` values whose modifier is one of TUIkit's own.
@MainActor
public protocol _TableRowContentModifier {}

/// A row modifier this framework defines, which records what it says in the
/// traits of every row its content declares.
@MainActor
protocol _TableRowTraitModifier: _TableRowContentModifier {
    /// Records this modifier in one row's traits.
    func apply(to traits: inout _TableRowTraits)
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

extension ModifiedContent: _TableRowPrimitive
where Content: TableRowContent, Modifier: _TableRowContentModifier {
    typealias PrimitiveRowValue = Content.TableRowValue

    func appendRows(to rows: inout _TableRowList<Content.TableRowValue>) {
        var own = tableRows(of: content)
        if let modifier = modifier as? any _TableRowTraitModifier {
            own.modifyTraits { modifier.apply(to: &$0) }
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
