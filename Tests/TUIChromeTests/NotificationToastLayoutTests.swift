//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationToastLayoutTests.swift
//
//  What a toast draws where: its buttons at its trailing edge, and its emoji
//  only while it is fully opaque.
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

@MainActor
@Suite("Notification toast layout")
struct NotificationToastLayoutTests {
    /// The screen `service`'s toasts are drawn on at its clock's reading now,
    /// without its escapes.
    private func screen(_ service: NotificationService) -> [String] {
        var context = RenderContext(
            availableWidth: 60, availableHeight: 14, tuiContext: TUIContext(), identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
        context.environment.notificationService = service
        let buffer = renderToBuffer(Text("Base").notificationHost(), context: context)
        return buffer.compositingOverlays(maxWidth: 60, maxHeight: 14, palette: context.environment.palette)
            .lines.map(\.stripped)
    }

    /// The row of `screen` holding `text`.
    private func row(_ text: String, in screen: [String]) throws -> String {
        try #require(screen.first { $0.contains(text) }, "\(screen)")
    }

    @Test("A toast's buttons sit at its trailing edge, its message at its leading one")
    func buttonsAreTrailing() throws {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post(
            "Saved", style: .success, duration: 5, actions: [NotificationAction(verbatim: "Undo", role: nil) {}])
        clock.nanos.withLock { $0 += 1_000_000_000 }
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        let lines = screen(service)
        let buttons = try row("Undo", in: lines)
        let message = try row("Saved", in: lines)
        // The space each row leaves between the toast's two border lines,
        // before its first mark and after its last.
        func margins(_ row: String) throws -> (leading: Int, trailing: Int) {
            let left = try #require(row.firstIndex(of: "│")), right = try #require(row.lastIndex(of: "│"))
            let inside = row[row.index(after: left)..<right]
            let leading = inside.prefix { $0 == " " }.count
            let trailing = inside.reversed().prefix { $0 == " " }.count
            return (leading, trailing)
        }
        let buttonMargins = try margins(buttons), messageMargins = try margins(message)
        #expect(messageMargins.leading == 1, "\(message)")
        #expect(buttonMargins.leading > buttonMargins.trailing, "\(buttons)")
        // As close to the trailing border as the message is to the leading one:
        // the border's blank, and whatever blank a button draws round its title.
        #expect(buttonMargins.trailing <= 2, "\(buttons)")
    }
}
