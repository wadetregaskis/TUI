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
/// app shows its toasts with nothing to add: they float over the page — over
/// any sheet or alert in it too (``OverlayLevel/notification`` is the topmost
/// level), or under it, as each toast's ``NotificationLayer`` and whose it is
/// say — and leave the bars uncovered. The package-level
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
    ///
    /// Each toast is a layer of its own, at the level its cover says
    /// (``NotificationCoverage``): one nothing covers over everything,
    /// ``OverlayLevel/notification``, its buttons live; one under a sheet,
    /// an alert or a dialog beneath every presented surface, where the
    /// presentation's veil dims it, its buttons inert and its clock stopped
    /// (``NotificationService/setCovered(_:atNanos:)``).
    @MainActor
    static func layers(context: RenderContext, areaWidth: Int, areaHeight: Int) -> [OverlayLayer] {
        // Without an app there is no service, so there is nothing to show.
        guard !context.isMeasuring, let service = context.environment.notificationService else { return [] }
        // A window held behind the one in front is drawn into nothing
        // (`ScenePresenter`): the toasts, their timing and their desktop
        // requests are the front window's.
        guard context.environment.focusManager?.isBackdrop != true else { return [] }
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
        // The toasts posted to the desktop too: through the terminal, where
        // their delivery applies in the scene's phase now. Sent by the frame
        // that first draws them, once.
        let phase = context.environment.scenePhase
        for request in service.takeDesktopRequests() where request.delivery.delivers(in: phase) {
            context.environment.terminalBell?.postNotification(request.message)
        }
        guard areaWidth > 0, areaHeight > 0 else { return [] }
        // The frame's stamp, so every toast in one frame fades by one instant and a
        // re-walk of the frame draws the same picture. A one-off render has no stamp —
        // `nowNanos` is 0 outside the run loop — and reads the service's clock instead,
        // which is what the toast was posted on.
        let frame = context.environment.animationFrame
        let now = frame.canAnimate ? UInt64(bitPattern: frame.nowNanos) : service.nowNanos()
        // What covers which toast, and so whose clock stops: noted before the
        // drawing reads their ages.
        let coverage = NotificationCoverage(
            focusManager: context.environment.focusManager, window: service.owner?.window)
        let covered = Set(service.activeEntries().filter(coverage.covers).map(\.id))
        service.setCovered(covered, atNanos: now)
        let activeEntries = service.activeEntries().filter(coverage.isDrawnHere)
        guard !activeEntries.isEmpty else { return [] }

        if let lifecycle = context.environment.lifecycle {
            NotificationAnimation.start(service: service, lifecycle: lifecycle, frames: context.renderCache?.link)
        }

        let width = min(service.width, max(1, areaWidth - 2))
        let toasts = ToastContext(
            service: service, context: context, now: now, entries: activeEntries, covered: covered,
            overPresentation: coverage.presentation != nil)
        // A stack per placement, each its own channel; a layer per toast in it.
        var shown: [NotificationEntry] = []
        var layers: [OverlayLayer] = []
        for placement in NotificationPlacement.allCases {
            let channel = toasts.entries.filter { $0.placement == placement }
            guard !channel.isEmpty else { continue }
            let drawn = stack(channel, placement: placement, width: width, maxHeight: areaHeight - 2, toasts: toasts)
            guard !drawn.isEmpty else { continue }
            shown += drawn.map(\.entry)
            let stackHeight = drawn.reduce(0) { $0 + $1.buffer.height }
            let stackWidth = drawn.map(\.buffer.width).max() ?? 0
            let origin = placement.origin(
                width: stackWidth, height: stackHeight, areaWidth: areaWidth, areaHeight: areaHeight)
            var y = origin.y
            for toast in drawn {
                let isCovered = covered.contains(toast.entry.id)
                layers.append(
                    OverlayLayer(
                        offsetX: origin.x, offsetY: y, content: toast.buffer,
                        level: isCovered ? .popover : .notification,
                        zIndex: isCovered ? Self.coveredZIndex : 0))
                y += toast.buffer.height
            }
        }
        // The keys that reach the buttons drawn, newest first: those of the
        // toasts nothing covers, which a presented surface does not stop.
        let reachable = shown.filter {
            !$0.isDismissed && !covered.contains($0.id) && !NotificationToast.buttons(of: $0).isEmpty
        }
        .sorted { $0.postedAtNanos > $1.postedAtNanos }.map(\.id)
        NotificationKeyboard.register(toasts: reachable, service: service, context: context)
        return layers
    }

    /// The ``OverlayLayer/zIndex`` of a covered toast's layer, at
    /// ``OverlayLevel/popover``: below every presented surface — a drop-down,
    /// a menu, a sheet, an alert — whose veil dims it, and above a view's own
    /// displaced drawing (``OverlayLayer/displacedDrawingZIndex``), as the page
    /// it lies on is.
    static let coveredZIndex: Double = -0.5

    /// What every toast of one walk is drawn with.
    @MainActor
    private struct ToastContext {
        /// The service the toasts are the notifications of.
        let service: NotificationService
        /// The context a toast nothing covers is drawn in: its buttons in the
        /// toasts' focus section.
        let context: RenderContext
        /// The context a covered toast is drawn in: isolated, so its buttons
        /// are inert, as the page's are under a sheet.
        let coveredContext: RenderContext
        /// The frame's instant, on the service's clock.
        let now: UInt64
        /// The notifications to draw, the one whose button has the focus held
        /// visible.
        let entries: [NotificationEntry]
        /// The ones covered this frame.
        let covered: Set<NotificationID>
        /// The toasts nothing covers with buttons, newest first, for the focus
        /// to move on among when one is chosen.
        let withButtons: [NotificationID]

        init(
            service: NotificationService, context: RenderContext, now: UInt64, entries: [NotificationEntry],
            covered: Set<NotificationID>, overPresentation: Bool
        ) {
            self.service = service
            self.now = now
            self.covered = covered
            let focusManager = context.environment.focusManager
            let withButtons = entries.filter { !covered.contains($0.id) && !NotificationToast.buttons(of: $0).isEmpty }
                .sorted { $0.postedAtNanos > $1.postedAtNanos }.map(\.id)
            self.withButtons = withButtons
            // A toast whose button has the focus waits: its fade starts no
            // sooner than a moment after the focus leaves it.
            if let held = NotificationKeyboard.focused(among: withButtons, focusManager: focusManager) {
                service.keepVisible(held, atNanos: now)
                let drawnHere = Set(entries.map(\.id))
                self.entries = service.activeEntries().filter { drawnHere.contains($0.id) }
            } else {
                self.entries = entries
            }
            // Made only where something is covered: isolating makes the
            // throwaway focus manager and dispatcher a backdrop draws into.
            coveredContext = covered.isEmpty ? context : context.isolatedForBackground()
            var drawing = context
            if !withButtons.isEmpty {
                // Passive, as the toolbars' are: Tab reaches it after the page,
                // and it never takes the keyboard by itself.
                let section = NotificationKeyboard.sectionID
                focusManager?.registerPassiveSection(id: section)
                drawing.environment.activeFocusSectionID = section
                if overPresentation {
                    // Over a sheet, an alert or a dialog, the buttons are as
                    // modal as it is: Tab stays among them, the window's bars
                    // stay inert while they have the focus, and the surface's
                    // presenter leaves the focus with them rather than taking
                    // it back (`activatePresentedSection(id:)`). While they
                    // have it, the keyboard is theirs, not the surface's
                    // behind them: its Escape and its keys do not fire.
                    focusManager?.markSectionModal(id: section)
                    if focusManager?.activeSectionIdentifier == section {
                        context.environment.keyEventDispatcher?.grabInput(sectionID: section)
                    }
                }
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
    /// - Returns: The toasts drawn, top to bottom, each with its notification.
    @MainActor
    private static func stack(
        _ entries: [NotificationEntry], placement: NotificationPlacement, width: Int, maxHeight: Int,
        toasts context: ToastContext
    ) -> [(buffer: FrameBuffer, entry: NotificationEntry)] {
        var drawn: [(buffer: FrameBuffer, entry: NotificationEntry)] = []
        var height = 0
        for entry in entries.reversed() {
            let opacity = NotificationTiming.opacity(
                elapsed: entry.age(atNanos: context.now), visibleDuration: entry.duration)
            let base = context.covered.contains(entry.id) ? context.coveredContext : context.context
            var toastContext = base.withChildIdentity(
                erasedType: NotificationToast.self, key: entry.id.rawValue.uuidString)
            toastContext.availableWidth = width
            let toast = NotificationToast(entry: entry, width: width, opacity: opacity, chosen: context.chosen(entry.id))
            let size = measureChild(toast, proposal: ProposedViewSize(width: width, height: nil), context: toastContext)
            guard drawn.isEmpty || height + size.height <= maxHeight else { break }
            let buffer = TUIView.renderToBuffer(toast, context: toastContext)
            height += buffer.height
            drawn.append((buffer, entry))
        }
        return placement.isTop ? drawn : drawn.reversed()
    }
}

// MARK: - Coverage

/// What covers which toast this frame: the presented surface holding the
/// window's keyboard, and the window in front.
///
/// A toast ``NotificationLayer/abovePresentations`` is covered by nothing. One
/// ``NotificationLayer/belowPresentations`` is covered by any sheet, alert,
/// dialog, popover or open menu holding the keyboard — unless it was posted
/// from that very presentation, which it is on top of. One posted for another
/// window is covered while that window is behind, and not drawn.
@MainActor
struct NotificationCoverage {
    /// The focus section of the presented surface holding the keyboard,
    /// looking through the toasts' own (focused over it), or `nil` while
    /// nothing is presented.
    let presentation: String?

    /// The window drawing the toasts, or `nil` where it is not known.
    let window: Int?

    init(focusManager: FocusManager?, window: Int?) {
        self.presentation = focusManager?.presentedSection(beneath: NotificationKeyboard.sectionID)
        self.window = window
    }

    /// Whether the toast of `entry` is drawn in this window: one posted for
    /// another window waits for that one to come to the front.
    func isDrawnHere(_ entry: NotificationEntry) -> Bool {
        guard let theirs = entry.owner?.window, let window else { return true }
        return theirs == window
    }

    /// Whether the toast of `entry` is covered: under a presentation, or
    /// waiting for its window.
    func covers(_ entry: NotificationEntry) -> Bool {
        guard isDrawnHere(entry) else { return true }
        guard entry.layer == .belowPresentations, let presentation else { return false }
        return entry.owner?.presentation != presentation
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
                // A covered toast's clock is stopped, so its opacity never
                // moves until a frame uncovers it; with every toast covered,
                // the wake is only the bound on the sleep.
                let due = entries.map {
                    $0.isCovered
                        ? .infinity
                        : NotificationTiming.timeUntilOpacityChanges(
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
