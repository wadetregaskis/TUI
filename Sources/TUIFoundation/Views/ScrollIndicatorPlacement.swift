//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorPlacement.swift
//
//  Where a scrolling view's indicators go: in room of their own beside the
//  content, or drawn over its edge while the pointer is over the view — and,
//  for that second, beside the content again while the view holds the focus.
//  The owner asked for both (A-CHURN-2, 2026-10-27), named for what each does,
//  and ruled on the focus (2026-10-29): a keyboard user, whose only way to
//  make indicators appear is to focus the view, sees where they are and what
//  is hidden, and nothing they need to read is covered. The second is the
//  default (SCROLLBAR-PLACEMENT, 2026-11-09), except for a scroller that can
//  never hold the focus — a tall menu's — which keeps its indicators beside
//  its content: a keyboard user has no other way to see them. The focus counts
//  wherever it is inside the view (2026-11-10), so moving it among the view's
//  controls, or into a scroll view inside it, never lays the content out again.
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
    /// out of the content's room whenever the indicator is shown.
    case besideContent

    /// Over the content's edge — the vertical bar on its last column, the
    /// horizontal one on its last row, the "N more" lines on its first and last
    /// — while the pointer is over the view; and while the focus is in the
    /// view — on the view, or on anything inside it — as ``besideContent``
    /// places them, in room of their own. Neither, and none is drawn. Either way only where the content overflows, as the
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
    ///
    /// The focus on a control inside the view, or on a scrolling view inside
    /// it, counts as the view's own: the keyboard user is still in there, and
    /// moving among the view's controls — by Tab or, with the focus following
    /// the pointer, by the mouse — leaves its content where it is. Only coming
    /// in and going out lay it out again, once each, rather than every step
    /// that passes through the view itself (the owner's report of nested
    /// scroll views jumping, 2026-11-10).
    ///
    /// A scroller that can never hold the focus — the one a menu too tall for
    /// its space scrolls its rows in, whose rows are the focus stops — places
    /// them as ``besideContent`` does, always: the keyboard has no way to make
    /// them appear over the content, and a keyboard user walking the rows
    /// still sees what is hidden.
    ///
    /// The default (the owner's ruling, 2026-11-09: "default to
    /// overlay-on-hover", and "keep scrollbars visible (beside the content) for
    /// scrollers that can't hold the focus").
    case overContent
}

private struct ScrollIndicatorPlacementKey: EnvironmentKey {
    static let defaultValue = ScrollIndicatorPlacement.overContent
}

private struct ScrollIndicatorsBesideForFocusKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ScrollIndicatorsBesideForNoFocusStopKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Where this subtree's scrolling views draw their indicators —
    /// ``ScrollIndicatorPlacement/overContent`` unless set; see
    /// ``View/scrollIndicatorPlacement(_:)``.
    public var scrollIndicatorPlacement: ScrollIndicatorPlacement {
        get { self[ScrollIndicatorPlacementKey.self] }
        set { self[ScrollIndicatorPlacementKey.self] = newValue }
    }

    /// Whether this view's indicators are drawn over the content, for the
    /// pointer, rather than given room of their own: placed
    /// ``ScrollIndicatorPlacement/overContent``, not holding the focus, and
    /// able to hold it
    /// (``RenderContext/placingScrollIndicators(explicitFocusID:focusIDIndex:canHoldFocus:)``).
    /// The question every part of a scrolling view's layout and drawing asks.
    @inlinable
    package var scrollIndicatorsOverlayContent: Bool {
        scrollIndicatorPlacement == .overContent && !scrollIndicatorsBesideForFocus
            && !scrollIndicatorsBesideForNoFocusStop
    }

    /// Whether this view watches the pointer for its indicators: placed
    /// ``ScrollIndicatorPlacement/overContent``, whether or not it holds the
    /// focus — so where the pointer is is known the moment the focus leaves —
    /// unless it can never hold the focus, when its indicators are beside its
    /// content whatever the pointer does.
    @inlinable
    package var scrollIndicatorsFollowPointer: Bool {
        scrollIndicatorPlacement == .overContent && !scrollIndicatorsBesideForNoFocusStop
    }

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

    /// Whether a scrolling view placed ``ScrollIndicatorPlacement/overContent``
    /// can never hold the focus, and so draws its indicators beside its
    /// content always: a framework scroller that is no focus stop, a tall
    /// menu's. Set and put back as ``scrollIndicatorsBesideForFocus`` is.
    @usableFromInline package var scrollIndicatorsBesideForNoFocusStop: Bool {
        get { self[ScrollIndicatorsBesideForNoFocusStopKey.self] }
        set { self[ScrollIndicatorsBesideForNoFocusStopKey.self] = newValue }
    }

    /// Gives a scrolling view's content the placement stated above the view,
    /// without the view's own focus in it — see ``scrollIndicatorsBesideForFocus``
    /// and ``scrollIndicatorsBesideForNoFocusStop``. Written only when set,
    /// which is only under a focused view or one that can hold no focus.
    package mutating func restoreStatedScrollIndicatorPlacement() {
        if scrollIndicatorsBesideForFocus { scrollIndicatorsBesideForFocus = false }
        if scrollIndicatorsBesideForNoFocusStop { scrollIndicatorsBesideForNoFocusStop = false }
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
    /// anything — a view never rendered has never been focused. The focus held
    /// anywhere inside the view counts as its own
    /// (``focusIsWithin(_:focusManager:)``).
    ///
    /// A view that can never hold the focus has its indicators beside its
    /// content always (``EnvironmentValues/scrollIndicatorsBesideForNoFocusStop``):
    /// the owner's ruling of 2026-11-09, so that a keyboard user sees them.
    ///
    /// Every other placement gets the context back as it is, after one read,
    /// so `.besideContent` pays nothing more; an `.overContent` view (the
    /// default) pays a state lookup, and writes the environment only when its
    /// focus changed from what it inherited.
    ///
    /// - Parameters:
    ///   - explicitFocusID: The view's `.focusID(_:)`, if it has one.
    ///   - focusIDIndex: The `StateStorage` index the view persists its focus
    ///     id at.
    ///   - canHoldFocus: Whether the view can hold the focus at all: `false`
    ///     for a framework scroller that is no focus stop.
    package func placingScrollIndicators(
        explicitFocusID: String?, focusIDIndex: Int, canHoldFocus: Bool = true
    ) -> RenderContext {
        guard environment.scrollIndicatorPlacement == .overContent else { return self }
        guard canHoldFocus else { return placingScrollIndicatorsForNoFocusStop() }
        var holdsFocus = false
        if let focusManager = environment.focusManager {
            let key = StateStorage.StateKey(identity: identity, propertyIndex: focusIDIndex)
            let persisted: StateBox<String>? = explicitFocusID == nil ? stateStorage?.existingStorage(for: key) : nil
            holdsFocus = focusIsWithin(explicitFocusID ?? persisted?.value, focusManager: focusManager)
            holdIndicatorPlacement(holdsFocus, focusManager: focusManager)
        }
        guard holdsFocus != environment.scrollIndicatorsBesideForFocus else { return self }
        var placed = self
        placed.environment.scrollIndicatorsBesideForFocus = holdsFocus
        return placed
    }
}

/// Whether a scrolling view placed ``ScrollIndicatorPlacement/overContent``
/// last found the focus inside it, decided from the live focus by its last
/// render that was not a backdrop's, and read by the render of it as a
/// backdrop (``RenderContext/focusIsWithin(_:focusManager:)``).
///
/// A class in a box, written through its property, so remembering the answer
/// on every render is no state write: it asks for no frame and drops no
/// cached drawing, as a `StateBox` value write would.
package final class HeldIndicatorPlacement {
    var besideForFocus = false
}

extension RenderContext {
    /// Whether the focus is in the scrolling view this context renders: on the
    /// view itself (`focusID`, `nil` for a view never rendered), or on a
    /// control drawn anywhere below it — a row's button, a field, a scroll
    /// view inside it (`FocusManager.focusedIdentity`, where the focused
    /// control last registered).
    ///
    /// What places the indicators beside the content under
    /// ``ScrollIndicatorPlacement/overContent``. Asked once a measure and once
    /// a render of a view placed so; the identity walk climbs only the focused
    /// control's chain, and only when the view itself does not hold the focus.
    ///
    /// Drawn as a backdrop, under a sheet, an alert or a popover, the page has
    /// a throwaway focus manager that holds no focus
    /// (`RenderContext.isolatedForBackground()`), and asked of it the answer
    /// would always be "no": the page would be laid out again for the bar over
    /// its content as the modal came up, and again beside it as it went. So a
    /// backdrop is answered with what the view last decided from the live
    /// focus, which its renders keep (``HeldIndicatorPlacement``): the page
    /// under a modal is laid out as it was before the modal came.
    ///
    /// So is a frame on which the focus has not landed yet when this view
    /// reads it: nothing holds it, or the control that holds it has not been
    /// drawn since the focus manager last swept its record of where controls
    /// are (`FocusManager.focusedIdentity` is `nil`). The second is the frame
    /// a modal is dismissed on: the page's control gets the focus back before
    /// the page is drawn, but it was last drawn under the backdrop's manager,
    /// so the live one no longer knows where it is until it registers again,
    /// after this view has read it. Until the focus lands, the view stays as
    /// it was.
    package func focusIsWithin(_ focusID: String?, focusManager: FocusManager) -> Bool {
        if focusManager.isBackdrop { return heldBesideForFocus }
        if let focusID, focusManager.isFocused(id: focusID) { return true }
        guard let focused = focusManager.focusedIdentity else { return heldBesideForFocus }
        return identity.isAncestor(of: focused)
    }

    /// What this view last decided from the live focus
    /// (``HeldIndicatorPlacement``), `false` before it has decided.
    private var heldBesideForFocus: Bool {
        let held: StateBox<HeldIndicatorPlacement>? = stateStorage?.existingStorage(for: heldPlacementKey)
        return held?.value.besideForFocus ?? false
    }

    /// Keeps `besideForFocus` as what this view decided from the live focus,
    /// for the renders that cannot read it (``focusIsWithin(_:focusManager:)``).
    /// Not in a measure, and not under a backdrop's throwaway focus manager.
    func holdIndicatorPlacement(_ besideForFocus: Bool, focusManager: FocusManager) {
        guard !focusManager.isBackdrop, !isMeasuring, let stateStorage else { return }
        let held: StateBox<HeldIndicatorPlacement> = stateStorage.storage(
            for: heldPlacementKey, default: HeldIndicatorPlacement())
        let placement = held.value
        placement.besideForFocus = besideForFocus
    }

    /// Where this view keeps ``HeldIndicatorPlacement``.
    private var heldPlacementKey: StateStorage.StateKey {
        StateStorage.StateKey(identity: identity, propertyIndex: StateStorage.StateKey.heldIndicatorPlacementIndex)
    }

    /// This context as a scrolling view that can never hold the focus reads
    /// it: under ``ScrollIndicatorPlacement/overContent``, its indicators
    /// beside its content
    /// (``EnvironmentValues/scrollIndicatorsBesideForNoFocusStop``). What
    /// ``placingScrollIndicators(explicitFocusID:focusIDIndex:canHoldFocus:)``
    /// gives such a view, for a caller that sizes one before it draws: a tall
    /// menu's rows, laid out for the scroller's bar.
    package func placingScrollIndicatorsForNoFocusStop() -> RenderContext {
        guard environment.scrollIndicatorPlacement == .overContent,
            !environment.scrollIndicatorsBesideForNoFocusStop
        else { return self }
        var placed = self
        placed.environment.scrollIndicatorsBesideForNoFocusStop = true
        return placed
    }

    /// Asks for this frame to be walked again when the focus the view holds
    /// (anywhere inside it, ``focusIsWithin(_:focusManager:)``) is not the one
    /// its indicators were placed for: it changed during the view's own
    /// render, after ``placingScrollIndicators(explicitFocusID:focusIDIndex:canHoldFocus:)``
    /// read it.
    ///
    /// That is the first focus stop on a page, which takes the focus as it
    /// registers, on its first frame (`FocusManager.register(_:inSection:)`),
    /// and a pending focus resolving as its target registers. Before the
    /// render the view has no focus id to ask about, and the stops before it
    /// in the walk may still take the focus first, so nothing can tell
    /// earlier. The frame would be written with the content at the whole
    /// width and no bar, and the next laid out beside the bar: a jump.
    /// Instead the view's drawing is invalidated as an effect of the walk
    /// (`EffectStage`), which `FrameSettling` walks again for before the
    /// frame is written, and this time the placement reads the focus held.
    /// Once a frame at most, on the frame the focus arrives in a render; a
    /// render outside a frame's walk (no drawing open) invalidates at once,
    /// and the next frame is laid out for the focus.
    ///
    /// - Parameter focusID: The id the view answers to in the focus ring.
    @MainActor
    package func settleScrollIndicatorPlacement(focusID: String) {
        guard !isMeasuring, environment.scrollIndicatorPlacement == .overContent,
            let focusManager = environment.focusManager
        else { return }
        // Kept as learnt here too: a frame whose focus arrived during its walk
        // is laid out for it when walked again, even where the focus is again
        // unsettled when the next walk reads it.
        let holdsFocus = focusIsWithin(focusID, focusManager: focusManager)
        holdIndicatorPlacement(holdsFocus, focusManager: focusManager)
        guard holdsFocus != environment.scrollIndicatorsBesideForFocus,
            let stage = stateStorage?.effectStage, let cache = renderCache
        else { return }
        let identity = self.identity
        stage.perform(as: .change) { cache.invalidateRender(for: identity) }
    }
}

extension View {
    /// Sets where the scrolling views in this view draw their indicators.
    ///
    /// ```swift
    /// List(messages) { MessageRow($0) }
    ///     .scrollIndicatorPlacement(.besideContent)
    /// ```
    ///
    /// ``ScrollIndicatorPlacement/overContent`` (the default) draws the
    /// indicators over the content's edge while the pointer is over the view,
    /// and beside it while the view holds the focus — and always beside it for
    /// a scroller that can never hold the focus, as a tall menu's;
    /// ``ScrollIndicatorPlacement/besideContent`` gives each indicator room of
    /// its own whenever it shows. Whether an indicator may show
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
