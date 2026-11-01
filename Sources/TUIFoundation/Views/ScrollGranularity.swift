//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollGranularity.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollGranularity

/// How finely a scrollable steps: TUI's one granularity of its own, beside
/// SwiftUI's scroll target behaviours. (TUI-specific: SwiftUI scrolls by
/// points, so the question doesn't arise there.)
///
/// - ``line``: the viewport moves one terminal *line* at a time — a tall
///   ``List`` or ``Table`` row scrolls into view gradually, and can be
///   partially clipped at the top of the viewport, exactly like a GUI list
///   mid-scroll. This is what every scrollable does with no scroll target
///   behaviour.
///
/// Scrolling by whole rows — the classic TUI behaviour, where the row a step
/// lands on is fully shown at the top — is SwiftUI's
/// `.scrollTargetBehavior(.viewAligned)`, and paging is `.paging`; see
/// ``ScrollTargetBehavior``. `.scrollGranularity(.line)` takes a subtree back
/// to line steps from either, which SwiftUI has no spelling for.
public enum ScrollGranularity: Sendable, Equatable {
    /// Scroll by terminal lines; a tall top row may be partially clipped.
    case line
}

// MARK: - View Modifier

extension View {
    /// Scrolls the ``List``, ``Table`` and ``ScrollView`` content in this
    /// subtree a terminal line at a time — TUI's default, and a way back to
    /// it beneath a ``View/scrollTargetBehavior(_:)`` stated further out.
    ///
    /// Under line steps a tall row scrolls into view gradually and may be
    /// partially clipped at the top edge. For whole-row steps, use
    /// `.scrollTargetBehavior(.viewAligned)`. Either way the viewport fills
    /// exactly, the row at the bottom edge drawn as far as it fits.
    nonisolated public func scrollGranularity(_ granularity: ScrollGranularity) -> some View {
        environment(\.scrollTargetBehavior, _FreeScrollTargetBehavior())
    }
}
