//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnModifierKeysChangedModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - onModifierKeysChanged

extension View {
    /// Performs an action whenever the user presses or releases a hardware
    /// modifier key.
    ///
    /// If a mask is provided, updates will only occur when they involve a
    /// change in one of the keys included in the mask. The default mask
    /// includes all modifier keys.
    ///
    /// ```swift
    /// ContentView()
    ///     .onModifierKeysChanged(mask: .option) { old, new in
    ///         showsDetails = new.contains(.option)
    ///     }
    /// ```
    ///
    /// When the view first appears, and `initial` is `true`, the action runs
    /// if any of the masked keys are already held, with an empty old value.
    ///
    /// ## Where it works
    ///
    /// A terminal reports a modifier key pressed or released on its own only
    /// under the kitty keyboard protocol's "report all keys as escape codes"
    /// enhancement, which TUIkit turns on wherever the terminal answers its
    /// query. Read ``EnvironmentValues/terminalCapabilities``'
    /// ``TerminalCapabilities/Feature/modifierKeys`` to know: where it is not supported
    /// the action never runs, so offer another route to whatever it reveals.
    /// Where it is, Shift, Control, Option and Caps Lock are reported,
    /// and Command (⌘) on the macOS terminals that pass it through as the
    /// protocol's Super key; ``EventModifiers/numericPad`` is never part of
    /// the state.
    ///
    /// - Parameters:
    ///   - mask: A set of modifier keys controlling which keys to observe for
    ///     changes. The default mask includes all keys.
    ///   - initial: Whether the action runs with the state of the masked keys
    ///     when the view appears. If `false`, it waits for the state to
    ///     actually change.
    ///   - action: A closure to receive updates when modifier key press state
    ///     changes. The closure receives the old and new values as input.
    /// - Returns: A modified view that updates when hardware modifier keys
    ///   change.
    public func onModifierKeysChanged(
        mask: EventModifiers = .all, initial: Bool = true,
        _ action: @escaping (EventModifiers, EventModifiers) -> Void
    ) -> some View {
        OnModifierKeysChangedModifier(content: self, mask: mask, initial: initial, action: action)
    }
}

// MARK: - The modifier

/// The view behind ``View/onModifierKeysChanged(mask:initial:_:)``: registers
/// the action with the app's ``ModifierKeyMonitor`` for this walk, and runs it
/// once with the held keys when the view first appears.
struct OnModifierKeysChangedModifier<Content: View>: View {
    let content: Content
    let mask: EventModifiers
    let initial: Bool
    let action: (EventModifiers, EventModifiers) -> Void

    var body: Never {
        fatalError("OnModifierKeysChangedModifier renders via Renderable")
    }
}

extension OnModifierKeysChangedModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A render side effect, so never on a measure (a render-to-measure
        // ancestor would register and fire twice), and declared to a
        // value-memoizing ancestor so a served frame does not leave the
        // observer unregistered — the rule `OnChangeModifier` follows.
        guard !context.isMeasuring, let monitor = context.environment.modifierKeyMonitor else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        monitor.observe(mask: mask, action)

        // "When the view first appears": the first render at this identity
        // finds no record. The record is the onChange slot's kind, claimed
        // positionally per walk as `.onChange` claims its own.
        if let storage = context.stateStorage {
            let index = storage.nextOnChangeIndex(for: context.identity)
            let key = StateStorage.StateKey(identity: context.identity, propertyIndex: index)
            let appeared: Bool? = storage.trackedValue(for: key)
            if appeared == nil {
                let held = monitor.current.intersection(mask)
                // Held until the drawing is kept, where it may be drawn again
                // (`EffectStage`), and the appearance put back if it is not.
                if initial, !held.isEmpty {
                    let action = self.action
                    storage.effectStage.perform { action([], held) }
                }
                storage.setChangedTrackedValue(true, for: key)
            }
            storage.markActive(context.identity)
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension OnModifierKeysChangedModifier: Layoutable {
    /// Behaviour only: it measures as its content does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it.
extension OnModifierKeysChangedModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnModifierKeysChangedModifier: DrawsContentUnchanged {}

// MARK: - In a Form

/// A modifier-keys action written on a form row goes around the row the form
/// lays out, which keeps its place, as SwiftUI's form keeps a row under the
/// modifiers measured (`Tools/SwiftUIProbes/Form rows`).
extension OnModifierKeysChangedModifier: FormRowRewrapping {
    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        OnModifierKeysChangedModifier<V>(content: row, mask: mask, initial: initial, action: action)
    }
}
