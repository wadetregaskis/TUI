//  🖥️ TUI — A Terminal UI framework for Swift
//  ServiceEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Localization Service

/// EnvironmentKey for the localization service.
private struct LocalizationServiceKey: EnvironmentKey {
    static let defaultValue = LocalizationService.shared
}

// MARK: - Lifecycle Manager

/// EnvironmentKey for view lifecycle tracking (appear/disappear/task).
private struct LifecycleKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: LifecycleManager? = nil
}

// MARK: - Key Event Dispatcher

/// EnvironmentKey for key event handler registration and dispatch.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct KeyEventDispatcherKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    @usableFromInline static let defaultValue: KeyEventDispatcher? = nil
}

// MARK: - Mouse Event Dispatcher

/// EnvironmentKey for mouse event handler registration and dispatch.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct MouseEventDispatcherKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    @usableFromInline static let defaultValue: MouseEventDispatcher? = nil
}

// MARK: - Animation Scheduler

/// EnvironmentKey for the run loop's animation scheduler. An animating view
/// declares how often it wants re-rendering through it (see
/// ``RenderContext/requestAnimation(token:frameTicks:)``)
/// and the scheduler coalesces those declarations so one render serves them all.
///
/// `nil` outside the live run loop — e.g. `ViewRenderer`'s one-off snapshot path,
/// which renders a single static frame and schedules no animation.
private struct AnimationSchedulerKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: AnimationScheduler? = nil
}

// MARK: - Synthesised Key Event Dispatch

/// EnvironmentKey for the synthesised-key path: a closure
/// that routes a ``KeyEvent`` through the full
/// ``InputHandler`` 5-layer chain. See ``TUIContext/
/// synthesizeKeyEvent`` for the rationale and consumer.
///
/// The closure is typed `@MainActor` because every caller
/// (``RenderLoop``, ``StatusBar``'s mouse handler) and the
/// only producer (``AppRunner/run()``) all run on the main
/// actor; the annotation also satisfies `Sendable` for the
/// static `defaultValue` storage.
private struct SynthesizeKeyEventKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: (@MainActor (KeyEvent) -> Void)? = nil
}

// MARK: - Preference Storage

/// EnvironmentKey for preference value collection during rendering.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct PreferenceStorageKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    @usableFromInline static let defaultValue: PreferenceStorage? = nil
}

// MARK: - Pulse Phase

/// EnvironmentKey for the focus indicator breathing animation phase.
private struct PulsePhaseKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: Double = 0
}

// MARK: - Cursor Timer

/// EnvironmentKey for TextField/SecureField cursor blink animation.
private struct CursorTimerKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    // `CursorTimer` is `@MainActor` (hence implicitly `Sendable`), so a `nil`
    // default needs no `nonisolated(unsafe)`.
    static let defaultValue: CursorTimer? = nil
}

// MARK: - Focus Indicator

/// EnvironmentKey for the active section's breathing ● in the current subtree.
private struct FocusIndicatorKey: EnvironmentKey {
    static let defaultValue: AnimatedColor? = nil
}

/// EnvironmentKey for the drag-and-drop session.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct DragAndDropSessionKey: EnvironmentKey {
    @usableFromInline static let defaultValue: DragAndDropSession? = nil
}

private struct TypedClipboardKey: EnvironmentKey {
    static let defaultValue: TypedClipboard? = nil
}

private struct ScreenSelectionKey: EnvironmentKey {
    static let defaultValue: ScreenSelection? = nil
}

// MARK: - Terminal image store

/// EnvironmentKey for the images this app has put in the terminal.
private struct TerminalImageStoreKey: EnvironmentKey {
    static let defaultValue: TerminalImageStore? = nil
}

private struct AppScopedObjectsKey: EnvironmentKey {
    static let defaultValue: AppScopedObjects? = nil
}

// MARK: - EnvironmentValues Extensions

extension EnvironmentValues {

    /// The localization service for retrieving translated strings.
    package var localizationService: LocalizationService {
        get { self[LocalizationServiceKey.self] }
        set { self[LocalizationServiceKey.self] = newValue }
    }

    /// The currently active language.
    var currentLanguage: LocalizationService.Language {
        localizationService.currentLanguage
    }

    /// View lifecycle tracking (appear, disappear, task management).
    package var lifecycle: LifecycleManager? {
        get { self[LifecycleKey.self] }
        set { self[LifecycleKey.self] = newValue }
    }

    /// Key event handler registration and dispatch.
    ///
    /// Setting it also sets `keyChannelToken`, which the value memos compare to
    /// tell a subtree's registrations into these channels from ones made into
    /// throwaways swapped in below.
    ///
    /// Only the getter is `@inlinable` (module split step A3): the setter also
    /// writes `keyChannelToken`, which it would have to export to save one call.
    @usableFromInline
    package var keyEventDispatcher: KeyEventDispatcher? {
        @inlinable get { self[KeyEventDispatcherKey.self] }
        set {
            self[KeyEventDispatcherKey.self] = newValue
            keyChannelToken = newValue.map(ObjectIdentifier.init)
        }
    }

    /// Dispatches a synthesised ``KeyEvent`` through the full
    /// ``InputHandler`` 5-layer chain. See
    /// ``TUIContext/synthesizeKeyEvent`` for the rationale.
    package var synthesizeKeyEvent: (@MainActor (KeyEvent) -> Void)? {
        get { self[SynthesizeKeyEventKey.self] }
        set { self[SynthesizeKeyEventKey.self] = newValue }
    }

    /// Mouse event handler registration and dispatch.
    @inlinable
    package var mouseEventDispatcher: MouseEventDispatcher? {
        get { self[MouseEventDispatcherKey.self] }
        set { self[MouseEventDispatcherKey.self] = newValue }
    }

    /// The images this app has transmitted to the terminal, or `nil` where
    /// there is no terminal to transmit to — a headless ``ViewRenderer``, a
    /// snapshot test. `nil` is not a degraded mode: an ``Image`` with nowhere
    /// to send pixels draws itself out of glyphs, which is what it has always
    /// done.
    package var terminalImageStore: TerminalImageStore? {
        get { self[TerminalImageStoreKey.self] }
        set { self[TerminalImageStoreKey.self] = newValue }
    }

    /// The objects this app's optional modules keep for it
    /// (``AppScopedObjects``), or `nil` outside a live app — where a module
    /// keeps nothing across renders.
    package var appScopedObjects: AppScopedObjects? {
        get { self[AppScopedObjectsKey.self] }
        set { self[AppScopedObjectsKey.self] = newValue }
    }

    /// The values this app last copied, or `nil` outside a live app — where a
    /// copy puts its text on the clipboard and nothing more.
    package var typedClipboard: TypedClipboard? {
        get { self[TypedClipboardKey.self] }
        set { self[TypedClipboardKey.self] = newValue }
    }

    /// TUI's selection of what is drawn, whose context menu the window
    /// presents; `nil` outside a live app.
    package var screenSelection: ScreenSelection? {
        get { self[ScreenSelectionKey.self] }
        set { self[ScreenSelectionKey.self] = newValue }
    }

    /// The app-wide drag-and-drop session, or `nil` outside a live app.
    @inlinable
    package var dragAndDropSession: DragAndDropSession? {
        get { self[DragAndDropSessionKey.self] }
        set { self[DragAndDropSessionKey.self] = newValue }
    }

    /// The run loop's animation scheduler, or `nil` outside the live loop.
    package var animationScheduler: AnimationScheduler? {
        get { self[AnimationSchedulerKey.self] }
        set { self[AnimationSchedulerKey.self] = newValue }
    }

    /// Preference value collection during rendering.
    ///
    /// Public and settable for the same reason ``stateStorage`` is: a headless
    /// renderer has to be able to wire it. The modifiers that publish a
    /// preference force-unwrap this, so a tree containing `.preference` cannot
    /// be rendered at all without it — which is what the `preferences` stress
    /// scenario ran into.
    @inlinable
    public var preferenceStorage: PreferenceStorage? {
        get { self[PreferenceStorageKey.self] }
        set { self[PreferenceStorageKey.self] = newValue }
    }

    /// The current breathing animation phase (0-1) for the focus indicator.
    ///
    /// This is per-frame volatile: it changes every render without clearing the
    /// render cache. Reading it records to any active ``volatileReadTracker`` so
    /// a value-memoizing view (`_MemoizedRow`) can decline to cache a subtree
    /// whose output would otherwise freeze.
    package var pulsePhase: Double {
        get {
            volatileReadTracker?.recordVolatileRead()
            return self[PulsePhaseKey.self]
        }
        set { self[PulsePhaseKey.self] = newValue }
    }

    /// The cursor timer for TextField/SecureField animations.
    package var cursorTimer: CursorTimer? {
        get { self[CursorTimerKey.self] }
        set { self[CursorTimerKey.self] = newValue }
    }

    /// The breathing ● the first border encountered in this subtree should
    /// draw — and every frame of it, so that border can hand the run loop a
    /// run rather than have the whole page re-render per tick.
    package var focusIndicator: AnimatedColor? {
        get { self[FocusIndicatorKey.self] }
        set { self[FocusIndicatorKey.self] = newValue }
    }
}

// MARK: - Detaching From the Runtime

extension EnvironmentValues {
    /// This environment without the framework's own objects: the runtime
    /// services ``applyRuntimeServices(from:)`` wires, the app's managers the
    /// render loop adds, the per-pass trackers, and the per-subtree objects a
    /// presentation or a control hands down to the views it draws.
    ///
    /// For an environment kept PAST the render that handed it over, on
    /// something the state storage holds: a scroll view keeps its environment
    /// on its handler for the scroll target behaviour it asks at event time
    /// (`ScrollViewTargeting`). Each of these objects reaches the state
    /// storage, or is reached from it, so kept there whole the environment was
    /// a cycle — storage, box, handler, environment, storage — and an app's
    /// state, render cache, focus manager and dispatchers outlived it.
    ///
    /// What is left is every value an app can state and a behaviour can read:
    /// the size classes, the layout direction, the app's own keys and objects.
    /// None of the objects cleared is one an app reads from a behaviour; each
    /// is the framework's.
    func detachedFromRuntime() -> EnvironmentValues {
        var detached = self
        // `applyRuntimeServices(from:)`.
        detached.keyboardShortcutRegistry = nil
        detached.stateStorage = nil
        detached.lifecycle = nil
        detached.keyEventDispatcher = nil
        detached.synthesizeKeyEvent = nil
        detached.keysAfterFrame = nil
        detached.mouseEventDispatcher = nil
        detached.dragAndDropSession = nil
        detached.typedClipboard = nil
        detached.tooltipState = nil
        detached.terminalImageStore = nil
        detached.renderCache = nil
        detached.preferenceStorage = nil
        // The render loop's managers and per-frame objects.
        detached.statusBar = nil
        detached.windowChrome = nil
        detached.focusManager = nil
        detached.paletteManager = nil
        detached.appearanceManager = nil
        detached.controlStyleManager = nil
        detached.cursorTimer = nil
        detached.animationScheduler = nil
        detached.volatileReadTracker = nil
        // Handed down to a subtree by what encloses it.
        detached.scrollContentWindow = nil
        detached.scrollToRegistry = nil
        detached.scrollPositionBinding = nil
        detached.scrollObservers = ScrollObservers()
        detached.dismissalGate = nil
        detached.menuRowSink = nil
        detached.assignedFocusID = nil
        detached.assignedKeyboardShortcut = nil
        detached.focusHandoffOffer = nil
        detached.preferredFocusOffer = nil
        detached.listRowEditRestrictions = nil
        detached.navigationBarItems = nil
        // …and by the features above the substrate, each in a slot this
        // cannot see the type of (``FeatureObjectSlot``): the navigation
        // stack's coordinator, a dialog's suppression toggle, a searchable's
        // dismissal, focus offer and scope bar, and the notification service
        // the render loop publishes for the window chrome.
        for slot in FeatureObjectSlot.allCases {
            detached[featureObject: slot] = nil
        }
        return detached
    }
}
