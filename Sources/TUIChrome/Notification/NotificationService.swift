//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationService.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Synchronization
import TUIFoundation

// MARK: - Notification Service

/// Central service for posting and managing notifications.
///
/// `NotificationService` lives in the environment and accepts fire-and-forget
/// notification posts from anywhere in the view hierarchy. Every scene
/// draws the active entries over its content, as a stack of toasts: there is
/// no host for the app to add.
///
/// ## Usage
///
/// Post notifications from anywhere using the shared instance:
///
/// ```swift
/// NotificationService.current.post("Saved!")
/// NotificationService.current.post("Connection lost", style: .error, duration: 5.0)
/// let saving = NotificationService.current.post("Saving…", duration: nil)
/// NotificationService.current.dismiss(saving)
/// ```
///
/// A ``NotificationStyle`` says what a notification is about — news, a
/// success, a warning, an error — in the palette's colour for it and with a
/// glyph, so the meaning never rests on colour alone.
///
/// ## Lifecycle
///
/// Each notification goes through three phases:
/// 1. **Fade-in** (0.2s) — opacity ramps from 0 to 1
/// 2. **Visible** — stays at full opacity for `duration` seconds, or until
///    it is dismissed (``dismiss(_:)``) where `duration` is `nil`
/// 3. **Fade-out** (0.3s) — opacity ramps from 1 to 0, then entry is removed
///
/// The service automatically removes expired entries and triggers re-renders
/// for animation frames.
public final class NotificationService: Sendable {
    /// The shared instance used by the running application.
    ///
    /// Prefer the environment where you can: the render loop installs this
    /// instance at ``EnvironmentValues/notificationService`` every frame, so a
    /// view body reaches it with `@Environment(\.notificationService)` and a
    /// test can substitute its own without touching global state.
    ///
    /// The static remains because a closure is not a body. Button actions,
    /// `onSelect` handlers and the rest run at EVENT time, when there is no
    /// render context to read an environment from — an `@Environment` property
    /// is nil there. A view that has a body can capture the service into its
    /// closure at render time; one that does not, and any code reached from
    /// outside the view tree at all, has only this.
    ///
    /// For tests, construct a fresh instance rather than reaching for
    /// `current`, which every test in the process shares.
    ///
    /// ```swift
    /// NotificationService.current.post("Done!")
    /// ```
    public static var current: NotificationService {
        get { currentStore.withLock { $0 } }
        set { currentStore.withLock { $0 = newValue } }
    }

    /// ``current``'s storage, read once a frame by the render loop.
    private static let currentStore = Mutex(NotificationService())

    private struct State {
        /// The active notification entries, ordered by posting time.
        var entries: [NotificationEntry] = []

        /// The links of the render caches of the apps that draw this service's
        /// notifications, which a post asks for a frame: one per app, noted as
        /// its scene draws them (``noteDisplayed(by:)``).
        ///
        /// A post can come from anywhere — an event handler, a task, a callback on
        /// a queue of its own — so it cannot ask "the app" for a frame: the host
        /// that draws the service is how the service knows which apps that is. A
        /// link, not the app's render state: it holds nothing that holds the cache
        /// or the app, and once its cache has gone it asks no one, and the next
        /// host to note itself drops it.
        var displays: [RenderCache.Link] = []
    }

    private let state = Mutex(State())

    /// The clock a notification's age is measured on.
    ///
    /// ``MonotonicClock``, the clock the run loop stamps every frame with, so a toast's
    /// fade is on the same timeline as every other animation. It was the wall clock,
    /// `Date()`, which can be set backwards (or forwards) while a toast is up, and which
    /// no test could step.
    let nowNanos: @Sendable () -> UInt64

    /// Creates an empty notification service.
    public convenience init() {
        self.init(nowNanos: { MonotonicClock.nowNanoseconds })
    }

    /// Creates an empty notification service that reads `nowNanos` for the time — a
    /// test's own clock.
    init(nowNanos: @escaping @Sendable () -> UInt64) {
        self.nowNanos = nowNanos
    }
}

// MARK: - Public API

extension NotificationService {
    /// Posts a new notification with localized text.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The notification appears immediately and
    /// auto-dismisses after `duration` seconds, or stays until it is
    /// dismissed where `duration` is `nil`.
    ///
    /// - Parameters:
    ///   - messageKey: The key for the notification message text.
    ///   - style: What it is about, which its colour and glyph say (default: ``NotificationStyle/plain``).
    ///   - duration: How long the notification stays visible in seconds (default: 3.0), or `nil` to keep it
    ///     until it is dismissed.
    /// - Returns: The notification's identifier, for ``dismiss(_:)``.
    @discardableResult
    public func post(
        _ messageKey: LocalizedStringKey, style: NotificationStyle = .plain, duration: TimeInterval? = 3.0
    ) -> NotificationID {
        post(messageKey.localized, style: style, duration: duration)
    }

    /// Posts a new notification, displayed as written.
    ///
    /// The notification appears immediately and auto-dismisses after `duration`
    /// seconds, or stays until it is dismissed where `duration` is `nil`.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. `duration`'s default survives the change: it is
    /// the generic parameter itself that cannot carry one (there would be
    /// nothing left to infer `S` from), and `duration` is not generic.
    ///
    /// - Parameters:
    ///   - message: The notification message text.
    ///   - style: What it is about, which its colour and glyph say (default: ``NotificationStyle/plain``).
    ///   - duration: How long the notification stays visible in seconds (default: 3.0), or `nil` to keep it
    ///     until it is dismissed.
    /// - Returns: The notification's identifier, for ``dismiss(_:)``.
    @_disfavoredOverload
    @discardableResult
    public func post<S: StringProtocol>(
        _ message: S, style: NotificationStyle = .plain, duration: TimeInterval? = 3.0
    ) -> NotificationID {
        let now = nowNanos()
        let entry = NotificationEntry(
            message: String(message), style: style, duration: duration ?? .infinity, postedAtNanos: now)
        add(entry, now: now)
        return entry.id
    }

    /// Fades out the notification `id` names, at once, whatever its duration
    /// — one posted to stay until dismissed included. Nothing happens where it
    /// has gone, or is already fading out.
    ///
    /// ```swift
    /// let saving = NotificationService.current.post("Saving…", duration: nil)
    /// try await document.save()
    /// NotificationService.current.dismiss(saving)
    /// ```
    public func dismiss(_ id: NotificationID) {
        dismiss { $0.id == id }
    }

    /// Fades out every notification, at once.
    public func dismissAll() {
        dismiss { _ in true }
    }

    /// Fades out the notifications `matches` picks, and asks the apps that
    /// draw them for a frame.
    func dismiss(where matches: (NotificationEntry) -> Bool) {
        let now = nowNanos()
        let displays = state.withLock { state in
            for index in state.entries.indices where matches(state.entries[index]) {
                state.entries[index] = state.entries[index].dismissed(atNanos: now)
            }
            return state.displays
        }
        for link in displays { link.requestFrame() }
    }

    /// Adds `entry`, posted at `now`, and asks the apps that draw this
    /// service for a frame.
    private func add(_ entry: NotificationEntry, now: UInt64) {
        let displays = state.withLock { state in
            // The expired go here too, not only in `activeEntries()`: that is the
            // drawing's to call, and a service nothing draws (a program that posts
            // with no scene up) kept every post it was ever given. The same rule as
            // `activeEntries()`, so what is drawn next is unchanged.
            state.entries.removeAll { now > $0.expiresAtNanos }
            state.entries.append(entry)
            return state.displays
        }
        // Outside the lock: a frame request calls the app's observers.
        for link in displays { link.requestFrame() }
    }

    /// Notes that the app whose render cache `link` is draws this service's
    /// notifications, so a post asks it for a frame. Called on every frame
    /// that draws them; `nil` — a render with no cache — notes nothing.
    package func noteDisplayed(by link: RenderCache.Link?) {
        guard let link else { return }
        state.withLock { state in
            // The usual case: noted already, one comparison.
            guard !state.displays.contains(where: { $0 === link }) else { return }
            state.displays.removeAll { !$0.isAttached }
            state.displays.append(link)
        }
    }

    /// Returns a snapshot of all currently active notifications.
    ///
    /// Entries whose total animation time (fade-in + visible + fade-out) has
    /// elapsed are pruned before the snapshot is returned.
    func activeEntries() -> [NotificationEntry] {
        let now = nowNanos()

        return state.withLock { state in
            state.entries.removeAll { now > $0.expiresAtNanos }
            return state.entries
        }
    }

    /// How many notifications are kept, expired or not, without pruning. For
    /// tests: a number that only grows is a leak.
    var entryCount: Int {
        state.withLock { $0.entries.count }
    }

    /// Removes all active notifications.
    func clear() {
        state.withLock { $0.entries.removeAll() }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The notification service for posting and managing notifications.
    ///
    /// Read by the scene, which draws the active entries over its content.
    /// Post notifications via the static accessor:
    ///
    /// ```swift
    /// NotificationService.current.post("Saved!")
    /// ```
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    public var notificationService: NotificationService? {
        // Kept in the substrate's `.notificationService` slot
        // (`FeatureObjectSlot`), which detaching an environment clears: the
        // service belongs to the window chrome, above the substrate, so the
        // substrate clears the slot without naming this type.
        get { self[featureObject: .notificationService] as? NotificationService }
        set { self[featureObject: .notificationService] = newValue }
    }
}
