//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcutModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Keyboard Shortcut Modifier

/// Plants the claimable carrier ``View/keyboardShortcut(_:)`` offers to the
/// first control rendered under it.
///
/// A plain `environment(\.assignedKeyboardShortcut, …)` did this until the
/// registration became replayable, and it did two things this must not:
///
/// - **It stopped every memo below it storing.** `KeyboardShortcutAssignment` is
///   a per-frame claim box, not a value, so `RenderCache.noteAppliedEnvironment`
///   answered `.incomparable` for it and `EnvironmentModifier` — which is what
///   a plain `.environment(_:_:)` is, and the only thing that writes the flag
///   (Environment.swift:47 and :140) — set `hasUncomparableEnvironmentValue`
///   over the whole subtree. That is the right answer for a value a subtree
///   might draw from and nothing could compare; it is the wrong one here,
///   because the only reader is `Button`, and what a `Button` does with it —
///   register an action for the frame — is declared to the memo on its own
///   (`KeyboardShortcutRegistrar/declare(_:action:carrier:context:)`). So the
///   carrier is assigned straight into the environment, as `.focusSection`
///   assigns its section, and the subtree keeps its cache.
/// - **It could not say where it was planted.** A registration may be replayed
///   only when the modifier carrying it sits INSIDE the memo that would store
///   it; planted above one, the carrier is still there to be claimed on a frame
///   the memo serves, and the memo's key — made of the view value below the
///   modifier — cannot see the shortcut change. So each plant stamps the carrier
///   with `RenderContext.effectRecordingDepth`, the memo nesting in force where
///   it was planted, which is what the registrar compares its own against.
///
/// Both walks plant: a measure pass registers nothing, but it needs the
/// shortcut to reserve the width the hint prints in, and one carrier serves the
/// frame's measure and its render (see ``KeyboardShortcutAssignment``).
struct KeyboardShortcutModifier<Content: View>: View {
    /// The content view, whose first control claims the shortcut.
    let content: Content

    /// The claim box, built with the view value rather than per pass, so the
    /// measure and the render of one frame share it. `nil` for
    /// `.keyboardShortcut(nil)`, which leaves the environment as it found it.
    let assignment: KeyboardShortcutAssignment?

    var body: Never {
        fatalError("KeyboardShortcutModifier renders via Renderable")
    }

    /// The context the content renders or measures under: the carrier in the
    /// environment, stamped with the memo nesting it was planted at.
    private func planting(into context: RenderContext) -> RenderContext {
        guard let assignment else { return context }
        assignment.planted(atEffectRecordingDepth: context.effectRecordingDepth)
        // `\.keyboardShortcut` reads the carrier's shortcut, so anything below
        // may draw from it — a button style emphasising the default button —
        // and a memo below keys on its own view value, which cannot see the
        // shortcut change. So the SHORTCUT is noted as an environment
        // modifier notes its value (the carrier box itself compares by
        // identity and is new every frame), and a change drops what was
        // cached below. Both walks, as `EnvironmentModifier` does: the measure
        // memo has the same blind spot.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                assignment.shortcut, identity: context.identity,
                keyPath: \EnvironmentValues.keyboardShortcut, depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
        var planted = context
        planted.environment.assignedKeyboardShortcut = assignment
        planted.environmentApplicationDepth += 1
        return planted
    }
}

// MARK: - Renderable

extension KeyboardShortcutModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: planting(into: context))
    }
}

// MARK: - Layoutable

extension KeyboardShortcutModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged. Forwarding the
    /// measure keeps it off `measureChild`'s render-to-measure fallback and lets
    /// the wrapped view's flexibility propagate, exactly as `KeyEventModifier`
    /// does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: planting(into: context))
    }
}

// MARK: - Registration

/// The one registration a control's `.keyboardShortcut` makes, shared by the
/// live render and by a value memo replaying it — see `EffectJournal`.
enum KeyboardShortcutRegistrar {
    /// The journal kind of a keyboard-shortcut registration.
    static let kind = EffectJournal.Kind("keyboardShortcut")

    /// Claims the shortcut a `.keyboardShortcut` above offers, for the control
    /// rendering at `context`, and registers `action` for it — what every
    /// control with a primary action does with one: a `Button`, and a `Toggle`,
    /// as SwiftUI's shortcuts "activate a button or toggle".
    ///
    /// `.command` is not a key a terminal can report, so the shortcut is
    /// resolved to whatever stands in for it here (`.commandKey(_:)`) — the one
    /// place that both holds the environment and knows the shortcut. Resolved
    /// on EVERY pass, because a button hands it to its style so a menu row can
    /// print its hint (as AppKit draws a menu item's key equivalent), and a
    /// measure that didn't see the hint would size the menu too narrow for the
    /// render to fit it.
    ///
    /// Registration, though, is per-frame presence: the registry is emptied
    /// before every walk, so a control whose subtree was served from a value
    /// memo has to register again or its key equivalent is dead while it is
    /// still on screen. Declared to any value-memoizing ancestor either way
    /// (``declare(_:commandChord:repeats:action:carrier:context:)``).
    ///
    /// - Parameters:
    ///   - action: What the shortcut does: the control's primary action.
    ///   - isDisabled: Whether the control is disabled, which claims nothing.
    ///   - repeats: Whether a held key's repeats run the action again.
    ///   - context: Where the control renders.
    /// - Returns: The shortcut as resolved here, or `nil` where none was
    ///   offered, the control is disabled, or another control claimed it.
    @MainActor
    @discardableResult
    static func claim(
        action: @escaping () -> Void, isDisabled: Bool, repeats: Bool, context: RenderContext
    ) -> KeyboardShortcut? {
        guard !isDisabled, let assignment = context.environment.assignedKeyboardShortcut,
            let shortcut = assignment.claim(by: context.identity, isMeasuring: context.isMeasuring)
        else { return nil }
        let resolved = shortcut.resolved(commandKey: context.environment.commandKey)
        // The shortcut as written too, where the app asked for a real ⌘ to
        // fire it (`.keyboardShortcutsMatchCommand()`); `nil` by default.
        let commandChord = shortcut.commandChord(matching: context.environment.keyboardShortcutsMatchCommand)
        if let resolved, assignment.registers, !context.isMeasuring,
            register(resolved, commandChord: commandChord, repeats: repeats, action: action, context: context)
        {
            declare(
                resolved, commandChord: commandChord, repeats: repeats, action: action, carrier: assignment,
                context: context)
        }
        return resolved
    }

    /// Registers `action` for `shortcut` with `context`'s shortcut registry,
    /// reporting whether there was one.
    ///
    /// It looks the registry up in `context` rather than taking one, so a replay
    /// registers into the registry of the frame that serves it — the registry is
    /// emptied before every walk (`KeyboardShortcutRegistry.beginRenderPass`),
    /// and a `.dimmed()` subtree or the page beneath a modal is handed a
    /// throwaway one.
    ///
    /// - Parameter repeats: Whether a held key's repeats run the action again
    ///   (``ButtonRepeatBehavior/enabled``); see
    ///   ``KeyboardShortcutRegistry/register(_:commandChord:repeats:action:)``,
    ///   which takes `commandChord` too.
    /// - Returns: `false` outside a running app, where there is no registry and
    ///   nothing was registered — so the caller declares nothing either.
    @MainActor
    @discardableResult
    static func register(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, repeats: Bool = true,
        action: @escaping () -> Void, context: RenderContext
    ) -> Bool {
        guard let registry = context.environment.keyboardShortcutRegistry else { return false }
        registry.register(shortcut, commandChord: commandChord, repeats: repeats, action: action)
        return true
    }

    /// Tells a value-memoizing ancestor what this registration was: whether it
    /// must decline to store the subtree, or may store it and make the
    /// registration again on every hit.
    ///
    /// The registry is rebuilt every pass, so a served subtree that did not
    /// register again would leave its button's key equivalent dead while the
    /// button is still on screen — which is why this declared a plain render
    /// side effect, and why no memo holding a shortcut-bearing `Button` could
    /// store at all. Registering again reproduces it exactly: the last
    /// registration on a trigger wins, and a replay happens where the subtree
    /// would have rendered, so the frame ends with the same action on the same
    /// trigger whether the subtree rendered or was served.
    ///
    /// **Except when the carrier was planted above the memo**, which is the one
    /// case that keeps declining. The modifier offers its shortcut to the first
    /// control that renders under it, and on a served frame no control renders
    /// under it at all: the offer would stand unclaimed while the replay
    /// registered anyway, so a sibling rendered after the memo could take a
    /// shortcut that belongs to the button inside it. The key cannot rule that
    /// out either — it is made of the view value BELOW the modifier, so a
    /// changed shortcut above it is invisible.
    ///
    /// Nesting is answered conservatively: the comparison is against the
    /// INNERMOST recording memo, so a carrier planted between two nested memos
    /// declines for both, rather than only for the inner one it sits above.
    @MainActor
    static func declare(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, repeats: Bool = true,
        action: @escaping () -> Void, carrier: KeyboardShortcutAssignment, context: RenderContext
    ) {
        let tracker = context.environment.volatileReadTracker
        guard carrier.isPlanted(insideMemoAtDepth: context.effectRecordingDepth) else {
            tracker?.recordRenderSideEffect()
            return
        }
        tracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Built only while a memo records, so the live path allocates no second
        // closure. The RESOLVED shortcut is captured, not the declared one: the
        // stand-in for `.command` comes from the environment where the button
        // rendered, and a change to it clears the entry the ordinary way.
        journal.append(
            EffectJournal.Entry(
                kind: kind, channelToken: context.environment.keyChannelToken
            ) { replay in
                register(shortcut, commandChord: commandChord, repeats: repeats, action: action, context: replay)
            })
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension KeyboardShortcutModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content's context: the shortcut it plants (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { planting(into: context) }
}

/// A shortcut written on a form's button — `Button("Save") { … }
/// .keyboardShortcut(.defaultAction)` — goes around the row the form lays out,
/// which keeps its place, as SwiftUI's form keeps it (measured,
/// `Tools/SwiftUIProbes/Form rows`).
extension KeyboardShortcutModifier: FormRowRewrapping {
    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        KeyboardShortcutModifier<V>(content: row, assignment: assignment)
    }
}

// MARK: - Read by a View That Draws the Control Itself

/// A wrapper that binds a keyboard shortcut to the control inside it, read by
/// a view that takes the control out from under its modifiers to draw it
/// itself — an alert, whose actions are drawn as the alert's buttons — and
/// puts the shortcut back on it there.
@MainActor
package protocol KeyboardShortcutBinding {
    /// The shortcut bound: `nil` for `.keyboardShortcut(nil)`, which leaves a
    /// shortcut written further out in force, and for a hint, which binds
    /// nothing (``View/keyboardShortcutHint(_:)``).
    var boundShortcut: KeyboardShortcut? { get }
}

extension KeyboardShortcutModifier: KeyboardShortcutBinding {
    package var boundShortcut: KeyboardShortcut? {
        guard let assignment, assignment.registers else { return nil }
        return assignment.shortcut
    }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension KeyboardShortcutModifier: DrawsContentUnchanged {}
