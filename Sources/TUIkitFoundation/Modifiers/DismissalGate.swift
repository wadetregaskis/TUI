//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissalGate.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The gate a presenter offers

/// What a presenter's own ways out — Escape, an outside click, its status-bar
/// item — go through, so content that wants to ask first can.
///
/// A presenter keeps one for the life of the presentation (an object compared
/// by identity, so the environment value is the same from frame to frame and
/// the memos inside the content keep working), clears ``interceptor`` before
/// each render of its content, and the content's
/// `dismissalConfirmationDialog`, if it wants to ask, sets it again.
@MainActor
package final class DismissalGate: Equatable {
    /// Asks before dismissing; given the dismissal to run if the answer is
    /// yes.
    package var interceptor: ((@escaping () -> Void) -> Void)?

    /// The cancel button the content drew last frame — a button with
    /// `.keyboardShortcut(.cancelAction)`, as a `.cancellationAction` toolbar
    /// item's is: its action, which the presenter's Escape runs in place of
    /// its own dismissal while nothing asks first, and whether a held
    /// Escape's repeats run it again (``escape(isRepeat:_:)``). `nil` when the
    /// content drew none.
    var cancelButton: KeyboardShortcutRegistry.Entry?

    /// Dismisses through the interceptor, if one asked to be asked.
    func dismiss(_ proceed: @escaping () -> Void) {
        if let interceptor {
            interceptor(proceed)
        } else {
            proceed()
        }
    }

    /// The presenter's Escape: the content's cancel button, if it drew one,
    /// as macOS presses a sheet's cancel button on Escape — its action is the
    /// app's, which dismisses or not as it says — and otherwise the
    /// presentation's own dismissal, through the interceptor.
    ///
    /// The presenter's Escape comes before the cancel button's on the way
    /// down the key layers (its status-bar item and key handler are layers 1
    /// and 2, a `.keyboardShortcut` layer 3.5), so it is here the button is
    /// pressed or not: without it a sheet's
    /// `ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.discardDraft(); dismiss() } }`
    /// was dismissed on Escape with the draft kept.
    ///
    /// Except while a `dismissalConfirmationDialog` would ask (``interceptor``):
    /// then Escape asks, and the button waits. Its usual action discards and
    /// then calls `dismiss()`, which asks too — but only once the action has
    /// run, so a press would lose the unsaved changes before the question the
    /// app put in the way of closing was asked.
    ///
    /// A held Escape's repeat (`isRepeat`, which only a terminal speaking the
    /// kitty keyboard protocol tells from a press) presses the button again
    /// only if the button repeats — `.buttonRepeatBehavior(.enabled)` — as
    /// its own `.keyboardShortcut` would: otherwise it is taken and runs
    /// nothing, so a Cancel that keeps the sheet up runs once per press, not
    /// once per repeat.
    package func escape(isRepeat: Bool, _ proceed: @escaping () -> Void) {
        guard escapePressesCancelButton, let cancelButton else {
            dismiss(proceed)
            return
        }
        if isRepeat, !cancelButton.repeats { return }
        cancelButton.action()
    }

    /// Whether the presenter's Escape presses the content's cancel button
    /// this frame (``escape(isRepeat:_:)``), rather than dismissing: what the
    /// status bar calls it by — "cancel", not "dismiss", for a Cancel that may
    /// keep the presentation up.
    package var escapePressesCancelButton: Bool {
        interceptor == nil && cancelButton != nil
    }

    /// Whether a held Escape's repeats do what its press did: not while it
    /// presses a cancel button that does not repeat (``escape(isRepeat:_:)``).
    package var escapeRepeats: Bool {
        guard escapePressesCancelButton, let cancelButton else { return true }
        return cancelButton.repeats
    }

    /// What the status bar calls the presenter's Escape: `dismissal`, the
    /// presenter's own name for it, unless Escape presses the content's
    /// cancel button.
    package func escapeLabel(dismissal: LocalizationKey.StatusBar) -> String {
        LocalizationService.shared.string(for: escapePressesCancelButton ? .cancel : dismissal)
    }

    /// Draws the presented content with `render`, and takes the cancel button
    /// it registered, if any, for ``escape(isRepeat:_:)``. A measurement
    /// registers nothing, and takes nothing.
    package func drawingContent<Result>(context: RenderContext, _ render: () -> Result) -> Result {
        guard !context.isMeasuring, let registry = context.environment.keyboardShortcutRegistry else {
            return render()
        }
        let mark = registry.registrationCount
        let result = render()
        cancelButton = registry.entry(for: .cancelAction, registeredAfter: mark)
        return result
    }

    package nonisolated static func == (lhs: DismissalGate, rhs: DismissalGate) -> Bool { lhs === rhs }
}

private struct DismissalGateKey: EnvironmentKey {
    static let defaultValue: DismissalGate? = nil
}

extension EnvironmentValues {
    /// The gate the nearest presentation's ways out go through — `nil` at the
    /// top level, where the quit key is the way out.
    package var dismissalGate: DismissalGate? {
        get { self[DismissalGateKey.self] }
        set { self[DismissalGateKey.self] = newValue }
    }
}

/// The presentation's gate, kept in a manual `StateStorage` box at the
/// presenter's identity, with last frame's interceptor and cancel button
/// cleared: the content renders next and sets them again if it still has them.
@MainActor
package func presentationDismissalGate(context: RenderContext, propertyIndex: Int) -> DismissalGate {
    let key = StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex)
    let gate: StateBox<DismissalGate>? = context.stateStorage?.storage(for: key, default: DismissalGate())
    let resolved = gate?.value ?? DismissalGate()
    resolved.interceptor = nil
    resolved.cancelButton = nil
    return resolved
}
