//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationOverlay.swift
//
//  The toasts a NotificationService holds, drawn as layers over the content
//  area: what the window chrome draws for every scene, with no step of the
//  app's own.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Notification Overlay

/// Draws the active notifications of the environment's ``NotificationService``
/// as overlay layers over an area of the screen.
///
/// The window chrome (`_WindowChromeHost`) calls this for every scene, after
/// the content and before the bars, with the content area's size, so every
/// app shows its toasts with nothing to add: they float over the page, over
/// any sheet or alert in it (``OverlayLevel/notification`` is the topmost
/// level), and leave the bars uncovered. The package-level
/// `notificationHost()` modifier draws the same over a single view, for a
/// test with no scene.
///
/// A toast is a layer, never baked into the page's lines: a presentation
/// composited at the root after the lines would otherwise dim and cover it.
enum NotificationOverlay {
    /// The layers that draw the service's active notifications over an area
    /// `areaWidth` by `areaHeight` cells, its top-left corner the origin of
    /// the buffer they are added to; none when there is no service, or
    /// nothing to show. Asks for the frames a fade needs.
    @MainActor
    static func layers(context: RenderContext, areaWidth: Int, areaHeight: Int) -> [OverlayLayer] {
        // Without an app there is no service, so there is nothing to show.
        guard !context.isMeasuring, let service = context.environment.notificationService else { return [] }
        // This app draws the service, so a post asks it for a frame.
        service.noteDisplayed(by: context.renderCache?.link)
        // The service is a process-wide object that no memo keys on, and a post
        // writes nothing the render cache sees. So the read DECLARES itself
        // (`recordUnkeyedRead`), as a view sizing itself to the scroll viewport
        // does, and a memo above the drawing declines to keep a buffer drawn
        // with no toast in it: it served that buffer after `post`, and the
        // toast never appeared. Declared whether or not there are toasts,
        // because "none" is the answer a post invalidates. The chrome draws
        // them at the root, where there is no memo above to decline.
        context.environment.volatileReadTracker?.recordUnkeyedRead()
        let activeEntries = service.activeEntries()
        guard !activeEntries.isEmpty, areaWidth > 0, areaHeight > 0 else { return [] }

        if let lifecycle = context.environment.lifecycle {
            NotificationAnimation.start(service: service, lifecycle: lifecycle, frames: context.renderCache?.link)
        }

        // The frame's stamp, so every toast in one frame fades by one instant and a
        // re-walk of the frame draws the same picture. A one-off render has no stamp —
        // `nowNanos` is 0 outside the run loop — and reads the service's clock instead,
        // which is what the toast was posted on.
        let frame = context.environment.animationFrame
        let now = frame.canAnimate ? UInt64(bitPattern: frame.nowNanos) : service.nowNanos()
        let width = min(service.width, max(1, areaWidth - 2))
        let toasts = ToastContext(service: service, context: context, now: now, entries: activeEntries)
        // A layer per placement, each its own stack: the channels.
        var shown: [NotificationEntry] = []
        let layers: [OverlayLayer] = NotificationPlacement.allCases.compactMap { placement in
            let channel = toasts.entries.filter { $0.placement == placement }
            guard !channel.isEmpty else { return nil }
            let (stack, drawn) = stackBuffer(
                channel, placement: placement, width: width, maxHeight: areaHeight - 2, toasts: toasts)
            shown += drawn
            guard !stack.isEmpty else { return nil }
            let origin = placement.origin(
                width: stack.width, height: stack.height, areaWidth: areaWidth, areaHeight: areaHeight)
            return OverlayLayer(offsetX: origin.x, offsetY: origin.y, content: stack, level: .notification)
        }
        // The keys that reach the buttons drawn, newest first; none behind a modal, where they are inert.
        if !toasts.isModal {
            let reachable = shown.filter { !$0.isDismissed && !NotificationToast.buttons(of: $0).isEmpty }
                .sorted { $0.postedAtNanos > $1.postedAtNanos }.map(\.id)
            NotificationKeyboard.register(toasts: reachable, service: service, context: context)
        }
        return layers
    }

    /// What every toast of one walk is drawn with.
    @MainActor
    private struct ToastContext {
        /// The service the toasts are the notifications of.
        let service: NotificationService
        /// The context they are drawn in: their buttons' focus section, or
        /// inert behind a modal.
        let context: RenderContext
        /// The frame's instant, on the service's clock.
        let now: UInt64
        /// The notifications to draw, the one whose button has the focus held
        /// visible.
        let entries: [NotificationEntry]
        /// Whether a modal holds the keyboard, so the toasts' buttons are
        /// drawn inert, as the toolbars' are.
        let isModal: Bool
        /// The toasts with buttons, newest first, for the focus to move on
        /// among when one is chosen.
        let withButtons: [NotificationID]

        init(service: NotificationService, context: RenderContext, now: UInt64, entries: [NotificationEntry]) {
            self.service = service
            self.now = now
            let focusManager = context.environment.focusManager
            isModal = focusManager?.activeSectionIsModal == true
            let withButtons = entries.filter { !NotificationToast.buttons(of: $0).isEmpty }
                .sorted { $0.postedAtNanos > $1.postedAtNanos }.map(\.id)
            self.withButtons = withButtons
            // A toast whose button has the focus waits: its fade starts no
            // sooner than a moment after the focus leaves it.
            if let held = NotificationKeyboard.focused(among: withButtons, focusManager: focusManager) {
                service.keepVisible(held, atNanos: now)
                self.entries = service.activeEntries()
            } else {
                self.entries = entries
            }
            var drawing = context
            if isModal {
                drawing = drawing.isolatedForBackground()
            } else if !withButtons.isEmpty {
                // Passive, as the toolbars' are: Tab reaches it after the page,
                // and it never takes the keyboard by itself.
                focusManager?.registerPassiveSection(id: NotificationKeyboard.sectionID)
                drawing.environment.activeFocusSectionID = NotificationKeyboard.sectionID
            }
            self.context = drawing
        }

        /// What choosing a button on the toast of `id` does after its action:
        /// dismisses the toast and moves the focus on.
        func chosen(_ id: NotificationID) -> @MainActor () -> Void {
            let (service, withButtons) = (service, withButtons)
            let focusManager = context.environment.focusManager
            return { [weak focusManager] in
                service.dismiss(id)
                if let focusManager { NotificationKeyboard.moveOn(after: id, among: withButtons, focusManager: focusManager) }
            }
        }
    }

    /// The toasts of one channel's `entries`, `width` cells wide, stacked
    /// with the newest nearest `placement`'s edge: first on the top edge, last
    /// on the bottom.
    ///
    /// As many as fit in `maxHeight` rows, newest first, and always the newest:
    /// the older ones wait off screen for room, rather than being cut in half
    /// at the area's edge.
    ///
    /// Each toast is drawn at an identity of its own, keyed by its
    /// notification, so what it holds keeps its state for its whole life
    /// whatever comes and goes around it. Measured before it is drawn, so one
    /// that does not fit registers no buttons the focus could reach.
    ///
    /// - Returns: The stack, and the notifications drawn in it.
    @MainActor
    private static func stackBuffer(
        _ entries: [NotificationEntry], placement: NotificationPlacement, width: Int, maxHeight: Int,
        toasts context: ToastContext
    ) -> (FrameBuffer, [NotificationEntry]) {
        var toasts: [FrameBuffer] = []
        var drawn: [NotificationEntry] = []
        var height = 0
        for entry in entries.reversed() {
            let opacity = NotificationTiming.opacity(
                elapsed: entry.age(atNanos: context.now), visibleDuration: entry.duration)
            var toastContext = context.context.withChildIdentity(
                erasedType: NotificationToast.self, key: entry.id.rawValue.uuidString)
            toastContext.availableWidth = width
            let toast = NotificationToast(entry: entry, width: width, opacity: opacity, chosen: context.chosen(entry.id))
            let size = measureChild(toast, proposal: ProposedSize(width: width, height: nil), context: toastContext)
            guard toasts.isEmpty || height + size.height <= maxHeight else { break }
            let buffer = TUIView.renderToBuffer(toast, context: toastContext)
            height += buffer.height
            toasts.append(buffer)
            drawn.append(entry)
        }
        var stack = FrameBuffer()
        for toast in placement.isTop ? toasts : toasts.reversed() { stack.appendVertically(toast) }
        return (stack, drawn)
    }
}

// MARK: - Animation

/// The task that asks for the frames a toast's fades need, and the last one
/// that clears it when it has gone.
enum NotificationAnimation {
    /// Starts the background task that triggers re-renders for fade animations
    /// and cleans up expired notifications.
    ///
    /// Uses a single shared token so only one animation task runs at a time.
    /// The task stops automatically when no notifications are active.
    ///
    /// The frames it asks for are asked of the app drawing the toasts, through
    /// its render cache's link (`frames`), which drops nothing the cache keeps:
    /// the read of the service is unkeyed, so no memo holds a toast.
    @MainActor
    static func start(service: NotificationService, lifecycle: LifecycleManager, frames: RenderCache.Link?) {
        let token = "notification-host-animation"

        // Recorded EVERY frame and started only on the first, which is not the
        // same thing as returning early once it has appeared. `recordAppear` is
        // the only writer of the manager's current-render token set, so a frame
        // that skipped it left the token missing at `endRenderPass`: the token
        // "disappeared", its appearance flag was cleared, and the next frame
        // re-entered here and called `startTask`, which cancels the task
        // already running. The cancelled sleep then threw, the loop broke, and
        // the epilogue asked for another render — so the toast pinned the app
        // at the frame-rate cap for its whole life, creating and cancelling a
        // task per frame, instead of the roughly thirty wakes its sleep
        // schedule computes. The same shape `TaskModifier` and `_ImageCore` use.
        let isFirstAppear = !lifecycle.hasAppeared(token: token)
        _ = lifecycle.recordAppear(token: token) {}
        guard isFirstAppear else { return }

        let nowNanos = service.nowNanos

        lifecycle.startTask(token: token, priority: .medium) { [lifecycle] in
            // What the last frame asked for showed: which notifications, and
            // when each is to fade out. A wake that finds it changed — a post,
            // a dismissal — asks for a frame even with no fade under way.
            var shown: [NotificationTiming.Shown] = []
            while !Task.isCancelled {
                // The entries as they are NOW, read at every wake: one posted
                // while this sleeps fades in on its own schedule, and the task
                // runs until the last of them expires. The ones the task began
                // with left a later post invisible until an earlier one began
                // to fade (2026-10-29 review).
                let entries = service.activeEntries()
                let now = nowNanos()
                // The latest expiry across all entries, on the service's clock.
                if now > entries.map(\.expiresAtNanos).max() ?? 0 {
                    break
                }
                // Sleep until an opacity actually moves, rather than 42 times a
                // second regardless. A notification is at a flat 1.0 for its
                // whole visible stretch — three seconds of the usual three and a
                // half — and every wake in there re-renders the entire screen to
                // draw exactly what is already on it.
                //
                // This cannot be an `AnimatedCellRun`, which is what everything
                // else on this path became: a run LOOPS, and a toast appears
                // once and vanishes. Its cells stop existing, which is a change
                // of layout rather than of appearance.
                let due = entries.map {
                    NotificationTiming.timeUntilOpacityChanges(
                        elapsed: $0.age(atNanos: now), visibleDuration: $0.duration)
                }.min() ?? 0
                // To an instant a 2-tick frame begins on the clock the frames are
                // stamped with, where a bar or a view animation on the same screen
                // changes too, rather than a fixed sleep from wherever this woke. The
                // clock is read again for the sleep, so the work above is not added on.
                let wake = UInt64(
                    clamping: NotificationTiming.nextWakeNanos(after: Int64(clamping: now), due: due))
                let current = nowNanos()
                try? await Task.sleep(nanoseconds: wake > current ? wake - current : 0)
                guard !Task.isCancelled else { break }
                // A frame only where it would draw something new: a wake that
                // only bounds the sleep (``NotificationTiming/longestSleep``)
                // draws the screen already there. Asked every wake, a toast
                // that stays until dismissed kept the app rendering four times
                // a second for as long as it stayed.
                let showing = entries.map { NotificationTiming.Shown(id: $0.id, duration: $0.duration) }
                if NotificationTiming.wakeDraws(due: due, shown: showing, lastShown: shown) {
                    shown = showing
                    frames?.requestFrame()
                }
            }

            // Only when the loop ran to its own end. A CANCELLED task is being
            // replaced, and its epilogue would clear the appearance flag the
            // replacement has just set — so the frame after that would start a
            // third task, cancelling the second, forever — and would ask for a
            // render on the way out.
            guard !Task.isCancelled else { return }
            // Final render to clear expired notifications.
            lifecycle.resetAppearance(token: token)
            frames?.requestFrame()
        }
    }
}
