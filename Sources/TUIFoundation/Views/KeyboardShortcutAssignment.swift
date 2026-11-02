//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutAssignment.swift
//
//  The claimable carrier `.keyboardShortcut` plants for a control, and the
//  environment entries that reach it and the registry. Split out of
//  `KeyboardShortcutRegistry.swift`, which had grown past the file-length
//  guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Assignment

/// The per-frame, claimable carrier ``View/keyboardShortcut(_:)-(KeyboardShortcut)``
/// plants in the environment.
///
/// A plain environment *value* would cascade to every button in the subtree —
/// `.keyboardShortcut(.defaultAction)` on a container would mark all of them.
/// A claimable box keeps SwiftUI's attach-to-one-control semantics: the first
/// button rendered under the modifier claims it (which is the wrapped button
/// itself when the modifier is attached directly, the only supported usage).
/// Main-loop-confined like the registry it feeds.
final class KeyboardShortcutAssignment {
    let shortcut: KeyboardShortcut

    /// Whether the control claiming it registers its action on the shortcut —
    /// `false` for a hint (``View/keyboardShortcutHint(_:)``), which a menu row
    /// prints and something else binds.
    let registers: Bool

    /// Who holds the claim, tracked SEPARATELY for measuring and for drawing.
    ///
    /// Keyed by identity rather than a bare "claimed" flag because a control
    /// asks more than once per frame: the measure pass needs the shortcut to
    /// size the space its hint occupies, and the render pass then needs it
    /// again to register the action. A one-shot claim would hand it to the
    /// measure and leave the render — the pass that actually registers — with
    /// nothing.
    ///
    /// Two latches rather than one because **a measure and a render need not lay
    /// the control out in the same place**, and one latch made the render's
    /// different identity look like a second control muscling in. A scrolling
    /// menu is exactly that: it measures its column bordered and hugging to
    /// decide whether it overflows, then draws the overflowing one inside a
    /// `ScrollView`, so every row's identity gains a component between the two
    /// passes. The measure claimed, the render was refused, and each row lost the
    /// key equivalent it had just been measured wide enough to print — silently,
    /// and only once the menu grew past its cap.
    private var measureClaimant: ViewIdentity?
    private var renderClaimant: ViewIdentity?

    /// How many value memos were recording where this carrier was last planted
    /// — `RenderContext.effectRecordingDepth` at that point in the walk.
    ///
    /// What it answers is whether the modifier sits INSIDE the memo that would
    /// store the control claiming it, which is what decides whether that
    /// control's registration can be replayed on a served frame. Stamped by
    /// `KeyboardShortcutModifier` on each plant rather than taken at init,
    /// because the carrier is built with the view value and the memo nesting is
    /// a property of where it is rendered.
    private var plantedAtEffectRecordingDepth = 0

    init(_ shortcut: KeyboardShortcut, registers: Bool = true) {
        self.shortcut = shortcut
        self.registers = registers
    }

    /// Records that this carrier was planted where `depth` value memos were
    /// recording.
    func planted(atEffectRecordingDepth depth: Int) {
        plantedAtEffectRecordingDepth = depth
    }

    /// Whether the memo now recording — the innermost of `recordingDepth` of
    /// them — is one this carrier was planted inside.
    ///
    /// Equal depths mean the modifier rendered below that memo's root, since a
    /// carrier is always an ancestor of the control claiming it and the depth
    /// only grows down the tree.
    func isPlanted(insideMemoAtDepth recordingDepth: Int) -> Bool {
        plantedAtEffectRecordingDepth == recordingDepth
    }

    /// Claims the assignment for the control at `identity`; returns nil if some
    /// other control already holds it for this kind of pass.
    ///
    /// - Parameters:
    ///   - identity: The claiming control's identity.
    ///   - isMeasuring: Whether this is a measuring pass (`RenderContext/isMeasuring`).
    ///     Measuring and drawing hold their claims independently — see the
    ///     latches above.
    func claim(by identity: ViewIdentity, isMeasuring: Bool) -> KeyboardShortcut? {
        if isMeasuring {
            if let measureClaimant, measureClaimant != identity { return nil }
            measureClaimant = identity
        } else {
            if let renderClaimant, renderClaimant != identity { return nil }
            renderClaimant = identity
        }
        return shortcut
    }
}

// MARK: - Environment

private struct KeyboardShortcutRegistryKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static var defaultValue: KeyboardShortcutRegistry? { nil }
}

private struct AssignedKeyboardShortcutKey: EnvironmentKey {
    static var defaultValue: KeyboardShortcutAssignment? { nil }
}

extension EnvironmentValues {
    /// The app's semantic-shortcut registry (nil outside a running app).
    package var keyboardShortcutRegistry: KeyboardShortcutRegistry? {
        get { self[KeyboardShortcutRegistryKey.self] }
        set { self[KeyboardShortcutRegistryKey.self] = newValue }
    }

    /// The shortcut assignment awaiting a control, planted by
    /// ``View/keyboardShortcut(_:)-(KeyboardShortcut)``.
    var assignedKeyboardShortcut: KeyboardShortcutAssignment? {
        get { self[AssignedKeyboardShortcutKey.self] }
        set { self[AssignedKeyboardShortcutKey.self] = newValue }
    }

    /// The keyboard shortcut buttons in this environment are triggered with,
    /// or `nil` where none was assigned to the view or an ancestor — SwiftUI's
    /// `\.keyboardShortcut`.
    ///
    /// For a button style whose look depends on its shortcut, as SwiftUI's
    /// documentation shows — here a view the style's body draws:
    ///
    /// ```swift
    /// struct DefaultMark: View {
    ///     @Environment(\.keyboardShortcut) private var shortcut
    ///
    ///     var body: some View {
    ///         Text(shortcut == .defaultAction ? "▸" : " ")
    ///     }
    /// }
    /// ```
    ///
    /// Read-only, as SwiftUI's is: ``View/keyboardShortcut(_:)-(KeyboardShortcut)`` is how one is
    /// assigned.
    public var keyboardShortcut: KeyboardShortcut? {
        assignedKeyboardShortcut?.shortcut
    }
}
