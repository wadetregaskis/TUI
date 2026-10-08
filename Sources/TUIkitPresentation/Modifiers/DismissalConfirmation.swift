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
    /// top-level content. While `shouldPresent` is `true`, every way out asks
    /// first: Escape and an outside click on a presentation, the quit key at
    /// the top level, and the content's own `@Environment(\.dismiss)` call
    /// wherever it is. Escape asks even where the content draws a cancel
    /// button, which it presses otherwise: the question comes before the
    /// button's action runs, not after it, when its own `dismiss()` would ask.
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
    /// An app's own `dismiss()` asks as SwiftUI's does. `shouldPresent` is
    /// the value the view was last drawn with, so a Save button that saves
    /// and dismisses in one action asks about the changes it has just saved:
    /// let it dismiss once the saved state has been drawn, or answer the
    /// question with a button that dismisses. A pushed `NavigationStack`
    /// screen's Escape (back) and a signal do not ask.
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

// MARK: - The modifier

/// The dismissal being held while the dialog asks about it, and the content's
/// `\.dismiss`.
@MainActor
final class PendingDismissal {
    var proceed: (() -> Void)?

    /// The content's `\.dismiss`, kept for the modifier's life so the action
    /// the content reads is equal from frame to frame (decisions B37) — what
    /// it does is brought up to date on every render. Here rather than in a
    /// `@State` of its own: a `@State`'s initial value is made every time the
    /// modifier is, so that box was allocated on every frame and dropped;
    /// this one is made once, by the instance the modifier keeps.
    private(set) lazy var contentDismissal = DismissAction.Box()

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

    /// What `dismiss()` means outside this modifier: closing the presentation
    /// the content is in, or quitting at the top level.
    @Environment(\.dismiss) private var outerDismiss

    var body: some View {
        let pending = pending
        let isConfirming = $isConfirming
        let ask: (@escaping () -> Void) -> Void = { proceed in
            pending.proceed = proceed
            isConfirming.wrappedValue = true
        }
        // The app's own `dismiss()` asks too, as SwiftUI's does ("when a
        // dismiss action has been triggered"): while `shouldPresent` holds it
        // puts the question in the way, and the dismissal goes ahead on any
        // answer but Cancel; otherwise it dismisses as it would have.
        let outer = outerDismiss
        let shouldPresent = shouldPresent
        let contentDismissal = pending.contentDismissal
        contentDismissal.action = {
            if shouldPresent {
                ask { outer() }
            } else {
                outer()
            }
        }
        let dialogActions = _DismissalActions(actions: actions, pending: pending)
        // The registrar goes OUTSIDE the dialog's presenter, which draws the
        // content beneath an open dialog as an inert backdrop: registered from
        // in there, the quit key would lose its question while the question is
        // on screen. That is seen only where the app lets the quit key work
        // under a dialog, `.dialogPreventsAppTermination(false)`: by the
        // automatic rule (decisions B36) the question — its Cancel and at
        // least one other answer — holds the quit key while it is up.
        return _DismissalConfirmationRegistrar(
            content: dialog(
                content.environment(\.dismiss, DismissAction(box: contentDismissal)),
                isConfirming: isConfirming, actions: dialogActions),
            shouldPresent: shouldPresent, ask: ask)
    }

    /// `content` with the dialog on it — with a message only when the app
    /// gave one, since an empty one would still keep a blank line.
    @ViewBuilder
    private func dialog(
        _ content: some View, isConfirming: Binding<Bool>, actions: _DismissalActions<A>
    ) -> some View {
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
        return TUIkitView.renderToBuffer(content, context: context)
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
        self.triggeredMenu = button.triggeredMenu
    }
}
