//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumn+StandardOrder.swift
//
//  A column of strings given no comparator sorts as Finder lists names,
//  "item2" before "item10", on every platform, as SwiftUI's does on a Mac.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - The order a column sorts in when it is given none

extension TableColumn {
    /// The comparator a column sorting by the strings at `value` takes when it
    /// is given none: `String.StandardComparator.localizedStandard`, SwiftUI's
    /// default, where Foundation has it, and `LocalizedStandardOrder`, the
    /// same order, where it does not.
    static func standardOrder(_ value: KeyPath<RowValue, String>) -> KeyPathComparator<RowValue> {
        #if canImport(Darwin)
            KeyPathComparator(sendable(value), comparator: String.StandardComparator.localizedStandard)
        #else
            KeyPathComparator(sendable(value), comparator: LocalizedStandardOrder())
        #endif
    }

    /// The comparator a column sorting by the `Comparable` values at `value`
    /// takes: Foundation's `KeyPathComparator(_:)`, which orders strings by
    /// `.localizedStandard` where Foundation has it and by their code points
    /// where it does not, so there a key path to strings takes
    /// `standardOrder(_:)` instead.
    static func standardOrder<V: Comparable>(_ value: KeyPath<RowValue, V>) -> KeyPathComparator<RowValue> {
        #if !canImport(Darwin)
            if let strings = value as? KeyPath<RowValue, String> { return standardOrder(strings) }
        #endif
        return KeyPathComparator(sendable(value))
    }
}

// MARK: - Columns of strings given no comparator

/// TUI's own initializers, beside SwiftUI's
/// `init(_:value:comparator:)`, for the call that gives no comparator.
///
/// SwiftUI's parameter is a `String.StandardComparator` defaulting to
/// `.localizedStandard`, and off Apple platforms Foundation has no such
/// comparator, nor any but `.lexical` (`LocalizedStandardOrder`). So the
/// default cannot be a value of SwiftUI's type that sorts as SwiftUI's does.
/// Instead a call that names no comparator lands here, and a call that names
/// one lands on SwiftUI's, exactly as written: these take no `comparator:`,
/// so they win over the initializer that would default it.
///
/// They constrain no `Sort`, which is what keeps every SwiftUI call shape
/// where it was. In a table that cannot sort, and for a column made outside
/// any table, the unsortable `init(_:value:)` (`Sort == Never`) is the more
/// specialised and wins, as it always did. In a table sorted by
/// `KeyPathComparator`s these do, sorting by `standardOrder(_:)`;
/// in one sorted by any other comparator, the column cannot sort, as the
/// unsortable initializer it was before left it (measured on Swift 6.2.4,
/// 6.3.3 and 6.4.2, `TableColumnStandardOrderTests`).
extension TableColumn where Label == Text {
    /// Creates a column that displays a string property, sorting by it where
    /// the table sorts by key paths, in the order Finder lists names.
    ///
    /// - Parameters:
    ///   - titleKey: The column's localized title key.
    ///   - value: The path to the property associated with the column.
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) where Content == Text {
        let resolved = titleKey.resolvedTitle
        self.init(resolved.plain, value: value)
        liveTitle = titleKey.liveWords
        styledTitle = resolved.styled
    }

    /// Creates a column that displays a string property, with a title
    /// displayed as written, sorting by it where the table sorts by key paths.
    ///
    /// - Parameters:
    ///   - title: The column's title.
    ///   - value: The path to the property associated with the column.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) where Content == Text {
        self.init(
            title: String(title), cell: .string { $0[keyPath: value] }, namesAProperty: true,
            sortComparator: Self.standardOrder(value) as? Sort)
    }

    /// Creates a column that displays a string property, with a text label,
    /// sorting by it where the table sorts by key paths.
    ///
    /// - Parameters:
    ///   - text: The column's label.
    ///   - value: The path to the property associated with the column.
    public init(_ text: Text, value: KeyPath<RowValue, String>) where Content == Text {
        self.init(text.content, value: value)
        liveTitle = text.liveWords
    }
}
