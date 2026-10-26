//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+DialogModifiers.swift
//
//  SwiftUI's scene-level dialog modifiers: the severity, the icon and the
//  suppression toggle of the alerts a scene presents — an `AlertScene`, and
//  the alerts its views present.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation
import TUIPresentation

// Decisions A26, option 1 under refusal review O9 (b): each is a scene
// environment write, applied where a scene's other writes are — to an alert
// scene's alert, and to everything a window scene draws — so it reaches the
// alerts the views present as the view modifier of the same name does.

extension Scene {
    /// Sets the severity for alerts — mirrors SwiftUI's
    /// `Scene.dialogSeverity(_:)`.
    ///
    /// On an ``AlertScene`` it is that alert's; on a window scene, the
    /// severity of the alerts its views present, as ``View/dialogSeverity(_:)``
    /// written on their root is. A critical alert is drawn as the view
    /// modifier draws one.
    ///
    /// - Parameter severity: The severity to use for alerts.
    /// - Returns: A scene whose alerts have that severity.
    public func dialogSeverity(_ severity: DialogSeverity) -> some Scene {
        environment(\.dialogSeverity, severity)
    }

    /// Configures the icon used by alerts — mirrors SwiftUI's
    /// `Scene.dialogIcon(_:)`.
    ///
    /// On an ``AlertScene`` it is that alert's; on a window scene, that of the
    /// alerts its views present, as ``View/dialogIcon(_:)`` is.
    ///
    /// - Parameter icon: The custom icon to use for the alert, or `nil` for
    ///   the default.
    /// - Returns: A scene whose alerts show the icon.
    public func dialogIcon(_ icon: Image?) -> some Scene {
        environment(\.dialogIcon, icon)
    }

    /// Enables user suppression of an alert with a custom suppression message
    /// — mirrors SwiftUI's `Scene.dialogSuppressionToggle(_:isSuppressed:)`.
    ///
    /// The alert shows a checkbox labelled `titleKey`, bound to
    /// `isSuppressed`, as the view modifier's alerts do. Typically the value is
    /// stored in `@AppStorage` and read to decide whether to present the alert
    /// again.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the checkbox's localized label.
    ///   - isSuppressed: Whether the person asked not to be shown the alert
    ///     again.
    /// - Returns: A scene whose alerts show the checkbox.
    public func dialogSuppressionToggle(_ titleKey: LocalizedStringKey, isSuppressed: Binding<Bool>) -> some Scene {
        suppressing(label: Text(titleKey), isSuppressed: isSuppressed)
    }

    /// Enables user suppression of an alert with a custom suppression message
    /// — mirrors SwiftUI's `Scene.dialogSuppressionToggle(_:isSuppressed:)`,
    /// disfavoured so a literal is a localized key.
    ///
    /// - Parameters:
    ///   - title: The checkbox's label, shown as written.
    ///   - isSuppressed: Whether the person asked not to be shown the alert
    ///     again.
    /// - Returns: A scene whose alerts show the checkbox.
    @_disfavoredOverload
    public func dialogSuppressionToggle<S: StringProtocol>(_ title: S, isSuppressed: Binding<Bool>) -> some Scene {
        suppressing(label: Text(verbatim: String(title)), isSuppressed: isSuppressed)
    }

    /// Enables user suppression of an alert with a custom suppression message
    /// — mirrors SwiftUI's `Scene.dialogSuppressionToggle(_:isSuppressed:)`.
    ///
    /// - Parameters:
    ///   - label: The checkbox's label.
    ///   - isSuppressed: Whether the person asked not to be shown the alert
    ///     again.
    /// - Returns: A scene whose alerts show the checkbox.
    public func dialogSuppressionToggle(_ label: Text, isSuppressed: Binding<Bool>) -> some Scene {
        suppressing(label: label, isSuppressed: isSuppressed)
    }

    /// Enables user suppression of an alert — mirrors SwiftUI's
    /// `Scene.dialogSuppressionToggle(isSuppressed:)`: the checkbox has the
    /// standard label, "Do not show this message again".
    ///
    /// - Parameter isSuppressed: Whether the person asked not to be shown the
    ///   alert again.
    /// - Returns: A scene whose alerts show the checkbox.
    public func dialogSuppressionToggle(isSuppressed: Binding<Bool>) -> some Scene {
        suppressing(label: nil, isSuppressed: isSuppressed)
    }

    /// The suppression toggle, as an environment write. A scene keeps nothing
    /// from frame to frame, so the toggle is made afresh each frame with what
    /// the modifier states now, where the view modifier keeps one in its state.
    private func suppressing(label: Text?, isSuppressed: Binding<Bool>) -> some Scene {
        transformEnvironment(\.dialogSuppression) { suppression in
            suppression = DialogSuppression(label: label, isSuppressed: isSuppressed)
        }
    }
}
