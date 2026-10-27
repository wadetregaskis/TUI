//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIContext.swift
//
//  Central dependency container replacing scattered singletons.
//  Owned by AppRunner and threaded through RenderContext.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIView

// MARK: - Lifecycle Manager

/// Manages view lifecycle tracking, disappear callbacks, and async tasks.
///
/// Bundles lifecycle tracking, disappear callbacks, and async task management
/// into a single cohesive manager.
/// All mutable state is protected by `NSLock`.
package final class LifecycleManager: @unchecked Sendable {

    /// Lock protecting all mutable state.
    private let lock = NSLock()

    // MARK: - Lifecycle Tracking

    /// Set of tokens that have appeared.
    private var appearedTokens: Set<String> = []

    /// Set of tokens that are currently visible (for onDisappear tracking).
    private var visibleTokens: Set<String> = []

    /// Tokens seen during the current render pass.
    private var currentRenderTokens: Set<String> = []

    // MARK: - Disappear Callbacks

    /// Callbacks registered for view disappearance.
    private var disappearCallbacks: [String: () -> Void] = [:]

    // MARK: - Task Storage

    /// Running async tasks keyed by lifecycle token.
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Whether appear/task effects actually run.
    ///
    /// `true` for a live app. A one-off snapshot render (see
    /// ``ViewRenderer``) sets this `false`: views are still tracked
    /// (so `recordAppear` tokens behave), but `onAppear` actions don't
    /// execute and `.task` work isn't started — there is no run loop
    /// to observe their results and no teardown pass to balance them,
    /// and a snapshot must not mutate shared state as a side effect.
    private let firesEffects: Bool

    /// Where an `onAppear` action and a task's start wait while the walk is in
    /// a drawing it may still discard, and where what an appearance changed is
    /// noted so it can be put back (``EffectStage``). The app's state
    /// storage's stage, wired by ``TUIContext``; `nil` for a manager standing
    /// alone, which acts at once.
    package var effectStage: EffectStage? {
        get { lock.withLock { _effectStage } }
        set {
            lock.withLock { _effectStage = newValue }
            // A discarded drawing takes back the presence it noted.
            newValue?.presenceUndo = { [weak self] token in self?.forgetPresence(token) }
        }
    }

    /// ``effectStage``'s storage, under the lock.
    private var _effectStage: EffectStage?

    // MARK: - Init

    /// Creates a new lifecycle manager.
    ///
    /// - Parameter firesEffects: Whether `onAppear`/`.task` effects
    ///   run (default `true`). Pass `false` for a side-effect-free
    ///   snapshot render.
    package init(firesEffects: Bool = true) {
        self.firesEffects = firesEffects
    }
}

// MARK: - Internal API

extension LifecycleManager {
    /// Marks the start of a new render pass.
    package func beginRenderPass() {
        lock.lock()
        defer { lock.unlock() }
        currentRenderTokens.removeAll()
    }

    /// Starts a walk of the frame made again for what its effects wrote
    /// (`FrameSettling`): a view's presence is the last walk's, so one the
    /// walk before drew — on screen last frame, or appearing in it — that this
    /// one does not, disappears with the frame, its `onDisappear` run. What
    /// has appeared stays appeared: the walk before's `onAppear`s have run.
    package func beginRewalk() {
        lock.lock()
        defer { lock.unlock() }
        visibleTokens.formUnion(currentRenderTokens)
        currentRenderTokens.removeAll()
    }

    /// Takes back `token`'s presence in this pass, for a discarded drawing
    /// that first saw it (``EffectStage/presenceUndo``).
    private func forgetPresence(_ token: String) {
        lock.lock()
        currentRenderTokens.remove(token)
        lock.unlock()
    }

    /// Marks the end of a render pass and triggers onDisappear for views that are no longer visible.
    package func endRenderPass() {
        lock.lock()
        let disappeared = visibleTokens.subtracting(currentRenderTokens)
        for token in disappeared {
            appearedTokens.remove(token)
        }
        visibleTokens = currentRenderTokens
        let callbacks = disappearCallbacks
        // A fired callback has served its purpose: if the view ever returns,
        // its modifier re-registers on that render (they register every
        // frame). Keeping the entry leaked one closure — plus whatever app
        // state it captured — for every ForEach row or task(id:) generation
        // that ever left the tree.
        for token in disappeared {
            disappearCallbacks.removeValue(forKey: token)
        }
        lock.unlock()

        // Execute callbacks outside the lock to avoid deadlocks
        for token in disappeared {
            callbacks[token]?()
        }
    }

    /// The number of registered disappear callbacks — a leak canary for tests.
    var disappearCallbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return disappearCallbacks.count
    }

    /// Records that a view with the given token appeared.
    ///
    /// Inside a drawing the walk may still discard, the action waits for the
    /// drawing to be kept, and the appearance — and the view's presence in
    /// this pass — is taken back if it is not (``EffectStage``): the drawing
    /// made in its place is the view's first, and a view only the discarded
    /// drawing drew is not on screen.
    ///
    /// - Parameters:
    ///   - token: Unique identifier for the view.
    ///   - action: The onAppear action to execute.
    /// - Returns: True if this is the first appearance (the action runs, or
    ///   waits for the drawing to be kept).
    @discardableResult
    package func recordAppear(token: String, action: @escaping () -> Void) -> Bool {
        lock.lock()
        let isPresent = !currentRenderTokens.insert(token).inserted
        let stage = _effectStage
        guard !appearedTokens.contains(token) else {
            lock.unlock()
            if !isPresent { stage?.notePresence(token) }
            return false
        }
        appearedTokens.insert(token)
        let shouldFire = firesEffects
        lock.unlock()
        if let stage, stage.isStaging {
            stage.noteUndo { [self, isPresent] in
                lock.lock()
                appearedTokens.remove(token)
                if !isPresent { currentRenderTokens.remove(token) }
                lock.unlock()
            }
        }
        // In snapshot mode the view is still recorded as appeared
        // (so repeat renders behave), but the action is suppressed.
        if shouldFire {
            if let stage { stage.perform(as: .appearance, action) } else { action() }
        }
        return shouldFire
    }

    /// Checks if a view has appeared before.
    package func hasAppeared(token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return appearedTokens.contains(token)
    }

    /// Removes the appeared state for a token so the next `recordAppear`
    /// treats it as a fresh first appearance.
    package func resetAppearance(token: String) {
        lock.lock()
        appearedTokens.remove(token)
        lock.unlock()
    }

    /// Registers a callback for when a view with the given token disappears.
    ///
    /// - Parameters:
    ///   - token: Unique identifier for the view.
    ///   - action: The onDisappear action to execute.
    package func registerDisappear(token: String, action: @escaping () -> Void) {
        lock.lock()
        let isNew = disappearCallbacks.updateValue(action, forKey: token) == nil
        let stage = _effectStage
        lock.unlock()
        // Registered first by a drawing the walk then discards, it would stay
        // for a view the kept drawing may never draw. One registered on an
        // earlier frame stays: the kept drawing's registration replaces it.
        guard isNew, let stage, stage.isStaging else { return }
        stage.noteUndo { [self] in
            lock.lock()
            disappearCallbacks.removeValue(forKey: token)
            lock.unlock()
        }
    }

    /// Unregisters the disappear callback for the given token.
    func unregisterDisappear(token: String) {
        lock.lock()
        defer { lock.unlock() }
        disappearCallbacks.removeValue(forKey: token)
    }

    /// Starts an async task associated with a lifecycle token.
    ///
    /// If a task already exists for the token, it is cancelled first.
    ///
    /// - Parameters:
    ///   - token: Unique identifier for the view.
    ///   - priority: The task priority.
    ///   - name: The task's name, where the runtime names tasks (macOS 26,
    ///     and Swift 6.2's runtime elsewhere), or `nil` for none.
    ///   - operation: The async operation to execute. It runs on ITS OWN
    ///     isolation: a closure written at a `@MainActor` call site inherits
    ///     that and runs on the main actor, while a value forwarded from
    ///     elsewhere (what `TaskModifier` hands over) keeps whatever isolation
    ///     the app gave it.
    package func startTask(
        token: String,
        priority: TaskPriority,
        name: String? = nil,
        identity: ViewIdentity? = nil,
        @_inheritActorContext operation: sending @escaping @isolated(any) @Sendable () async ->
            Void
    ) {
        // Inside a drawing the walk may still discard, the task starts once
        // the drawing is kept (``EffectStage``): a discarded drawing's task
        // never starts, and the drawing made in its place starts its own.
        if let stage = effectStage, stage.isStaging {
            stage.perform(as: .appearance) { [self] in
                startTaskNow(token: token, priority: priority, name: name, identity: identity, operation: operation)
            }
            return
        }
        startTaskNow(token: token, priority: priority, name: name, identity: identity, operation: operation)
    }

    /// ``startTask(token:priority:name:operation:)``'s work, done now.
    private func startTaskNow(
        token: String,
        priority: TaskPriority,
        name: String?,
        identity: ViewIdentity?,
        operation: @escaping @isolated(any) @Sendable () async -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        // Snapshot renders don't start tasks — there's no run loop to
        // observe their effects and no disappear pass to cancel them.
        guard firesEffects else { return }
        tasks[token]?.cancel()
        // Started ON THE OPERATION'S OWN ISOLATION: the `@isolated(any)` value
        // carries it, and `Task.init` honours it with no hop. For a closure
        // written in a view body that is the main actor, so
        // `results = await search(query)` — the example this framework's own
        // documentation gives — is a safe `@State` write; running it
        // nonisolated (the behaviour before `.task` was isolated at all) made
        // that same line an off-main write racing the render loop's reads.
        // Pinning it to `@MainActor` here instead — the behaviour in between —
        // was safe but left an app no way to say "not on the main actor",
        // which the isolation-carrying parameter now allows.
        // As dispatched from the view the task belongs to, which a `Task`
        // carries (`StateRegistration.dispatchingIdentity`).
        StateRegistration.dispatching(from: identity) {
            if let name, #available(macOS 26, *) {
                tasks[token] = Task(name: name, priority: priority, operation: operation)
            } else {
                tasks[token] = Task(priority: priority, operation: operation)
            }
        }
    }

    /// Cancels and removes the task associated with the given token.
    package func cancelTask(token: String) {
        lock.lock()
        tasks[token]?.cancel()
        tasks.removeValue(forKey: token)
        lock.unlock()
    }

    /// Resets all lifecycle state.
    ///
    /// Cancels all running tasks, clears all callbacks and tracking state.
    package func reset() {
        lock.lock()
        appearedTokens.removeAll()
        visibleTokens.removeAll()
        currentRenderTokens.removeAll()
        disappearCallbacks.removeAll()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        lock.unlock()
    }
}

// MARK: - TUI Context

/// Central dependency container for TUI runtime services.
///
/// `TUIContext` bundles all framework-internal services into a single
/// object owned by `AppRunner`. It is threaded through `RenderContext`
/// so that view modifiers can access services during rendering.
///
/// ## Services
///
/// - ``lifecycle``: View lifecycle tracking (appear/disappear/task)
/// - ``keyEventDispatcher``: Key event handler registration and dispatch
/// - ``preferences``: Preference value collection during rendering
/// - ``stateStorage``: Persistent `@State` value storage indexed by view identity
///
/// ## Usage
///
/// View modifiers access services through `RenderContext.environment`:
///
/// ```swift
/// extension MyModifier: Renderable {
///     func renderToBuffer(context: RenderContext) -> FrameBuffer {
///         context.environment.keyEventDispatcher!.addHandler { event in
///             // handle key
///         }
///         return TUI.renderToBuffer(content, context: context)
///     }
/// }
/// ```
package final class TUIContext: @unchecked Sendable {
    /// Semantic keyboard-shortcut registry (default / cancel actions),
    /// re-populated each render pass by buttons carrying a
    /// ``KeyboardShortcut`` and consulted by the input chain.
    package let keyboardShortcuts = KeyboardShortcutRegistry()

    /// View lifecycle tracking (appear, disappear, task management).
    package let lifecycle: LifecycleManager

    /// Key event handler registration and dispatch.
    package let keyEventDispatcher: KeyEventDispatcher

    /// Mouse event handler registration and hit-test dispatch.
    package let mouseEventDispatcher: MouseEventDispatcher

    /// The images this app has transmitted to the terminal, and the only
    /// thing that deletes one.
    ///
    /// A plain stored property with no init parameter, unlike its neighbours:
    /// nothing needs to substitute one, and an image store shared between two
    /// contexts would delete one context's images out from under the other.
    package let terminalImageStore = TerminalImageStore()

    /// The objects the app's optional modules keep for it, one of each type —
    /// the URL image cache, say, which this module cannot name
    /// (``AppScopedObjects``).
    package let appScopedObjects = AppScopedObjects()

    /// The help text a frame may show, and how it became the candidate.
    ///
    /// A plain stored property with no init parameter, like
    /// ``terminalImageStore``: nothing needs to substitute one, and there is no
    /// sensible meaning to two contexts sharing a tooltip.
    package let tooltipState = TooltipState()

    /// The modifier keys held, as a terminal speaking the kitty keyboard
    /// protocol reports them, and the views listening for them
    /// (`onModifierKeysChanged`, `modifierKeyAlternate`). Kept by the key
    /// dispatcher, whose per-walk clear clears its listeners too.
    package var modifierKeys: ModifierKeyMonitor { keyEventDispatcher.modifierKeys }

    /// The values a `copyable` or `cuttable` view last put on the clipboard,
    /// beside the text the clipboard got — so a paste in this app can have the
    /// values back. Stored as ``tooltipState`` is, and for the same reasons.
    package let typedClipboard = TypedClipboard()

    /// Where this app's copies go — the terminal by OSC 52, this machine's
    /// clipboard when the user is at this machine, or nowhere, said so in the
    /// status bar — and the OSC 52 writes owed to the terminal. See
    /// ``ClipboardWriter``.
    ///
    /// This machine's clipboard behind it is the one the context was made
    /// with (``init(clipboard:urlOpener:appState:)``): the app's run loop passes the system's,
    /// and every other context keeps its copies in memory.
    ///
    /// Settable, unlike its neighbours, so a test can hand a context a writer
    /// with its own answers to where the terminal is.
    package var clipboardWriter: ClipboardWriter { get { _clipboardWriter } set { _clipboardWriter = newValue } }

    /// ``clipboardWriter``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _clipboardWriter: ClipboardWriter {
        didSet { _clipboardAccess = ClipboardAccess(writer: _clipboardWriter) }
    }

    /// TUI's own selection of what is drawn — the one a drag that no
    /// control uses makes. See ``ScreenSelection``.
    package let screenSelection = ScreenSelection()

    /// The terminal's bell, rung when a control turns input away, and the
    /// `BEL` owed to the terminal at the next frame. See ``TerminalBell``.
    /// Its ring asks this context's render state for the frame.
    package let terminalBell: TerminalBell

    /// The keys to press once the frame being drawn is on the screen — a menu
    /// bar's item's key (``KeysAfterFrame``). Pressing one asks this
    /// context's render state for the frame.
    package let keysAfterFrame: KeysAfterFrame

    /// ``clipboardWriter`` as the environment hands it to controls, built once
    /// per writer rather than once per frame.
    package var clipboardAccess: ClipboardAccess { _clipboardAccess }

    /// ``clipboardAccess``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private lazy var _clipboardAccess = ClipboardAccess(writer: _clipboardWriter)

    /// This machine's URL opener, for an ``OpenURLAction`` that defers to the
    /// system: the one the context was made with (``init(clipboard:urlOpener:appState:)``).
    /// The app's run loop passes the system's; every other context's keeps
    /// what it is handed in memory and launches nothing.
    package let urlOpener: any URLOpenerBackend

    /// App-wide drag-and-drop state (active drag + per-frame drop targets).
    package let dragAndDropSession: DragAndDropSession

    /// Preference value collection during rendering.
    package let preferences: PreferenceStorage

    /// The scene's operational state, published to `\.scenePhase` each frame.
    ///
    /// Owned here rather than by a view because only the run loop knows it:
    /// the one transition a terminal can report is suspend/resume, which the
    /// loop handles between frames. See ``ScenePhase``.
    package var scenePhase: ScenePhase { get { _scenePhase } set { _scenePhase = newValue } }

    /// ``scenePhase``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _scenePhase: ScenePhase = .active

    /// What the terminal reports about the keyboard, published to
    /// `\.keyboardReporting`. Set once, by the run loop, from the startup
    /// negotiation of the kitty keyboard protocol; ``KeyboardReporting/legacy``
    /// until then, and for a context with no terminal behind it.
    package var keyboardReporting: KeyboardReporting { get { _keyboardReporting } set { _keyboardReporting = newValue } }

    /// ``keyboardReporting``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _keyboardReporting = KeyboardReporting.legacy

    /// What the terminal does outside its grid that an app can ask for — the
    /// pointer's shape, a progress bar, a notification — published to
    /// `\.terminalFeatures`. Set by the app runner from the terminal it
    /// identified at startup, and by the render loop each frame for whether
    /// the progress bar shows, which under tmux follows the clients attached;
    /// ``TerminalFeatures/none`` until then, and for a context with no
    /// terminal behind it.
    package var terminalFeatures: TerminalFeatures { get { _terminalFeatures } set { _terminalFeatures = newValue } }

    /// ``terminalFeatures``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _terminalFeatures = TerminalFeatures.none

    /// What the terminal can do, feature by feature, published to
    /// `\.terminalCapabilities`. Set by the app runner at launch from TUI's
    /// tables and the terminal's answers, by the render loop when whether the
    /// progress bar shows changes, and by the run loop when a key shows a
    /// feature (``observeTerminalInput(_:)``); every feature undetermined until
    /// then, and for a context with no terminal behind it.
    package var terminalCapabilities: TerminalCapabilities {
        get { _terminalCapabilities }
        set { _terminalCapabilities = newValue }
    }

    /// ``terminalCapabilities``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _terminalCapabilities = TerminalCapabilities.nothingKnown

    /// Learns what `event`, a key read from the terminal, shows of it
    /// (``TerminalCapabilities/observing(_:)``).
    /// - Returns: Whether the capabilities changed, so that a frame shows it.
    package func observeTerminalInput(_ event: KeyEvent) -> Bool {
        guard let learnt = _terminalCapabilities.observing(event) else { return false }
        _terminalCapabilities = learnt
        return true
    }

    /// The app's undo and redo keys, as the scene set them
    /// (`Scene.undoShortcuts(_:)`): published by the render loop each frame,
    /// read by the input chain and the status bar between frames.
    package let undoKeys = AppUndoKeys()

    /// The app's undo manager, published to `\.undoManager`. Made by the run
    /// loop, on the main actor, which `UndoManager` is isolated to and this
    /// context's initialiser is not; `nil` until then, and for a context with
    /// no app behind it, which is SwiftUI's answer for "a context that doesn't
    /// support undo and redo operations".
    package var undoManager: UndoManager? { get { _undoManager } set { _undoManager = newValue } }

    /// ``undoManager``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _undoManager: UndoManager?

    /// The undo steps of text controls that have gone away, which every frame
    /// takes out of ``undoManager`` as it begins (`RenderLoop.beginRenderPass()`).
    package let departedUndoSteps = DepartedUndoSteps()

    /// The app's render state: whether a frame is owed, the transaction the
    /// change behind it was made under, the clocks that ticked, and an exit
    /// asked for. The app's run loop polls it, and the frame requests the
    /// app's views make reach it — a `@State` write and an `@Observable`
    /// change through the render cache's link, which is pointed at it here.
    ///
    /// One per context, so one per app: two apps in one process — two tests
    /// running at once — never draw each other's change under the other's
    /// transaction.
    package let appState: AppState

    /// The app's top-level `dismiss()`: asks ``appState`` to exit, so it exits
    /// this app, wherever it is called from. What `\.dismiss` holds at the
    /// top of every frame's environment (`applyRuntimeServices(from:)`), until
    /// a presentation puts its own below; one action for the context's life,
    /// so it is equal from frame to frame and keeps the memos below it on.
    package let exitAction: DismissAction

    /// Persistent `@State` value storage indexed by `ViewIdentity`.
    package let stateStorage: StateStorage

    /// Cache for memoized subtree rendering results.
    ///
    /// Stores rendered ``FrameBuffer`` output for ``EquatableView`` instances,
    /// keyed by `ViewIdentity`. Cleared on every `@State` change; entries
    /// for removed views are garbage-collected at the end of each render pass.
    package let renderCache: RenderCache

    /// Closure that synthesises a key event through the full
    /// ``InputHandler`` 5-layer dispatch chain (text-input,
    /// status-bar items, view handlers, focus system, default
    /// quit / theme / appearance bindings).
    ///
    /// Populated by ``AppRunner/run()`` immediately after the
    /// `InputHandler` is constructed; consumed by the
    /// ``StatusBar`` mouse handler so a click on an item that
    /// only has a `triggerKey` (no inline action) — e.g. the
    /// "Back" (ESC), "Quit" (q), or "Show" (Enter) system
    /// entries — fires through the same chain that a physical
    /// keypress would, including ``InputHandler``'s Layer 4
    /// quit binding which only ``AppRunner`` knows how to
    /// invoke.
    ///
    /// `var` rather than `let` because ``InputHandler`` needs
    /// to reference ``TUIContext``-owned services at
    /// construction time, so the closure can only be wired up
    /// after both objects exist.
    package var synthesizeKeyEvent: (@MainActor (KeyEvent) -> Void)? { get { _synthesizeKeyEvent } set { _synthesizeKeyEvent = newValue } }

    /// ``synthesizeKeyEvent``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _synthesizeKeyEvent: (@MainActor (KeyEvent) -> Void)?

    /// Creates a new TUI context with fresh instances of all services.
    ///
    /// Each context gets its OWN `RenderCache` — there is no process-wide shared
    /// instance. The app's run loop creates one context and reuses it across
    /// frames, so its cache still persists frame-to-frame; meanwhile every other
    /// context (notably each test's) is fully isolated, which is what keeps
    /// parallel render tests from contaminating one another's cache.
    ///
    /// - Parameters:
    ///   - clipboard: This machine's clipboard, behind the context's
    ///     ``clipboardWriter``. The app's run loop passes the system's
    ///     (`SystemClipboard.Backend`); every other context — a headless run's,
    ///     a test's — keeps its copies in memory, and never touches the user's
    ///     pasteboard.
    ///   - urlOpener: This machine's URL opener (``urlOpener``). The app's run
    ///     loop passes the system's (`SystemURLOpener`); every other context
    ///     keeps what it is handed in memory, and never launches a browser.
    ///   - appState: The app's render state (``appState``): a fresh one unless
    ///     the caller holds one the context's frame requests must reach.
    package init(
        clipboard: any ClipboardBackend = InMemoryClipboard(),
        urlOpener: any URLOpenerBackend = InMemoryURLOpener(),
        appState: AppState = AppState()
    ) {
        self.appState = appState
        self.exitAction = DismissAction(box: DismissAction.Box { [appState] in appState.requestExit() })
        self.terminalBell = TerminalBell(requestFrame: { [appState] in appState.setNeedsRender() })
        self.keysAfterFrame = KeysAfterFrame(requestFrame: { [appState] in appState.setNeedsRender() })
        self._clipboardWriter = ClipboardWriter(
            system: clipboard, requestFrame: { [appState] in appState.setNeedsRender() })
        self.urlOpener = urlOpener
        self.lifecycle = LifecycleManager()
        self.keyEventDispatcher = KeyEventDispatcher()
        self.mouseEventDispatcher = MouseEventDispatcher()
        self.dragAndDropSession = DragAndDropSession()
        self.stateStorage = StateStorage()
        // A drawing the walk may still discard holds back its views' appearances
        // and tasks on the same stage as their other effects, so they run in
        // the order they were made.
        self.lifecycle.effectStage = self.stateStorage.effectStage
        // Drop targeting hit-tests the dispatcher's composited regions; the
        // dispatcher stamps the session with absolute cursor positions.
        self.dragAndDropSession.dispatcher = self.mouseEventDispatcher
        self.mouseEventDispatcher.dragAndDropSession = self.dragAndDropSession
        // The pointer moving is what ends a tooltip held through the status
        // bar's reflow (`TooltipState.held`).
        self.mouseEventDispatcher.tooltipState = self.tooltipState
        self.preferences = PreferenceStorage()
        self.renderCache = RenderCache(valueHashPlans: .tuikit())
        // Point the state storage at this context's cache so a `@State` change
        // (``StateBox/value`` didSet) invalidates the right cache. Without the
        // shared singleton there is no implicit common target — the owner must
        // wire the two together.
        self.stateStorage.renderCache = self.renderCache
        // And the cache's link at this app's render state, so the frame a
        // write asks for — under the transaction the write was made in — is
        // asked of this app and of no other.
        self.renderCache.link.requestFrames(from: appState)
        // And the cache at the dispatcher's interned handler ids: a stored
        // buffer carries them in its regions, so the two prune together.
        self.renderCache.internedIDTable = self.mouseEventDispatcher
        // And the drag session at the cache, so a view lifted out of its place
        // — or landing back in it — is not served as it was stored.
        self.dragAndDropSession.renderInvalidation = self.renderCache.link
        wireScreenSelection()
    }

    /// Creates a new TUI context with the given services.
    ///
    /// Useful for testing where you want to inject mock services.
    ///
    /// - Parameters:
    ///   - lifecycle: The lifecycle manager to use.
    ///   - keyEventDispatcher: The key event dispatcher to use.
    ///   - preferences: The preference storage to use.
    ///   - stateStorage: The state storage to use.
    ///   - renderCache: The render cache to use (defaults to a fresh, isolated cache).
    ///   - appState: The render state the context's frame requests reach
    ///     (defaults to a fresh one).
    package init(
        lifecycle: LifecycleManager,
        keyEventDispatcher: KeyEventDispatcher,
        mouseEventDispatcher: MouseEventDispatcher = MouseEventDispatcher(),
        preferences: PreferenceStorage,
        stateStorage: StateStorage = StateStorage(),
        renderCache: RenderCache = RenderCache(valueHashPlans: .tuikit()),
        appState: AppState = AppState()
    ) {
        self.appState = appState
        self.exitAction = DismissAction(box: DismissAction.Box { [appState] in appState.requestExit() })
        self.terminalBell = TerminalBell(requestFrame: { [appState] in appState.setNeedsRender() })
        self.keysAfterFrame = KeysAfterFrame(requestFrame: { [appState] in appState.setNeedsRender() })
        // A snapshot's or a test's: its copies and URLs stay in memory (see
        // init(clipboard:urlOpener:appState:)).
        self._clipboardWriter = ClipboardWriter(
            system: InMemoryClipboard(), requestFrame: { [appState] in appState.setNeedsRender() })
        self.urlOpener = InMemoryURLOpener()
        self.lifecycle = lifecycle
        self.keyEventDispatcher = keyEventDispatcher
        self.mouseEventDispatcher = mouseEventDispatcher
        self.dragAndDropSession = DragAndDropSession()
        // See init(): drop targeting hit-tests the dispatcher's regions.
        self.dragAndDropSession.dispatcher = self.mouseEventDispatcher
        self.mouseEventDispatcher.dragAndDropSession = self.dragAndDropSession
        // See init(): the pointer moving ends a tooltip held through a reflow.
        self.mouseEventDispatcher.tooltipState = self.tooltipState
        self.preferences = preferences
        self.stateStorage = stateStorage
        // See init(clipboard:urlOpener:appState:): one stage for every effect.
        self.lifecycle.effectStage = stateStorage.effectStage
        self.renderCache = renderCache
        // See init(): wire state-change invalidation to this context's cache,
        // and the cache's frame requests to this context's render state.
        self.stateStorage.renderCache = self.renderCache
        self.renderCache.link.requestFrames(from: appState)
        // See init(): and the interned handler ids, which prune with it.
        self.renderCache.internedIDTable = self.mouseEventDispatcher
        // See init(): and the drag session, whose carried view draws as gone.
        self.dragAndDropSession.renderInvalidation = self.renderCache.link
        wireScreenSelection()
    }

    /// Points the dispatcher at the screen selection, which its drags make, and
    /// the selection at the clipboard writer, which its copies go through —
    /// weakly, as the context owns all three.
    private func wireScreenSelection() {
        mouseEventDispatcher.screenSelection = screenSelection
        screenSelection.copy = { [weak self] text, representations in
            // Read when the copy is made: a test may hand the context a writer.
            guard let writer = self?.clipboardWriter else { return }
            MainActor.assumeIsolated {
                _ = writer.write(text, representations: representations, announcingSuccess: true)
            }
        }
    }
}
