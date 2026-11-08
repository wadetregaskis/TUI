//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationsDemo.swift
//
//  The Overlays page's notifications section: a button for each thing a
//  toast can do.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// A button per kind of toast: the four styles, a button on a toast, one that
/// stays until dismissed, another placement, live content, the desktop too,
/// and dismissing them all. There is no host to add: the app's scene draws
/// them.
struct NotificationsDemo: View {
    /// Where the demo's toasts are posted.
    private var service: NotificationService { NotificationService.current }

    var body: some View {
        DemoSection("page.overlays.notifications.section") {
            Text("page.overlays.notifications.explain")
                .foregroundStyle(.palette.foregroundSecondary)
            HStack(spacing: 1) {
                Button("page.overlays.notifications.info") {
                    service.post("page.overlays.notifications.infoMessage", style: .info)
                }
                Button("page.overlays.notifications.success") {
                    service.post("page.overlays.notifications.successMessage", style: .success)
                }
                Button("page.overlays.notifications.warning") {
                    service.post("page.overlays.notifications.warningMessage", style: .warning)
                }
                Button("page.overlays.notifications.error") {
                    service.post("page.overlays.notifications.errorMessage", style: .error, duration: 5)
                }
            }
            HStack(spacing: 1) {
                Button("page.overlays.notifications.undo") { postUndoable() }
                Button("page.overlays.notifications.sticky") {
                    service.post("page.overlays.notifications.stickyMessage", style: .warning, duration: nil)
                }
                Button("page.overlays.notifications.bottom") {
                    service.post("page.overlays.notifications.bottomMessage", placement: .bottom)
                }
            }
            HStack(spacing: 1) {
                Button("page.overlays.notifications.live") { postLiveProgress() }
                Button("page.overlays.notifications.desktop") {
                    service.post("page.overlays.notifications.desktopMessage", style: .success, desktop: .always)
                }
                Button("page.overlays.notifications.dismissAll") { service.dismissAll() }
            }
        }
    }

    /// A toast with a button: Undo, which posts what it undid.
    private func postUndoable() {
        let service = service
        service.post(
            "page.overlays.notifications.undoMessage", style: .success, duration: 6,
            actions: [
                NotificationAction("page.overlays.notifications.undoAction") {
                    service.post("page.overlays.notifications.restored", style: .info)
                }
            ])
    }

    /// A toast whose content is live: a download that fills over five seconds,
    /// redrawn by its own timeline.
    private func postLiveProgress() {
        let start = Date()
        let label = L("page.overlays.notifications.liveLabel")
        service.post(style: .info, duration: 6, placement: .bottomTrailing) {
            TimelineView(.periodic(from: start, by: 0.25)) { context in
                let percent = min(100, Int(context.date.timeIntervalSince(start) / 5 * 100))
                Text(verbatim: "\(label) \(percent)%")
            }
        }
    }
}
