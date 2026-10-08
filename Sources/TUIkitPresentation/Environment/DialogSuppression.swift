//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DialogSuppression.swift
//
//  `dialogSuppressionToggle`: the "do not show this message again" checkbox in
//  the alerts and confirmation dialogs presented inside a view.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Enables user suppression of the alerts and confirmation dialogs
    /// presented in this view, with a custom suppression message. Mirrors
    /// SwiftUI's `dialogSuppressionToggle(_:isSuppressed:)`.
    ///
    /// Each such dialog shows a checkbox above its buttons, bound to
    /// `isSuppressed`. Nothing is suppressed for you: keep the value — in
    /// `@AppStorage`, typically — and decide from it whether to present the
    /// dialog next time, as on macOS.
    ///
    /// ```swift
    /// @AppStorage("suppressEraseAlert") private var suppressAlert = false
    ///
    /// Button("Delete Items") {
    ///     if suppressAlert { eraseAll() } else { confirming = true }
    /// }
    /// .confirmationDialog("Erase these items?", isPresented: $confirming) {
    ///     Button("Erase", role: .destructive) { eraseAll() }
    /// }
    /// .dialogSuppressionToggle("Do not ask about erasing again", isSuppressed: $suppressAlert)
    /// ```
    ///
    /// The checkbox comes after the buttons in the focus ring, so a dialog's
    /// first button still takes the focus when it opens.
    ///
    /// A string **literal** binds here, so the title is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The title of the suppression toggle.
    ///   - isSuppressed: Whether the suppression toggle is on.
    public func dialogSuppressionToggle(
        _ titleKey: LocalizedStringKey, isSuppressed: Binding<Bool>
    ) -> some View {
        _DialogSuppressionModifier(content: self, label: Text(titleKey), isSuppressed: isSuppressed)
    }

    /// Enables user suppression of the alerts and confirmation dialogs
    /// presented in this view, with a suppression message displayed as
    /// written.
    ///
    /// - Parameters:
    ///   - title: The title of the suppression toggle.
    ///   - isSuppressed: Whether the suppression toggle is on.
    @_disfavoredOverload
    public func dialogSuppressionToggle<S: StringProtocol>(
        _ title: S, isSuppressed: Binding<Bool>
    ) -> some View {
        _DialogSuppressionModifier(
            content: self, label: Text(verbatim: String(title)), isSuppressed: isSuppressed)
    }

    /// Enables user suppression of the alerts and confirmation dialogs
    /// presented in this view, with a suppression label of your own.
    ///
    /// - Parameters:
    ///   - label: The label of the suppression toggle.
    ///   - isSuppressed: Whether the suppression toggle is on.
    public func dialogSuppressionToggle(_ label: Text, isSuppressed: Binding<Bool>) -> some View {
        _DialogSuppressionModifier(content: self, label: label, isSuppressed: isSuppressed)
    }

    /// Enables user suppression of the alerts and confirmation dialogs
    /// presented in this view, with the default suppression message — "Do not
    /// show this message again", in the language the app is running in.
    /// Mirrors SwiftUI's `dialogSuppressionToggle(isSuppressed:)`.
    ///
    /// - Parameter isSuppressed: Whether the suppression toggle is on.
    public func dialogSuppressionToggle(isSuppressed: Binding<Bool>) -> some View {
        _DialogSuppressionModifier(content: self, label: nil, isSuppressed: isSuppressed)
    }
}

// MARK: - The environment value

/// The suppression toggle a `dialogSuppressionToggle` asks the dialogs inside
/// a view to show.
///
/// An object a modifier holds in `@State` and refreshes each body, rather than
/// a value holding the binding, for the reason ``SearchDismissal`` is one: an
/// environment value must be comparable or it turns every memo off below it,
/// and a `Binding` cannot be compared. One object for the modifier's life
/// compares by identity.
@MainActor
final class DialogSuppression: Equatable {
    /// The toggle's label, or `nil` for the default.
    var label: Text?
    var isSuppressed: Binding<Bool>?

    /// The toggle drawn in a dialog.
    var toggle: some View {
        let defaultLabel = Text(
            verbatim: LocalizationService.shared.string(for: LocalizationKey.Label.suppressDialog))
        return Toggle(isOn: isSuppressed ?? .constant(false)) { label ?? defaultLabel }
            // macOS draws a checkbox, whatever style the page around the
            // presenting view chose for its own toggles.
            .toggleStyle(.checkbox)
    }

    nonisolated static func == (lhs: DialogSuppression, rhs: DialogSuppression) -> Bool { lhs === rhs }
}

extension EnvironmentValues {
    /// The suppression toggle the dialogs presented in this environment show
    /// — set by `dialogSuppressionToggle`.
    ///
    /// Kept in the substrate's `.dialogSuppression` slot
    /// (``FeatureObjectSlot``), which detaching an environment clears.
    var dialogSuppression: DialogSuppression? {
        get { self[featureObject: .dialogSuppression] as? DialogSuppression }
        set { self[featureObject: .dialogSuppression] = newValue }
    }
}

/// Hands the dialogs inside its content a suppression toggle.
struct _DialogSuppressionModifier<Content: View>: View {
    let content: Content
    let label: Text?
    let isSuppressed: Binding<Bool>

    @State private var suppression = DialogSuppression()

    var body: some View {
        // Refreshed on every evaluation, so a dialog drawn now toggles the
        // binding as it stands now.
        suppression.label = label
        suppression.isSuppressed = isSuppressed
        return content.environment(\.dialogSuppression, suppression)
    }
}

// MARK: - Drawing

/// An alert's footer: its buttons, and the suppression toggle above them when
/// the environment asks for one.
///
/// The buttons are rendered FIRST and drawn second, so they register in the
/// focus ring ahead of the toggle: the dialog's first button keeps the focus
/// it opens with, as on macOS, where the checkbox is never where the focus
/// starts.
struct _AlertFooter: View, Renderable, Layoutable {
    let buttons: [Button]
    let verticalButtons: Bool
    let suppression: DialogSuppression?

    var body: Never {
        fatalError("_AlertFooter renders via Renderable")
    }

    private enum ChildIndex {
        static let buttons = 0
        static let toggle = 1
    }

    private var buttonsView: _AlertButtons {
        _AlertButtons(buttons: buttons, vertical: verticalButtons)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buttonsBuffer = TUIkitView.renderToBuffer(
            buttonsView,
            context: context.withChildIdentity(type: _AlertButtons.self, index: ChildIndex.buttons))
        guard let suppression else { return buttonsBuffer }
        var result = TUIkitView.renderToBuffer(
            suppression.toggle,
            context: context.withChildIdentity(type: DialogSuppression.self, index: ChildIndex.toggle))
        result.appendVertically(buttonsBuffer)
        return result
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let buttonsSize = measureChild(
            buttonsView, proposal: proposal,
            context: context.withChildIdentity(type: _AlertButtons.self, index: ChildIndex.buttons))
        guard let suppression else { return buttonsSize }
        let toggleSize = measureChild(
            suppression.toggle, proposal: proposal,
            context: context.withChildIdentity(type: DialogSuppression.self, index: ChildIndex.toggle))
        return ViewSize(
            width: max(buttonsSize.width, toggleSize.width),
            height: buttonsSize.height + toggleSize.height)
    }
}

/// The buttons, in a row or a column.
struct _AlertButtons: View {
    let buttons: [Button]
    let vertical: Bool

    @ViewBuilder var body: some View {
        if vertical {
            AlertButtonColumn(buttons: buttons)
        } else {
            AlertButtonRow(buttons: buttons)
        }
    }
}
