//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissalConfirmation.swift
//
//  `dismissalConfirmationDialog`: a confirmation dialog in the way of closing
//  a presentation, or of quitting, while there is something to lose.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Presents a confirmation dialog when a dismiss action has been
    /// triggered. Mirrors SwiftUI's
    /// `dismissalConfirmationDialog(_:shouldPresent:actions:message:)`.
    ///
    /// Apply it to the content of a sheet, cover or popover — or to an app's
    /// top-level content. While `shouldPresent` is `true`, the reader's own
    /// ways out ask first: Escape and an outside click on a presentation, and
    /// the quit key at the top level.
    ///
    /// ```swift
    /// MessageEditor(message: $message)
    ///     .dismissalConfirmationDialog(
    ///         "Save this message as a draft?",
    ///         shouldPresent: message.hasUnsavedChanges
    ///     ) {
    ///         Button("Save") { message.save() }
    ///         Button("Don't Save", role: .destructive) { message.discard() }
    ///     } message: {
    ///         Text("This message has not been sent.")
    ///     }
    /// ```
    ///
    /// Every action closes the dialog after it runs. A `.cancel`-role button —
    /// or the standard Cancel the dialog adds when none is given, which Escape
    /// also chooses — keeps the presentation; any other action lets the
    /// dismissal go ahead once it has run.
    ///
    /// An app's own `@Environment(\.dismiss)` call is not intercepted: it is
    /// the app's decision, made in code, and goes through as written.
    ///
    /// A string **literal** binds here, so the title is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    ///   - message: The dialog's message.
    public func dismissalConfirmationDialog<A: View, M: View>(
        _ titleKey: LocalizedStringKey, shouldPresent: Bool,
        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M
    ) -> some View {
        _DismissalConfirmationModifier(
            content: self, title: titleKey.localized, shouldPresent: shouldPresent,
            actions: actions(), message: message())
    }

    /// Presents a confirmation dialog, titled as written, when a dismiss
    /// action has been triggered.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    ///   - message: The dialog's message.
    @_disfavoredOverload
    public func dismissalConfirmationDialog<S: StringProtocol, A: View, M: View>(
        _ title: S, shouldPresent: Bool,
        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M
    ) -> some View {
        _DismissalConfirmationModifier(
            content: self, title: String(title), shouldPresent: shouldPresent,
            actions: actions(), message: message())
    }

    /// Presents a confirmation dialog, with a `Text` title, when a dismiss
    /// action has been triggered.
    ///
    /// The title is drawn as plain text, as every dialog title here is.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    ///   - message: The dialog's message.
    public func dismissalConfirmationDialog<A: View, M: View>(
        _ title: Text, shouldPresent: Bool,
        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M
    ) -> some View {
        _DismissalConfirmationModifier(
            content: self, title: title.content, shouldPresent: shouldPresent,
            actions: actions(), message: message())
    }

    /// Presents a confirmation dialog with no message when a dismiss action
    /// has been triggered. Mirrors SwiftUI's
    /// `dismissalConfirmationDialog(_:shouldPresent:actions:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    public func dismissalConfirmationDialog<A: View>(
        _ titleKey: LocalizedStringKey, shouldPresent: Bool, @ViewBuilder actions: () -> A
    ) -> some View {
        _DismissalConfirmationModifier<Self, A, EmptyView>(
            content: self, title: titleKey.localized, shouldPresent: shouldPresent,
            actions: actions(), message: nil)
    }

    /// Presents a confirmation dialog, titled as written and with no message,
    /// when a dismiss action has been triggered.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    @_disfavoredOverload
    public func dismissalConfirmationDialog<S: StringProtocol, A: View>(
        _ title: S, shouldPresent: Bool, @ViewBuilder actions: () -> A
    ) -> some View {
        _DismissalConfirmationModifier<Self, A, EmptyView>(
            content: self, title: String(title), shouldPresent: shouldPresent,
            actions: actions(), message: nil)
    }

    /// Presents a confirmation dialog, with a `Text` title and no message,
    /// when a dismiss action has been triggered.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - shouldPresent: Whether a dismissal should ask first.
    ///   - actions: The dialog's actions.
    public func dismissalConfirmationDialog<A: View>(
        _ title: Text, shouldPresent: Bool, @ViewBuilder actions: () -> A
    ) -> some View {
        _DismissalConfirmationModifier<Self, A, EmptyView>(
            content: self, title: title.content, shouldPresent: shouldPresent,
            actions: actions(), message: nil)
    }
}

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
final class DismissalGate: Equatable {
    /// Asks before dismissing; given the dismissal to run if the answer is
    /// yes.
    var interceptor: ((@escaping () -> Void) -> Void)?

    /// Dismisses through the interceptor, if one asked to be asked.
    func dismiss(_ proceed: @escaping () -> Void) {
        if let interceptor {
            interceptor(proceed)
        } else {
            proceed()
        }
    }

    nonisolated static func == (lhs: DismissalGate, rhs: DismissalGate) -> Bool { lhs === rhs }
}

private struct DismissalGateKey: EnvironmentKey {
    static let defaultValue: DismissalGate? = nil
}

extension EnvironmentValues {
    /// The gate the nearest presentation's ways out go through — `nil` at the
    /// top level, where the quit key is the way out.
    var dismissalGate: DismissalGate? {
        get { self[DismissalGateKey.self] }
        set { self[DismissalGateKey.self] = newValue }
    }
}

/// The presentation's gate, kept in a manual `StateStorage` box at the
/// presenter's identity, with last frame's interceptor cleared: the content
/// renders next and sets it again if it still wants to ask.
@MainActor
func presentationDismissalGate(context: RenderContext, propertyIndex: Int) -> DismissalGate {
    let key = StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex)
    let gate: StateBox<DismissalGate>? = context.stateStorage?.storage(for: key, default: DismissalGate())
    let resolved = gate?.value ?? DismissalGate()
    resolved.interceptor = nil
    return resolved
}

// MARK: - The modifier

/// The dismissal being held while the dialog asks about it.
@MainActor
final class PendingDismissal {
    var proceed: (() -> Void)?

    /// Lets the held dismissal go ahead.
    func run() {
        let proceed = proceed
        self.proceed = nil
        proceed?()
    }
}

struct _DismissalConfirmationModifier<Content: View, A: View, M: View>: View {
    let content: Content
    let title: String
    let shouldPresent: Bool
    let actions: A
    let message: M?

    @State private var isConfirming = false
    @State private var pending = PendingDismissal()

    var body: some View {
        let pending = pending
        let isConfirming = $isConfirming
        let ask: (@escaping () -> Void) -> Void = { proceed in
            pending.proceed = proceed
            isConfirming.wrappedValue = true
        }
        let dialogActions = _DismissalActions(actions: actions, pending: pending)
        // The registrar goes OUTSIDE the dialog's presenter, which draws the
        // content beneath an open dialog as an inert backdrop: registered from
        // in there, the quit key would lose its question while the question is
        // on screen.
        return _DismissalConfirmationRegistrar(
            content: dialog(isConfirming: isConfirming, actions: dialogActions),
            shouldPresent: shouldPresent, ask: ask)
    }

    /// The content with the dialog on it — with a message only when the app
    /// gave one, since an empty one would still keep a blank line.
    @ViewBuilder
    private func dialog(isConfirming: Binding<Bool>, actions: _DismissalActions<A>) -> some View {
        if let message {
            content.confirmationDialog(
                title, isPresented: isConfirming, titleVisibility: .visible,
                actions: { actions }, message: { message })
        } else {
            content.confirmationDialog(
                title, isPresented: isConfirming, titleVisibility: .visible, actions: { actions })
        }
    }
}

/// Offers `ask` to the nearest presentation's gate, or to the quit key at the
/// top level, on every frame `shouldPresent` holds.
struct _DismissalConfirmationRegistrar<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let shouldPresent: Bool
    let ask: (@escaping () -> Void) -> Void

    var body: Never {
        fatalError("_DismissalConfirmationRegistrar renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            // A per-frame registration: the gate is cleared before every render
            // of the content and the quit key's question before every walk, so
            // a served subtree would stop asking.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            if shouldPresent {
                if let gate = context.environment.dismissalGate {
                    gate.interceptor = ask
                } else {
                    context.environment.statusBar?.askBeforeQuitting(ask)
                }
            }
        }
        return TUIkit.renderToBuffer(content, context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - The dialog's actions

/// The app's actions, each letting the held dismissal go ahead once it has
/// run — except a `.cancel` one, which keeps the presentation. A standard
/// Cancel is added when the app gave none.
struct _DismissalActions<A: View>: View, ButtonProvider {
    let actions: A
    let pending: PendingDismissal

    var body: some View { actions }

    func extractButtons() -> [Button] {
        let pending = pending
        var buttons = alertActionButtons(from: actions).map { button in
            guard button.role != .cancel else { return button }
            return Button(button, action: {
                button.action()
                pending.run()
            })
        }
        if !buttons.contains(where: { $0.role == .cancel }) {
            buttons.append(
                Button(
                    LocalizationService.shared.string(for: LocalizationKey.Button.cancel),
                    role: .cancel, action: {}))
        }
        return buttons
    }
}

extension Button {
    /// `button`, running `action` instead of its own.
    init(_ button: Button, action: @escaping () -> Void) {
        self.label = button.label
        self.labelView = button.labelView
        self.action = action
        self.role = button.role
        self.focusID = button.focusID
        self.isDisabled = button.isDisabled
        self.isMenuTrigger = button.isMenuTrigger
    }
}
