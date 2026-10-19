//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationTermination.swift
//
//  `presentationPreventsAppTermination(_:)` and
//  `dialogPreventsAppTermination(_:)`: a presentation that stops the quit key
//  while it is on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Whether a presentation prevents the app from being quit. Mirrors
    /// SwiftUI's `presentationPreventsAppTermination(_:)`.
    ///
    /// Apply it to the presented **content** — a sheet's, a cover's or a
    /// popover's — as with ``View/interactiveDismissDisabled(_:)``:
    ///
    /// ```swift
    /// .sheet(isPresented: $editing) {
    ///     Editor()
    ///         .presentationPreventsAppTermination(true)
    /// }
    /// ```
    ///
    /// SwiftUI's quit is the app menu's Quit item; a terminal app's is its quit
    /// key (`q` by default — ``StatusBarState/quitShortcut``). While a
    /// presentation that prevents termination is on screen the key does
    /// nothing and the status bar stops offering it. A signal is not stopped:
    /// Ctrl-C, or `kill`, still ends the app, as a force quit does on macOS.
    ///
    /// `nil` asks for the automatic behaviour, which here is not to prevent
    /// it: in a terminal the quit key is a presentation's escape hatch, offered
    /// on its status bar. (SwiftUI's automatic rule reads the sheet's toolbar,
    /// which a terminal has none of.) Of several statements, a non-`nil` one
    /// overrides `nil`, and `true` takes precedence over `false`.
    ///
    /// - Parameter prevents: Whether the presentation prevents quitting, or
    ///   `nil` for the automatic behaviour.
    public func presentationPreventsAppTermination(_ prevents: Bool?) -> some View {
        _AppTerminationView(content: self, preventsAppTermination: prevents)
    }

    /// Whether the alerts and confirmation dialogs presented in this view
    /// prevent the app from being quit. Mirrors SwiftUI's
    /// `dialogPreventsAppTermination(_:)`.
    ///
    /// Apply it after the `alert` or `confirmationDialog`, as SwiftUI's
    /// examples do. While such a dialog is up the quit key does nothing and
    /// the status bar stops offering it; a signal still ends the app. See
    /// ``View/presentationPreventsAppTermination(_:)``.
    ///
    /// `nil` asks for the automatic behaviour, which is macOS's rule: the
    /// dialog prevents quitting unless it has a single button whose role is
    /// not ``ButtonRole/destructive``, its ``View/dialogSeverity(_:)`` is not
    /// critical, and it holds no text field. Counted over the actions passed,
    /// as SwiftUI counts them; no actions at all is the one standard OK button
    /// a dialog then shows. (A TUIkit dialog draws only buttons, so the text
    /// field clause never applies.) So a one-button notice leaves the quit key
    /// working, and a question — OK and Cancel, a destructive action, an
    /// error — holds it until it is answered.
    ///
    /// - Parameter prevents: Whether the dialogs prevent quitting, or `nil`
    ///   for the automatic behaviour.
    public func dialogPreventsAppTermination(_ prevents: Bool?) -> some View {
        environment(\.dialogPreventsAppTermination, prevents)
    }
}

/// The wrapper ``View/presentationPreventsAppTermination(_:)`` produces.
/// Renders and measures as its content; carrying the flag is its whole job.
struct _AppTerminationView<Content: View>: View, AppTerminationPreventing {
    let content: Content
    let preventsAppTermination: Bool?

    var body: Never {
        fatalError("_AppTerminationView renders via Renderable")
    }
}

extension _AppTerminationView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
    }
}

extension _AppTerminationView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _AppTerminationView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension _AppTerminationView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _AppTerminationView: DrawsContentUnchanged {}

// MARK: - The dialogs' rule

extension AlertPresentationModifier {
    /// Whether a dialog with `buttons` stops the quit key: as stated, or by
    /// macOS's automatic rule where `stated` is `nil` (decisions B36) — unless
    /// it has a single button that is not destructive, is not critical, and
    /// holds no text field (a TUIkit dialog holds none). No buttons is the one
    /// standard OK button SwiftUI shows then.
    static func preventsTermination(stated: Bool?, buttons: [AlertAction], isCritical: Bool) -> Bool {
        if let stated { return stated }
        let isOneHarmlessButton = buttons.count <= 1 && buttons.first?.role != .destructive
        return !isOneHarmlessButton || isCritical
    }
}

// MARK: - The dialogs' environment value

private struct DialogPreventsAppTerminationKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Whether the dialogs presented in this environment prevent quitting —
    /// set by ``View/dialogPreventsAppTermination(_:)``.
    var dialogPreventsAppTermination: Bool? {
        get { self[DialogPreventsAppTerminationKey.self] }
        set { self[DialogPreventsAppTerminationKey.self] = newValue }
    }
}
