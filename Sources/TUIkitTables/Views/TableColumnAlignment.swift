//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnAlignment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// `Locale.NumberingSystem` is Foundation's.
import Foundation
import TUIkitFoundation

// MARK: - TableColumnAlignment

/// Describes the alignment of the content of a table column.
///
/// The alignment of a column applies to both its header label and the default
/// alignment of its content for each row:
///
/// ```swift
/// TableColumn("Price") { Text($0.price, format: .number) }
///     .alignment(.numeric)
/// ```
public struct TableColumnAlignment: Hashable, Sendable {
    /// What the alignment asks for.
    enum Kind: Hashable, Sendable {
        case automatic, leading, center, trailing
        /// Aligned for numbers in this numbering system, or in the current
        /// locale's when `nil`.
        case numeric(Locale.NumberingSystem?)
    }

    let kind: Kind

    /// The default column alignment. This is equivalent to `leading`.
    public static var automatic: Self { Self(kind: .automatic) }

    /// Leading column alignment.
    public static var leading: Self { Self(kind: .leading) }

    /// Center column alignment.
    public static var center: Self { Self(kind: .center) }

    /// Trailing column alignment.
    public static var trailing: Self { Self(kind: .trailing) }

    /// Column alignment appropriate for numeric content.
    ///
    /// Use it when a column shows mostly numbers, so that the values are easy
    /// to scan and compare. It aligns trailing.
    ///
    /// SwiftUI documents it as following the current locale's numbering
    /// system — trailing for a left-to-right one, leading for a right-to-left
    /// one. Measured on macOS 26.2, every numbering system tried aligned
    /// trailing (see `numeric(_:)`), and so does this.
    public static var numeric: Self { Self(kind: .numeric(nil)) }

    /// Column alignment appropriate for numeric content in the given
    /// numbering system. It aligns trailing: SwiftUI on macOS 26.2 aligned
    /// `latn`, `arab`, `arabext` and `hebr` numbers trailing alike.
    ///
    /// - Parameter numberingSystem: The numbering system the column's numbers
    ///   are written in.
    public static func numeric(_ numberingSystem: Locale.NumberingSystem) -> Self {
        Self(kind: .numeric(numberingSystem))
    }

    /// Where a column so aligned places its header and cells.
    ///
    /// Numeric alignment is trailing. SwiftUI's documentation promises
    /// leading for a right-to-left numbering system, but measured on macOS
    /// 26.2 every system tried — `latn`, `arab`, `arabext`, `hebr` — aligned
    /// trailing, as digits in each are written left to right; and a terminal
    /// lays out left to right regardless (``EnvironmentValues/layoutDirection``).
    var horizontal: HorizontalAlignment {
        switch kind {
        case .automatic, .leading: .leading
        case .center: .center
        case .trailing, .numeric: .trailing
        }
    }
}
