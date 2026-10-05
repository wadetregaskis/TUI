//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifierKeyMonitor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Modifier Key Monitor

/// The modifier keys held now, as the terminal last reported them, and the
/// views that want to hear when they change.
///
/// Fed by the run loop from `TerminalInput.modifierKeys`, which only a terminal
/// speaking the kitty keyboard protocol sends — a modifier key pressed or
/// released on its own, or a lock key toggled. In a legacy encoding nothing
/// feeds it, so the state stays empty and nothing it holds ever fires; the
/// render loop does not even publish it there
/// (``KeyboardReporting/reportsModifierKeys``).
///
/// Its observers are registered per walk of the scene, as key handlers are,
/// and are asked when a report changes the state — between frames, like a key
/// handler, so every change reaches them, not only the ones a frame happens to
/// see.
///
/// `@unchecked Sendable` on the same footing as the other dispatchers
/// (`KeyEventDispatcher`, `MouseEventDispatcher`): touched only from the main
/// run loop, by the render pass and by input dispatch.
final class ModifierKeyMonitor: @unchecked Sendable {
    /// The modifier keys held, and Caps Lock if it is on.
    private(set) var current: EventModifiers = []

    /// One view's observer: what it masks the state to, and its action.
    private struct Observer {
        let mask: EventModifiers
        let action: (EventModifiers, EventModifiers) -> Void
    }

    /// This walk's observers, in render order.
    private var observers: [Observer] = []

    /// Whether the frame on screen drew something from ``current``, so a change
    /// needs a frame to show.
    private var isDrawnFrom = false

    init() {}

    /// Forgets the last walk's observers and drawing; the walk about to start
    /// registers its own.
    func beginSceneRender() {
        observers.removeAll()
        isDrawnFrom = false
    }

    /// Adds an observer for this walk, asked with the old and new state, both
    /// masked, whenever a report changes the state within `mask`.
    func observe(mask: EventModifiers, _ action: @escaping (EventModifiers, EventModifiers) -> Void) {
        observers.append(Observer(mask: mask, action: action))
    }

    /// Notes that this walk drew something from ``current``: a modifier key
    /// alternate.
    func noteDrawnFrom() {
        isDrawnFrom = true
    }

    /// The number of observers this walk registered, for tests.
    var observerCount: Int { observers.count }

    /// Takes a report from the terminal, tells each observer whose masked state
    /// it changes, and answers whether the screen needs a frame for it.
    ///
    /// - Returns: `true` when the state changed and the frame on screen drew
    ///   something from it. An observer's action asks for its own frame if it
    ///   changes state, as a key handler's does.
    @discardableResult
    func record(_ state: ModifierKeyState) -> Bool {
        let old = current
        let new = EventModifiers(state)
        guard new != old else { return false }
        current = new
        for observer in observers {
            let before = old.intersection(observer.mask)
            let after = new.intersection(observer.mask)
            if before != after { observer.action(before, after) }
        }
        return isDrawnFrom
    }
}

// MARK: - From a report

extension EventModifiers {
    /// The modifiers a terminal's modifier-key report says are held, and Caps
    /// Lock if it is on.
    init(_ state: ModifierKeyState) {
        var result: Self = []
        if state.shift { result.insert(.shift) }
        if state.control { result.insert(.control) }
        if state.option { result.insert(.option) }
        if state.command { result.insert(.command) }
        if state.capsLock { result.insert(.capsLock) }
        self = result
    }
}

// MARK: - Environment

private struct ModifierKeyMonitorKey: EnvironmentKey {
    static let defaultValue: ModifierKeyMonitor? = nil
}

extension EnvironmentValues {
    /// The app's modifier-key state, published only where the terminal reports
    /// modifier keys on their own; `nil` everywhere else, which is the answer
    /// "no modifier key is held, and none ever will be reported".
    var modifierKeyMonitor: ModifierKeyMonitor? {
        get { self[ModifierKeyMonitorKey.self] }
        set { self[ModifierKeyMonitorKey.self] = newValue }
    }
}
