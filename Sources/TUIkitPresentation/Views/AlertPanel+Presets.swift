//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlertPanel+Presets.swift
//
//  The four styled alerts — warning, error, info, success — split out of
//  AlertPanel.swift, which is the view itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Preset Alert Styles

// Each preset is THREE overloads, not two. The key one keeps its defaulted
// title; its twin is generic over `StringProtocol` — which is what keeps a
// literal binding to the key overload at all, `@_disfavoredOverload` alone
// having stopped being enough in Swift 6.3 for a signature with another
// required argument, and every one of these has `message` — and a generic
// parameter cannot carry a default, so the title's default had to move OUT of
// that twin into a third overload taking no title at all. That is
// ``QuitShortcut``'s split, applied eight times.
//
// The third overload is `@_disfavoredOverload` as well, and there the attribute
// is load-bearing rather than tidying: it has FEWER defaulted arguments than
// the key overload (none, against that one's title), and Swift's "fewer
// defaults wins" tie-break would otherwise hand `AlertPanel.warning(message:
// "alert.diskFull")` to it — leaving the message unlooked-up and the title
// resolved through the service instead of the key table. Mutation-tested on
// 6.3.3: remove the attribute and that call does go to the generic form.
//
// What the shape preserves is the symmetry `SwiftUI compatibility guide.md` §4a
// records: `warning(message: "alert.diskFull")` reaches the key overload and is
// looked up, while `warning(message: computedString)` reaches the generic one
// and STILL gets the translated `label.warning` title. Neither side gave up its
// default; the disfavoured side's simply lives in its own declaration now.
//
// The forwarded default needs no `as String` (``QuitShortcut``'s does): it is a
// service call's result rather than a literal, so there is nothing for a
// ``LocalizedStringKey`` to be built out of and the forwarding call can only
// land on the generic overload.

/// The sign each preset's title starts with. Emoji, as the critical dialog's
/// ⚠️ is: icons drawn in their own colours rather than the palette's, each a
/// two-cell pictograph (🛑 and ✅ by default presentation, ⚠️ and ℹ️ with
/// U+FE0F) — the class the advance table measures and the writer compensates
/// where a host advances one a cell short. Package-wide for the file panels'
/// remote-machine notice, which starts with the same warning sign.
package enum AlertPanelMark {
    package static let warning = "\u{26A0}\u{FE0F}"
    static let error = "\u{1F6D1}"
    static let info = "\u{2139}\u{FE0F}"
    static let success = "\u{2705}"
}

extension LocalizedStringKey {
    /// A preset's title key, resolved: TUIkit's own word when it is the
    /// preset's default key — so an app's `Localizable` table does not change
    /// a preset's title by spelling the same key (see
    /// ``LocalizationService``) — and the app's lookup of any other key.
    ///
    /// Compared by key because a default argument is just a value: nothing
    /// tells the default apart from the same key passed by the app, and that
    /// key names TUIkit's word either way.
    ///
    /// `service` is the shared one but for tests, which read an app's tables
    /// from a bundle of their own.
    func localizedTitle(
        defaultingTo label: LocalizationKey.Label, service: LocalizationService = .shared
    ) -> String {
        key == label.rawValue && arguments.isEmpty
            ? service.frameworkString(for: key) : resolved(with: service)
    }
}

extension AlertPanel {
    /// Creates a warning-style alert with palette warning colors.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``. The default title is the framework's own
    /// `label.warning`, translated into every bundled language; the presets
    /// used to hard-code the English word.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.warning`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: A warning-styled alert.
    public static func warning(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.warning.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        warning(
            title: titleKey.localizedTitle(defaultingTo: .warning), message: messageKey.localized, actions: actions)
    }

    /// Creates a warning-style alert with text displayed as written.
    ///
    /// Generic over `StringProtocol` in both slots, and so necessarily without
    /// the title's default — see the note at the top of this file.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A warning-styled alert.
    @_disfavoredOverload
    public static func warning<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        var alert = Self(
            title: title,
            message: message,
            titleColor: .palette.warning,
            actions: actions
        )
        alert.titleMark = AlertPanelMark.warning
        return alert
    }

    /// Creates a warning-style alert titled with the localized `label.warning`,
    /// its message displayed as written.
    ///
    /// This is where the generic overload's title default went — see the note
    /// at the top of this file.
    ///
    /// - Parameters:
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A warning-styled alert.
    @_disfavoredOverload
    public static func warning<S: StringProtocol>(
        message: S,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        warning(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.warning),
            message: message,
            actions: actions
        )
    }

    /// Creates an error-style alert with palette error title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.error`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: An error-styled alert.
    public static func error(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.error.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        error(title: titleKey.localizedTitle(defaultingTo: .error), message: messageKey.localized, actions: actions)
    }

    /// Creates an error-style alert with text displayed as written.
    ///
    /// Generic in both slots, and so without the title's default — see the note
    /// at the top of this file.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An error-styled alert.
    @_disfavoredOverload
    public static func error<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        var alert = Self(
            title: title,
            message: message,
            titleColor: .palette.error,
            actions: actions
        )
        alert.titleMark = AlertPanelMark.error
        return alert
    }

    /// Creates an error-style alert titled with the localized `label.error`,
    /// its message displayed as written.
    ///
    /// - Parameters:
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An error-styled alert.
    @_disfavoredOverload
    public static func error<S: StringProtocol>(
        message: S,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        error(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.error),
            message: message,
            actions: actions
        )
    }

    /// Creates an info-style alert with palette info title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.info`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: An info-styled alert.
    public static func info(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.info.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        info(title: titleKey.localizedTitle(defaultingTo: .info), message: messageKey.localized, actions: actions)
    }

    /// Creates an info-style alert with text displayed as written.
    ///
    /// Generic in both slots, and so without the title's default — see the note
    /// at the top of this file.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An info-styled alert.
    @_disfavoredOverload
    public static func info<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        var alert = Self(
            title: title,
            message: message,
            titleColor: .palette.info,
            actions: actions
        )
        alert.titleMark = AlertPanelMark.info
        return alert
    }

    /// Creates an info-style alert titled with the localized `label.info`, its
    /// message displayed as written.
    ///
    /// - Parameters:
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An info-styled alert.
    @_disfavoredOverload
    public static func info<S: StringProtocol>(
        message: S,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        info(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.info),
            message: message,
            actions: actions
        )
    }

    /// Creates a success-style alert with palette success title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.success`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: A success-styled alert.
    public static func success(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.success.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        success(title: titleKey.localizedTitle(defaultingTo: .success), message: messageKey.localized, actions: actions)
    }

    /// Creates a success-style alert with text displayed as written.
    ///
    /// Generic in both slots, and so without the title's default — see the note
    /// at the top of this file.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A success-styled alert.
    @_disfavoredOverload
    public static func success<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        var alert = Self(
            title: title,
            message: message,
            titleColor: .palette.success,
            actions: actions
        )
        alert.titleMark = AlertPanelMark.success
        return alert
    }

    /// Creates a success-style alert titled with the localized `label.success`,
    /// its message displayed as written.
    ///
    /// - Parameters:
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A success-styled alert.
    @_disfavoredOverload
    public static func success<S: StringProtocol>(
        message: S,
        @ViewBuilder actions: () -> Actions
    ) -> AlertPanel {
        success(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.success),
            message: message,
            actions: actions
        )
    }
}

// MARK: - Preset Alerts without Actions

// The same three-overload shape as above, for the same reasons.

extension AlertPanel where Actions == EmptyView {
    /// Creates a warning-style alert without actions. Literals are keys.
    public static func warning(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.warning.rawValue),
        message messageKey: LocalizedStringKey
    ) -> AlertPanel<EmptyView> {
        warning(title: titleKey.localizedTitle(defaultingTo: .warning), message: messageKey.localized)
    }

    /// Creates a warning-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func warning<S1: StringProtocol, S2: StringProtocol>(
        title: S1, message: S2
    ) -> AlertPanel<EmptyView> {
        {
            var alert = AlertPanel<EmptyView>(title: title, message: message, titleColor: .palette.warning)
            alert.titleMark = AlertPanelMark.warning
            return alert
        }()
    }

    /// Creates a warning-style alert without actions, titled with the localized
    /// `label.warning` and its message shown as written.
    @_disfavoredOverload
    public static func warning<S: StringProtocol>(message: S) -> AlertPanel<EmptyView> {
        warning(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.warning),
            message: message)
    }

    /// Creates an error-style alert without actions. Literals are keys.
    public static func error(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.error.rawValue),
        message messageKey: LocalizedStringKey
    ) -> AlertPanel<EmptyView> {
        error(title: titleKey.localizedTitle(defaultingTo: .error), message: messageKey.localized)
    }

    /// Creates an error-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func error<S1: StringProtocol, S2: StringProtocol>(
        title: S1, message: S2
    ) -> AlertPanel<EmptyView> {
        {
            var alert = AlertPanel<EmptyView>(title: title, message: message, titleColor: .palette.error)
            alert.titleMark = AlertPanelMark.error
            return alert
        }()
    }

    /// Creates an error-style alert without actions, titled with the localized
    /// `label.error` and its message shown as written.
    @_disfavoredOverload
    public static func error<S: StringProtocol>(message: S) -> AlertPanel<EmptyView> {
        error(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.error),
            message: message)
    }

    /// Creates an info-style alert without actions. Literals are keys.
    public static func info(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.info.rawValue),
        message messageKey: LocalizedStringKey
    ) -> AlertPanel<EmptyView> {
        info(title: titleKey.localizedTitle(defaultingTo: .info), message: messageKey.localized)
    }

    /// Creates an info-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func info<S1: StringProtocol, S2: StringProtocol>(
        title: S1, message: S2
    ) -> AlertPanel<EmptyView> {
        {
            var alert = AlertPanel<EmptyView>(title: title, message: message, titleColor: .palette.info)
            alert.titleMark = AlertPanelMark.info
            return alert
        }()
    }

    /// Creates an info-style alert without actions, titled with the localized
    /// `label.info` and its message shown as written.
    @_disfavoredOverload
    public static func info<S: StringProtocol>(message: S) -> AlertPanel<EmptyView> {
        info(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.info),
            message: message)
    }

    /// Creates a success-style alert without actions. Literals are keys.
    public static func success(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.success.rawValue),
        message messageKey: LocalizedStringKey
    ) -> AlertPanel<EmptyView> {
        success(title: titleKey.localizedTitle(defaultingTo: .success), message: messageKey.localized)
    }

    /// Creates a success-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func success<S1: StringProtocol, S2: StringProtocol>(
        title: S1, message: S2
    ) -> AlertPanel<EmptyView> {
        {
            var alert = AlertPanel<EmptyView>(title: title, message: message, titleColor: .palette.success)
            alert.titleMark = AlertPanelMark.success
            return alert
        }()
    }

    /// Creates a success-style alert without actions, titled with the localized
    /// `label.success` and its message shown as written.
    @_disfavoredOverload
    public static func success<S: StringProtocol>(message: S) -> AlertPanel<EmptyView> {
        success(
            title: LocalizationService.shared.string(for: LocalizationKey.Label.success),
            message: message)
    }
}
