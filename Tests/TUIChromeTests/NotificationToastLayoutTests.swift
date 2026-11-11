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

    @Test("A toast's emoji wait for its fade-in to finish, holding their cells blank meanwhile")
    func emojiWaitForTheFadeIn() throws {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post("Done \u{1F389} now", style: .success, duration: 5)
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        // Halfway through the 0.2 s fade-in, then fully in.
        clock.nanos.withLock { $0 += 100_000_000 }
        let fading = try row("Done", in: screen(service))
        clock.nanos.withLock { $0 += 1_000_000_000 }
        let shown = try row("Done", in: screen(service))
        #expect(shown.contains("\u{2705} Done \u{1F389} now"), "\(shown)")
        // The same row with each two-cell emoji two blank cells: nothing shifts.
        let blanked = shown.replacingOccurrences(of: "\u{2705}", with: "  ")
            .replacingOccurrences(of: "\u{1F389}", with: "  ")
        #expect(fading == blanked, "\(fading)")
    }

    @Test("A toast's emoji go as soon as its fade-out starts")
    func emojiGoWithTheFadeOut() throws {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post("Done \u{1F389}", style: .info, duration: 1)
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        // Past the 0.2 s fade-in and the second it stays, into the 0.3 s fade-out.
        clock.nanos.withLock { $0 += 1_250_000_000 }
        let fading = try row("Done", in: screen(service))
        #expect(!fading.contains("\u{2139}\u{FE0F}") && !fading.contains("\u{1F389}"), "\(fading)")
        #expect(fading.contains("Done"), "\(fading)")
    }

    @Test("A toast's own text keeps fading: only its emoji wait")
    func textStillFades() throws {
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post("Plain words", duration: 5)
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        clock.nanos.withLock { $0 += 100_000_000 }
        #expect(try row("Plain words", in: screen(service)).contains("Plain words"))
    }
}
