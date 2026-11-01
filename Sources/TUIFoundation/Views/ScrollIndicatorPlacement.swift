//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorPlacement.swift
//
//  Where a scrolling view's indicators go: in room of their own beside the
//  content, or drawn over its edge while the pointer is over the view — and,
//  for that second, beside the content again while the view holds the focus.
//  The owner asked for both (A-CHURN-2, 2026-10-27), named for what each does,
//  and ruled on the focus (2026-10-29): a keyboard user, whose only way to
//  make indicators appear is to focus the view, sees where they are and what
//  is hidden, and nothing they need to read is covered.
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
    /// — while the pointer is over the view; and while the view holds the
    /// focus, as ``besideContent`` places them, in room of their own. Neither,
    /// and none is drawn. Either way only where the content overflows, as the
    /// visibility says.
    ///
    /// For the pointer the content keeps all of the view's room, and is laid
    /// out once: no indicator's coming or going can change its width. The
    /// focus moves them beside it — the content laid out again, narrower (and,
    /// under `.visible` "N more" lines, shorter) — because from the keyboard
    /// the focus is the only way into the view: that is when a keyboard user
    /// needs to see where they are and what is hidden, and an indicator drawn
    /// over the content then would cover what they could read only by leaving.
    /// Losing the focus gives the content its whole room back.
    case overContent
}

private struct ScrollIndicatorPlacementKey: EnvironmentKey {
    static let defaultValue = ScrollIndicatorPlacement.besideContent
}

private struct ScrollIndicatorsBesideForFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Where this subtree's scrolling views draw their indicators — see
    /// ``View/scrollIndicatorPlacement(_:)``.
    public var scrollIndicatorPlacement: ScrollIndicatorPlacement {
        get { self[ScrollIndicatorPlacementKey.self] }
        set { self[ScrollIndicatorPlacementKey.self] = newValue }
    }

    /// Whether this view's indicators are drawn over the content, for the
    /// pointer, rather than given room of their own: placed
    /// ``ScrollIndicatorPlacement/overContent`` and not holding the focus
    /// (``RenderContext/placingScrollIndicators(explicitFocusID:focusIDIndex:canHoldFocus:)``).
    /// The question every part of a scrolling view's layout and drawing asks.
    @inlinable
    package var scrollIndicatorsOverlayContent: Bool {
        scrollIndicatorPlacement == .overContent && !scrollIndicatorsBesideForFocus
    }

    /// Whether this view watches the pointer for its indicators: placed
    /// ``ScrollIndicatorPlacement/overContent``, whether or not it holds the
    /// focus — so where the pointer is is known the moment the focus leaves.
    @inlinable
    package var scrollIndicatorsFollowPointer: Bool { scrollIndicatorPlacement == .overContent }

    /// Whether a scrolling view placed ``ScrollIndicatorPlacement/overContent``
    /// holds the focus, and so draws its indicators beside its content. Set
    /// for the view's own reads by
    /// ``RenderContext/placingScrollIndicators(explicitFocusID:focusIDIndex:canHoldFocus:)``,
    /// and put back for its content by ``restoreStatedScrollIndicatorPlacement()``:
    /// it is the view's, and a scrolling view in the content has a focus of its
    /// own.
    @usableFromInline package var scrollIndicatorsBesideForFocus: Bool {
        get { self[ScrollIndicatorsBesideForFocusKey.self] }
        set { self[ScrollIndicatorsBesideForFocusKey.self] = newValue }
    }

    /// Gives a scrolling view's content the placement stated above the view,
    /// without the view's own focus in it — see ``scrollIndicatorsBesideForFocus``.
    /// Written only when set, which is only under a focused view.
    package mutating func restoreStatedScrollIndicatorPlacement() {
        if scrollIndicatorsBesideForFocus { scrollIndicatorsBesideForFocus = false }
    }
}

extension RenderContext {
    /// This context as a scrolling view reads it for its own indicators: under
    /// ``ScrollIndicatorPlacement/overContent``, with
    /// ``EnvironmentValues/scrollIndicatorsBesideForFocus`` saying whether the
    /// view holds the focus, and so whether its layout gives the indicators
    /// room of their own. Asked at the top of the view's measure and render
    /// alike, before anything is laid out, so the two agree, and the frame the
    /// focus arrives on (or leaves on) is laid out for it: no frame is drawn
    /// for the placement before.
    ///
    /// The focus is read from the focus manager directly, in a measure too,
    /// where `FocusRegistration.isFocused(context:focusID:)` answers `false`;
    /// and it is the true focus, not the drawn one (`indicatesFocus(_:)`):
    /// where the indicators go is layout, not a focus effect. The id is the one
    /// the view's last render persisted, read without claiming or storing
    /// anything — a view never rendered has never been focused.
    ///
    /// Every other placement gets the context back as it is, after one read,
    /// so the default pays nothing more; an `.overContent` view pays a state
    /// lookup, and writes the environment only when its focus changed from
    /// what it inherited.
    ///
    /// - Parameters:
    ///   - explicitFocusID: The view's `.focusID(_:)`, if it has one.
    ///   - focusIDIndex: The `StateStorage` index the view persists its focus
    ///     id at.
    ///   - canHoldFocus: Whether the view can hold the focus at all: `false`
    ///     for a framework scroller, which is no focus stop.
    package func placingScrollIndicators(
        explicitFocusID: String?, focusIDIndex: Int, canHoldFocus: Bool = true
    ) -> RenderContext {
        guard environment.scrollIndicatorPlacement == .overContent else { return self }
        var holdsFocus = false
        if canHoldFocus, let focusManager = environment.focusManager {
            let key = StateStorage.StateKey(identity: identity, propertyIndex: focusIDIndex)
            let persisted: StateBox<String>? = explicitFocusID == nil ? stateStorage?.existingStorage(for: key) : nil
            if let focusID = explicitFocusID ?? persisted?.value { holdsFocus = focusManager.isFocused(id: focusID) }
        }
        guard holdsFocus != environment.scrollIndicatorsBesideForFocus else { return self }
        var placed = self
        placed.environment.scrollIndicatorsBesideForFocus = holdsFocus
        return placed
    }
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
    /// them over the content's edge while the pointer is over the view, and
    /// beside it while the view holds the focus. Whether an indicator may show
    /// at all is still ``View/scrollIndicators(_:axes:)``'s to say, and which
    /// kind is ``View/scrollIndicatorStyle(_:)``'s.
    ///
    /// TUI-specific: SwiftUI's indicators are the platform's.
    ///
    /// - Parameter placement: Where the indicators go.
    /// - Returns: A view whose scrolling views place their indicators so.
    nonisolated public func scrollIndicatorPlacement(_ placement: ScrollIndicatorPlacement) -> some View {
        environment(\.scrollIndicatorPlacement, placement)
    }
}
