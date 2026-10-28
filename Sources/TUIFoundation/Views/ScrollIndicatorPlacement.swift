//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorPlacement.swift
//
//  Where a scrolling view's indicators go: in room of their own beside the
//  content, or drawn over its edge while the pointer is over the view. The
//  owner asked for both (A-CHURN-2, 2026-10-27), named for what each does,
//  with the hover-only rule for the second: a keyboard user, whose only way
//  to make indicators appear is to focus the view, would otherwise have to
//  leave it to see the content they cover.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// Where a scrolling view's indicators — its scrollbars and its "▲/▼ N more"
/// lines — are drawn. Set with ``View/scrollIndicatorPlacement(_:)``.
///
/// TUI-specific: SwiftUI's indicators are the platform's (on a Mac, overlay
/// scrollers or legacy ones, the user's choice), with no API to pick.
public enum ScrollIndicatorPlacement: Sendable, Equatable, CaseIterable {
    /// In room of their own: a column for the vertical bar, a row for the
    /// horizontal one, a line for each "N more" line under `.visible`, taken
    /// out of the content's room whenever the indicator is shown. The default.
    case besideContent

    /// Over the content's edge — the vertical bar on its last column, the
    /// horizontal one on its last row, the "N more" lines on its first and last
    /// — and only while the pointer is over the view and its content
    /// overflows. The content keeps all of the view's room, and is laid out
    /// once: no indicator's coming or going can change its width.
    ///
    /// Shown for the pointer only, never for the focus: from the keyboard the
    /// focus is the only way into the view, and an indicator that came with it
    /// would cover content the user could see only by leaving.
    case overContent
}

private struct ScrollIndicatorPlacementKey: EnvironmentKey {
    static let defaultValue = ScrollIndicatorPlacement.besideContent
}

extension EnvironmentValues {
    /// Where this subtree's scrolling views draw their indicators — see
    /// ``View/scrollIndicatorPlacement(_:)``.
    public var scrollIndicatorPlacement: ScrollIndicatorPlacement {
        get { self[ScrollIndicatorPlacementKey.self] }
        set { self[ScrollIndicatorPlacementKey.self] = newValue }
    }

    /// Whether this subtree's indicators are drawn over the content, for the
    /// pointer, rather than given room of their own.
    @inlinable
    package var scrollIndicatorsOverlayContent: Bool { scrollIndicatorPlacement == .overContent }
}

extension View {
    /// Sets where the scrolling views in this view draw their indicators.
    ///
    /// ```swift
    /// List(messages) { MessageRow($0) }
    ///     .scrollIndicatorPlacement(.overContent)
    /// ```
    ///
    /// ``ScrollIndicatorPlacement/besideContent`` (the default) gives each
    /// indicator room of its own; ``ScrollIndicatorPlacement/overContent`` draws
    /// them over the content's edge while the pointer is over the view. Whether
    /// an indicator may show at all is still ``View/scrollIndicators(_:axes:)``'s
    /// to say, and which kind is ``View/scrollIndicatorStyle(_:)``'s.
    ///
    /// TUI-specific: SwiftUI's indicators are the platform's.
    ///
    /// - Parameter placement: Where the indicators go.
    /// - Returns: A view whose scrolling views place their indicators so.
    public func scrollIndicatorPlacement(_ placement: ScrollIndicatorPlacement) -> some View {
        environment(\.scrollIndicatorPlacement, placement)
    }
}
