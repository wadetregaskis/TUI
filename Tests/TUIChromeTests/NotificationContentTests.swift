//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationContentTests.swift
//
//  A toast that draws views of the app's own in place of a message, built
//  each frame it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import Testing

@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// A value a toast's content reads, which the test changes between frames.
final class LiveText: Sendable {
    let text = Mutex("10%")
}

@MainActor
@Suite("Notifications with view content")
struct NotificationContentTests {
    /// The screen `service`'s toasts are drawn on at the clock's reading now.
    private func screen(_ service: NotificationService) -> [String] {
        var context = RenderContext(
            availableWidth: 60, availableHeight: 14, tuiContext: TUIContext(), identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
        context.environment.notificationService = service
        let buffer = renderToBuffer(Text("Base").notificationHost(), context: context)
        return buffer.compositingOverlays(maxWidth: 60, maxHeight: 14, palette: context.environment.palette)
            .lines.map(\.stripped)
    }

    @Test("A toast draws the views it was posted with, after its style's glyph")
    func drawsContent() throws {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post(style: .success) {
            HStack(spacing: 1) {
                Text("Exported")
                Text("report.pdf").bold()
            }
        }
        clock.nanos.withLock { $0 += 1_000_000_000 }
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        let row = try #require(screen(service).first { $0.contains("Exported") })
        #expect(row.contains("✓ Exported report.pdf"), "\(row)")
    }

    @Test("A toast's content is built each frame, so it shows what it reads now")
    func contentIsLive() {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        let progress = LiveText()
        service.post(duration: nil) { Text(verbatim: "Downloading \(progress.text.withLock { $0 })") }
        clock.nanos.withLock { $0 += 1_000_000_000 }
        defer {
            service.dismissAll()
            clock.nanos.withLock { $0 += 3_600_000_000_000 }
        }
        #expect(screen(service).contains { $0.contains("Downloading 10%") })
        progress.text.withLock { $0 = "70%" }
        #expect(screen(service).contains { $0.contains("Downloading 70%") })
    }
}
