//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormRowRewrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - Modifiers a form puts back around a row

/// A modifier a ``Form`` can put back around the row it lays out for the view
/// the modifier is written on.
///
/// SwiftUI's form keeps a row in its place whatever is written on it, the
/// modifier applying to the whole row (measured on macOS 15.8 for `.padding`,
/// `.background`, `.help`, `.tag` and `.id` among others, the label staying in
/// the label column: `Tools/SwiftUIProbes/Form rows`). A form takes a row
/// apart — a `LabeledContent`'s label
/// goes in the label column, its content after it — so what was written on the
/// row has to be put back around the row the form lays out. A
/// ``ContentRewrapping`` modifier can be, and the form puts one back as it is.
/// This is the same question asked of ONE row, which more modifiers can
/// answer: a modifier that is not ``ContentRewrapping`` for a reason of its own
/// — padding and an id are moved onto a group's members by ``ModifiedView``'s
/// own resolution, and help and a tag are read-only wrappers — can still go
/// back around a single row.
@MainActor
package protocol FormRowRewrapping {
    /// The type of the view this modifier is written on.
    associatedtype FormRowContent: View

    /// The view this modifier is written on.
    var formRowContent: FormRowContent { get }

    /// A copy of this modifier around `row`, the row the form lays out, in
    /// place of the view it was written on.
    func rewrappingFormRow<V: View>(_ row: V) -> any View

    /// The cells this modifier puts before the row's leading edge, which a
    /// labelled row's label needs ahead of it in the label column: SwiftUI
    /// widens the column by a row's leading padding, rather than moving the
    /// row's label out of it (measured). Zero for every modifier but padding.
    var formRowLeadingInset: Int { get }
}

extension FormRowRewrapping {
    package var formRowLeadingInset: Int { 0 }
}

extension FormRowRewrapping where Self: SingleContentWrapper {
    package var formRowContent: WrappedContent { wrappedContent }
}

/// Padding, an id, a background colour, a shadow: a buffer modifier applies
/// to the row as a whole, as SwiftUI's does.
extension ModifiedView: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        ModifiedView<V, Modifier>(content: row, modifier: modifier)
    }

    package var formRowLeadingInset: Int {
        (modifier as? PaddingModifier).map { max(0, $0.insets.leading) } ?? 0
    }
}
