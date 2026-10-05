//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher+PressRoles.swift
//
//  The regions that take a left press only to act on its CLICK, and the press
//  held for them until it shows whether it is one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Press roles

/// What a region that takes left presses is, when all it does with them is act
/// on the click.
///
/// Most regions that take a left press are controls: a button, a field, a
/// slider, a `.draggable`. A few take it only so that a click on empty space
/// does something — a scroll view's viewport focuses the scroll view, a split
/// view's column activates its section — and a drag means nothing to them.
/// Those file a role, and a press that reaches one is HELD: the dispatcher
/// captures the button itself, and hands the region its press and its release
/// together when the release arrives, if the pointer never left the cell. That
/// is what lets a drag over such a region become something else (the screen
/// selection) without taking the region's click away.
///
/// **The contract a role states:** the region acts on the RELEASE, and its
/// press does nothing anyone would see — it only claims the gesture. Every
/// region that files one does exactly that (`ScrollView`'s viewport,
/// `NavigationSplitView`'s columns). A future region that acted on the press
/// would see it late, at the release, and must not file a role.
enum PressRole {
    /// A pane's background: a scroll view's viewport, a split view's column.
    case background
}

extension MouseEventDispatcher {
    /// Files `role` for the region whose handler `id` names, for the frame.
    ///
    /// Recorded for a value memo, as the handler registration beside it is, so
    /// a served subtree files it again.
    @MainActor
    func filePressRole(_ role: PressRole, for id: HitTestRegion.HandlerID, in context: RenderContext) {
        guard !context.isMeasuring else { return }
        pressRoles[id] = role
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.pressRoleKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.pressRoles[id] = role
            })
    }

    /// The journal kind of a press role's filing.
    static let pressRoleKind = EffectJournal.Kind("pressRole")

    /// Dispatches a left press, holding it for the first region with a role
    /// it reaches.
    ///
    /// The regions are offered the press innermost first, as for every other
    /// event, until one takes it. A region with a role is not offered it: the
    /// press is held for it instead (``HeldPress``), and the region hears its
    /// press and release together at the release.
    func dispatchLeftPress(_ event: MouseEvent, matching: [HitTestRegion]) -> Bool {
        for region in matching {
            if pressRoles[region.handlerID] != nil, let handler = handler(for: region.handlerID) {
                hold(event, for: (handler, region.localOriginX, region.localOriginY))
                return true
            }
            if offer(event, to: region) != .declined { return true }
        }
        return false
    }

    /// Captures the left button for a held press whose click belongs to
    /// `claimer`.
    private func hold(_ press: MouseEvent, for claimer: HeldPress.Claimer) {
        let held = HeldPress(press: press, claimer: claimer)
        pressedHandlers[.left] = PressCapture(
            handler: { [held] event in held.receive(event) }, regionOffsetX: 0, regionOffsetY: 0)
    }
}

// MARK: - The held press

/// A left press held for a region with a ``PressRole`` until it shows whether
/// it is a click.
///
/// It receives the rest of the gesture in content-area coordinates, as the
/// dispatcher's capture for it is anchored at the origin, and hands the
/// claimer its press and release at the release, in the claimer's own
/// coordinates and with the press's click count.
final class HeldPress {
    /// The region the click belongs to: its handler, captured at the press
    /// (the table is rebuilt every frame, and a gesture spans frames), and its
    /// origin.
    typealias Claimer = (handler: (MouseEvent) -> Bool, originX: Int, originY: Int)

    /// The press, as the dispatcher stamped it.
    let press: MouseEvent

    /// Whose click it is.
    let claimer: Claimer

    init(press: MouseEvent, claimer: Claimer) {
        self.press = press
        self.claimer = claimer
    }

    /// One event of the rest of the gesture.
    func receive(_ event: MouseEvent) -> Bool {
        if event.phase == .released { deliverClick(ending: event) }
        return true
    }

    /// The claimer's press, then its release.
    private func deliverClick(ending release: MouseEvent) {
        func local(_ event: MouseEvent) -> MouseEvent {
            MouseEvent(
                button: event.button, phase: event.phase, x: event.x - claimer.originX,
                y: event.y - claimer.originY, shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                clickCount: event.clickCount)
        }
        guard claimer.handler(local(press)) else { return }
        _ = claimer.handler(local(release))
    }
}
