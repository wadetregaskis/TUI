//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationKeyboard.swift
//
//  How the keyboard reaches a toast's buttons: F6 to the newest toast with
//  one and on to the older ones, Escape to dismiss the toast holding the
//  focus, and Tab as for any passive section.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Notification Keyboard

/// The keyboard's route to the buttons on toasts — there is always one, as
/// for every pointer interaction in TUI.
///
/// The buttons of every toast drawn are one PASSIVE focus section
/// (``sectionID``), as the window's toolbars are: Tab reaches it after the
/// page, and it never takes the keyboard by itself, so a toast arriving never
/// moves the focus out from under the person typing.
///
/// - **F6** — the key browsers and Windows use to move between a page and its
///   notification bar — moves the focus to the newest toast with a button;
///   again, to the next older one; past the oldest, back to the section it
///   came from (``FocusManager/deactivateSection(id:)``). Registered first, so
///   asked last: an app's own F6 handler wins. The status bar names it while a
///   toast with a button is drawn and the focus is elsewhere.
/// - **Escape**, while a toast's button has the focus, dismisses that toast and
///   moves the focus on to the next older one, or back where it came from: a
///   status bar item of the section, so the bar says so.
@MainActor
enum NotificationKeyboard {
    /// The focus section every toast's buttons register in.
    static let sectionID = "notifications"

    /// The focus ID of the button at `index` on the toast of `id`.
    static func focusID(_ id: NotificationID, button index: Int) -> String {
        prefix(id) + String(index)
    }

    /// What every focus ID on the toast of `id` starts with.
    private static func prefix(_ id: NotificationID) -> String {
        "notification-\(id.rawValue.uuidString)-"
    }

    /// The toast among `toasts` whose button has the focus, if one has.
    static func focused(among toasts: [NotificationID], focusManager: FocusManager?) -> NotificationID? {
        guard let focused = focusManager?.currentFocusedID else { return nil }
        return toasts.first { focused.hasPrefix(prefix($0)) }
    }

    /// What the status bar calls F6.
    private static var focusLabel: String {
        LocalizationService.shared.string(for: LocalizationKey.StatusBar.focusNotification)
    }

    /// What the status bar calls Escape over a toast.
    private static var dismissLabel: String {
        LocalizationService.shared.string(for: LocalizationKey.StatusBar.dismiss)
    }

    /// Registers, for this walk, the keys that reach `toasts` — the toasts
    /// drawn with buttons, newest first — and what the status bar says of
    /// them. Nothing where there are none, or nothing to register with.
    static func register(toasts: [NotificationID], service: NotificationService, context: RenderContext) {
        let environment = context.environment
        guard !toasts.isEmpty, let focusManager = environment.focusManager,
            let keys = environment.keyEventDispatcher
        else { return }
        if focusManager.activeSectionIdentifier == sectionID {
            let dismissFocused = { [weak focusManager] in
                guard let focusManager, let current = focused(among: toasts, focusManager: focusManager) else { return }
                service.dismiss(current)
                moveOn(after: current, among: toasts, focusManager: focusManager)
            }
            environment.statusBar?.registerSectionItems(
                sectionID: sectionID,
                items: [
                    StatusBarItem(shortcut: Shortcut.escape, label: dismissLabel, order: .escapeKey, action: dismissFocused)
                ],
                composition: .merge)
        } else {
            environment.statusBar?.notificationFocusLabel = focusLabel
        }
        keys.insertHandler(at: 0, sectionID: nil) { [weak focusManager] event in
            guard let focusManager, event.key == .f6, !event.ctrl, !event.alt, !event.shift, event.phase != .release
            else { return false }
            cycle(toasts, focusManager: focusManager)
            return true
        }
    }

    /// F6: into the newest toast, on to the next older one, or out past the
    /// oldest.
    static func cycle(_ toasts: [NotificationID], focusManager: FocusManager) {
        guard let newest = toasts.first else { return }
        guard focusManager.activeSectionIdentifier == sectionID else {
            focusManager.activateSection(id: sectionID)
            focusManager.focus(id: focusID(newest, button: 0))
            return
        }
        guard let current = focused(among: toasts, focusManager: focusManager),
            let index = toasts.firstIndex(of: current)
        else {
            focusManager.focus(id: focusID(newest, button: 0))
            return
        }
        if index + 1 < toasts.count {
            focusManager.focus(id: focusID(toasts[index + 1], button: 0))
        } else {
            focusManager.deactivateSection(id: sectionID)
        }
    }

    /// After the toast of `id` was dismissed from the keyboard or by one of
    /// its buttons: the focus on to the next older toast in `toasts`, the
    /// newest left where it was the oldest, or back where it came from where
    /// none is left. Nothing where the focus is not on a toast.
    static func moveOn(after id: NotificationID, among toasts: [NotificationID], focusManager: FocusManager) {
        guard focusManager.activeSectionIdentifier == sectionID else { return }
        let index = toasts.firstIndex(of: id) ?? toasts.count
        let rest = toasts.filter { $0 != id }
        if index + 1 < toasts.count {
            focusManager.focus(id: focusID(toasts[index + 1], button: 0))
        } else if let newest = rest.first {
            focusManager.focus(id: focusID(newest, button: 0))
        } else {
            focusManager.deactivateSection(id: sectionID)
        }
    }
}
