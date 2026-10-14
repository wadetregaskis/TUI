//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabeledContentPlacement.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where a `LabeledContent` puts its content beside its label, by what it is a
/// row of — as SwiftUI's automatic style decides (measured on macOS 15.8,
/// `PROBES-1014/labeledcontent`).
///
/// Here rather than beside `LabeledContent`, because a `List` says it is one
/// and the lists are not built on the forms.
package enum LabeledContentPlacement: Sendable, Equatable {
    /// On its own: the row hugs, with the content right after the label.
    case standalone
    /// A list's row: the label leading, a fixed value at the trailing edge, a
    /// field or a slider filling the rest after the label.
    case listRow
}

private struct LabeledContentPlacementKey: EnvironmentKey {
    static let defaultValue = LabeledContentPlacement.standalone
}

extension EnvironmentValues {
    /// Where a `LabeledContent` here puts its content — see
    /// ``LabeledContentPlacement``.
    package var labeledContentPlacement: LabeledContentPlacement {
        get { self[LabeledContentPlacementKey.self] }
        set { self[LabeledContentPlacementKey.self] = newValue }
    }
}
