//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemNotifier+Permission.swift
//
//  Whether macOS shows what `osascript` posts: its notifications are Script
//  Editor's, which System Settings can turn off.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension SystemNotifier {
    /// What macOS's notification settings say of the app a helper's
    /// notifications belong to.
    enum Permission: Equatable, Sendable {
        /// Its notifications are allowed.
        case allowed
        /// Its notifications are turned off: macOS keeps them in Notification
        /// Center's records, unshown.
        case denied
        /// The settings could not be read, or do not name it.
        case unknown
    }

    /// The app `osascript`'s `display notification` posts as.
    static let scriptEditorBundleID = "com.apple.ScriptEditor2"

    /// The bit of an app's `flags`, in the settings' `apps` list, that its
    /// "Allow notifications" switch sets.
    ///
    /// Not documented. Read on macOS 15.8.3, 2026-11-10: every app whose
    /// notifications were allowed in System Settings had it (Ghostty, iTerm2,
    /// Claude), and Script Editor, whose notifications macOS kept unshown, did
    /// not (*Terminal compatibility survey*, "Whether a notification
    /// appears"). Only "off" is read from it, and only to say so: a different
    /// meaning costs a wrong diagnostic, never a notification.
    static let allowsNotificationsFlag = 1 << 25

    /// What `apps`, the settings' list of apps, says of `bundleID`'s
    /// notifications.
    static func permission(of bundleID: String, in apps: [[String: Any]]?) -> Permission {
        guard let apps else { return .unknown }
        let entry = apps.first { ($0["bundle-id"] as? String)?.caseInsensitiveCompare(bundleID) == .orderedSame }
        guard let flags = entry?["flags"] as? Int else { return .unknown }
        return flags & allowsNotificationsFlag != 0 ? .allowed : .denied
    }

    /// Whether macOS shows Script Editor's notifications, which are what
    /// `osascript` posts: read from the notification settings
    /// (`com.apple.ncprefs`), now. `.unknown` where there are none to read.
    static func scriptEditorPermission() -> Permission {
        #if canImport(Darwin)
        let apps = UserDefaults(suiteName: "com.apple.ncprefs")?.array(forKey: "apps") as? [[String: Any]]
        return permission(of: scriptEditorBundleID, in: apps)
        #else
        return .unknown
        #endif
    }

    /// What TUI says, once, where Script Editor's notifications are off.
    static let scriptEditorDeniedMessage =
        "Notifications posted with osascript are Script Editor's, and System Settings has Script Editor's "
        + "notifications turned off, so macOS keeps them unshown. To see them, turn on Allow notifications in "
        + "System Settings ▸ Notifications ▸ Script Editor."
}
