//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventDispatcher+ClickFocus.swift
//
//  A click focusing a `.focusable()` view: the dispatcher's half, which runs
//  beside whatever inside the view takes the press, as on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The view a left press on a region focuses, and the manager it is focused
/// through (``MouseEventDispatcher/fileClickFocus(_:manager:for:in:)``).
struct ClickFocusTarget {
    let manager: FocusManager
    let focusID: String
}

extension MouseEventDispatcher {
    /// Files the region `id` as one a left press focuses the view answering
    /// to `focusID` through: `.focusable()`'s, when `.edit` is among its
    /// interactions. Filed every frame, as the region is, and replayed with it
    /// when a memo serves the view, into the manager of the frame that serves
    /// it.
    @MainActor
    package func fileClickFocus(
        _ focusID: String, manager: FocusManager, for id: HitTestRegion.HandlerID, in context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        clickFocusTargets[id] = ClickFocusTarget(manager: manager, focusID: focusID)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.clickFocusKind, channelToken: token) { replay in
                guard let manager = replay.environment.focusManager else { return }
                replay.environment.mouseEventDispatcher?.clickFocusTargets[id] =
                    ClickFocusTarget(manager: manager, focusID: focusID)
            })
    }

    /// The journal kind of a click-to-focus filing.
    static let clickFocusKind = EffectJournal.Kind("clickFocus")

    /// Focuses the `.focusable()` view a left press lands on, before the
    /// press is routed, unless something in front of it owns the click.
    ///
    /// SwiftUI on macOS focuses a focusable view a click lands on AND gives
    /// the click to what is inside it: a tap gesture on the view runs, and the
    /// view takes the focus. The view's own region lies behind its content's
    /// (`FocusableModifier`), so it hears a press only when nothing inside it
    /// took the press; a tap gesture inside it that recognized, or a mouse
    /// handler that claimed the press, would keep the focus from it. So the
    /// focusing is done here, apart from who takes the press.
    ///
    /// What lies in front of the view's region, innermost first, decides:
    ///
    /// - a CONTROL, which takes a plain left press as its own click (a
    ///   `Button` inside the view, a field, a list, a sheet's backdrop or an
    ///   open menu over it), owns the click, and the view is not focused: the
    ///   control does with the focus what it does with any click;
    /// - an attached gesture, a hover observer (`.onHover`, `help(_:)`), the
    ///   app's own `.onMouseEvent` closure, a drag handle that stands aside for
    ///   a click, and the regions that are no targets at all are looked
    ///   through: the view is focused, and they hear the press as they would
    ///   have.
    ///
    /// The view's region still takes a press nothing in front of it took, and
    /// focuses the view there too, which is how a click a drag handle passes
    /// through (``passClickThrough(from:event:)``) focuses it.
    func focusPressedView(_ event: MouseEvent) {
        guard !clickFocusTargets.isEmpty, event.phase == .pressed, event.button == .left else { return }
        for region in matchingRegions(at: event.x, y: event.y, click: true) {
            if let target = clickFocusTargets[region.handlerID] {
                target.manager.focus(id: target.focusID)
                return
            }
            if ownsLeftClick(region.handlerID) { return }
        }
    }

    /// Whether the region `id` names takes a plain left press as a click of
    /// its own, which a `.focusable()` view behind it does not then share
    /// (``focusPressedView(_:)``).
    private func ownsLeftClick(_ id: HitTestRegion.HandlerID) -> Bool {
        if takesNoPlainLeftPress(id) || isApplicationHandler(id) { return false }
        if case .dragSource? = pressRoles[id] { return false }
        return true
    }
}
