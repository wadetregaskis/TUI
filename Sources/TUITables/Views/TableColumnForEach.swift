//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnForEach.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation
import TUIFoundation

// MARK: - TableColumnForEach

/// A structure that computes columns on demand from an underlying collection of
/// identified data.
///
/// Use `TableColumnForEach` to create columns based on a `RandomAccessCollection`
/// of some data type. Either the collection's elements must conform to
/// `Identifiable` or you need to provide an `id` parameter.
///
/// ```swift
/// Table(track.samples) {
///     TableColumn("Timestamp") { sample in
///         Text(sample.timestamp, format: .number)
///     }
///     TableColumnForEach(track.channels) { channel in
///         TableColumn(channel.name) { sample in
///             Text(sample.level(channel: channel.id), format: .number)
///         }
///     }
/// }
/// ```
///
/// This is how a column list is computed from data: a column builder has no
/// `for` loop, in SwiftUI or here.
public struct TableColumnForEach<
    Data: RandomAccessCollection, ID: Hashable, RowValue: Identifiable, Sort: SortComparator,
    Content: TableColumnContent
>: TableColumnContent
where RowValue == Content.TableRowValue, Sort == Content.TableColumnSortComparator {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never

    /// The collection of underlying identified data.
    public var data: Data

    /// A function to create content on demand using the underlying data.
    public var content: (Data.Element) -> Content

    /// The identity of each element: the columns an element builds are that
    /// element's for as long as its identity is.
    let elementID: (Data.Element) -> ID

    /// Creates an instance that uniquely identifies and creates table columns
    /// across updates based on the identity of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The identified data that the columns are computed from.
    ///   - content: The table column builder that creates the columns for
    ///     each element.
    public init(
        _ data: Data,
        @TableColumnBuilder<RowValue, Sort> content: @escaping (Data.Element) -> Content
    ) where ID == Data.Element.ID, Data.Element: Identifiable {
        self.data = data
        self.content = content
        self.elementID = { $0.id }
    }

    /// Creates an instance that uniquely identifies and creates table columns
    /// across updates based on the provided key path to the underlying data's
    /// identifier.
    ///
    /// - Parameters:
    ///   - data: The data that the columns are computed from.
    ///   - id: The key path to the provided data's identifier.
    ///   - content: The table column builder that creates the columns for
    ///     each element.
    public init(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @TableColumnBuilder<RowValue, Sort> content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.content = content
        self.elementID = { $0[keyPath: id] }
    }

    /// Creates an instance that computes table columns over a given constant
    /// range.
    ///
    /// The instance only reads the initial value of the provided data and
    /// doesn't need to identify columns across updates.
    ///
    /// - Parameters:
    ///   - data: A constant range.
    ///   - content: The table column builder that creates the columns for
    ///     each index.
    public init(
        _ data: Range<Int>,
        @TableColumnBuilder<RowValue, Sort> content: @escaping (Int) -> Content
    ) where Data == Range<Int>, ID == Int {
        self.data = data
        self.content = content
        self.elementID = { $0 }
    }

    /// Never called: a column loop hands its columns to the table directly.
    public var tableColumnBody: Never { fatalError("TableColumnForEach renders its columns directly") }
}

extension TableColumnForEach {
    /// Appends the columns built for each element, in order.
    public static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<RowValue>) {
        for element in content.data {
            appendTableColumns(content.content(element), to: &columns, at: "/\(content.elementID(element))")
        }
    }
}
