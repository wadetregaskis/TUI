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
/// dismissing them all, and a toast under a sheet and one over it. There is no
/// host to add: the app's scene draws them.
struct NotificationsDemo: View {
    /// Where the demo's toasts are posted: belonging to no window, so above
    /// any sheet (`NotificationLayer`).
    private var service: NotificationService { NotificationService.current }

    /// The window's own service, whose posts go under what is presented over
    /// the window.
    @Environment(\.notificationService) private var windowService

    /// Whether the demo's sheet is up.
    @State private var showsSheet = false

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
            presentations
        }
        .sheet(isPresented: $showsSheet) { DemoSheet(isPresented: $showsSheet) }
    }

    /// A toast and a sheet at once: the window's toast waits under the sheet,
    /// its timer stopped; one above presentations is on top, reachable by F6.
    private var presentations: some View {
        // Read here, in the body: a closure runs at event time, when an
        // `@Environment` property has nothing to read.
        let (window, service) = (windowService, service)
        return HStack(spacing: 1) {
            Button("page.overlays.notifications.underSheet") {
                window?.post("page.overlays.notifications.underMessage", style: .info, duration: 4)
                showsSheet = true
            }
            Button("page.overlays.notifications.overSheet") {
                service.post(
                    "page.overlays.notifications.overMessage", style: .warning, duration: 8,
                    layer: .abovePresentations,
                    actions: [NotificationAction("page.overlays.notifications.overAction") {}])
                showsSheet = true
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

    /// The sheet the two buttons present: what to look for, a toast posted
    /// from inside it — on top of it, as it is the sheet's — and Close.
    private struct DemoSheet: View {
        @Binding var isPresented: Bool
        @Environment(\.notificationService) private var sheetService

        var body: some View {
            let sheetService = sheetService
            VStack(alignment: .leading, spacing: 1) {
                Text("page.overlays.notifications.sheetExplain")
                HStack(spacing: 1) {
                    Button("page.overlays.notifications.sheetPost") {
                        sheetService?.post("page.overlays.notifications.sheetMessage", style: .success)
                    }
                    Button("page.overlays.notifications.sheetClose") { isPresented = false }
                }
            }
            .padding()
            .frame(width: 60)
        }
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
