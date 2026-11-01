//  🖥️ TUI — A Terminal UI framework for Swift
//  MultilineTextAlignment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Environment key

/// The two halves of ``EnvironmentValues/multilineTextAlignment``, under one
/// key so that a `Text` reading it does one lookup: what an app states, and
/// what the place the text is drawn in asks for where it states nothing.
private struct MultilineTextAlignmentSetting: Equatable {
    /// The alignment a ``View/multilineTextAlignment(_:)`` above states, or
    /// `nil` where none does.
    var stated: TextAlignment?

    /// The alignment where none is stated: see
    /// ``EnvironmentValues/unstatedMultilineTextAlignment``.
    var unstated: TextAlignment = .leading
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    // Leading by default — a terminal reads from the top-left, and unaligned
    // wrapped text is flush-left; matches SwiftUI's default.
    static let defaultValue = MultilineTextAlignmentSetting()
}

extension EnvironmentValues {
    /// How the lines of a multi-line ``Text`` align relative to one another
    /// within the text block, set by ``View/multilineTextAlignment(_:)``.
    ///
    /// Like any environment value it cascades to every descendant, so a single
    /// application near a subtree's root aligns all the wrapped text beneath it.
    /// Defaults to ``TextAlignment/leading`` — or, where nothing above states
    /// one, to what the place the text is drawn in asks for: a
    /// `LabeledContent`'s value trails.
    public var multilineTextAlignment: TextAlignment {
        get {
            let setting = self[MultilineTextAlignmentKey.self]
            return setting.stated ?? setting.unstated
        }
        set { self[MultilineTextAlignmentKey.self].stated = newValue }
    }

    /// The alignment multi-line text takes where no
    /// ``View/multilineTextAlignment(_:)`` above it states one: leading,
    /// unless the place it is drawn in asks for another. The automatic
    /// `LabeledContentStyle` asks its value to trail, line by line.
    ///
    /// Apart from ``multilineTextAlignment`` because a place's preference
    /// must not override an alignment the app stated above it, as the value's
    /// `.multilineTextAlignment(.trailing)` did (found by the BUGS13 lane's
    /// second review). And because it is the PLACE's: a surface presented from
    /// inside it is drawn somewhere else, and leaves it behind
    /// (``leaveUnstatedTextAlignment()``) — a popover a value's button
    /// presented trailed its lines with the value's.
    package var unstatedMultilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self].unstated }
        set { self[MultilineTextAlignmentKey.self].unstated = newValue }
    }

    /// Leaves behind what the place a presenter is drawn in asked of the text
    /// in it (``unstatedMultilineTextAlignment``), for a presented surface's
    /// content: a sheet, a popover, an alert or a menu is attached inside the
    /// content that presents it, but drawn over the screen. An alignment the
    /// app stated stays, as every environment value the app sets flows into
    /// a presentation.
    ///
    /// Writes only what is set, since nearly every presenter sits in no such
    /// place.
    package mutating func leaveUnstatedTextAlignment() {
        if self[MultilineTextAlignmentKey.self].unstated != .leading {
            self[MultilineTextAlignmentKey.self].unstated = .leading
        }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the alignment of the lines of multi-line ``Text`` within this
    /// subtree.
    ///
    /// Wrapped (or explicitly multi-line) text lays each line out relative to
    /// the block's own width — the width of its longest line: ``TextAlignment/leading``
    /// leaves the lines flush-left (a ragged right edge), ``TextAlignment/center``
    /// centres each line, and ``TextAlignment/trailing`` pushes each flush-right.
    /// A single-line `Text` is unaffected, and the block as a whole is still
    /// positioned by its parent (a `.frame` alignment, a stack). Matches
    /// SwiftUI's `multilineTextAlignment(_:)`.
    ///
    /// ```swift
    /// Text("A longer first line\nand a shorter one")
    ///     .multilineTextAlignment(.center)
    /// ```
    ///
    /// - Parameter alignment: The line-to-line alignment.
    /// - Returns: A view whose descendant text uses `alignment`.
    nonisolated public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}
