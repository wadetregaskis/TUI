//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationStyleTests.swift
//
//  A toast's style, said twice: in the palette's colour for it, and with a
//  glyph, so its meaning never rests on colour alone.
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

/// A clock a test steps by hand, for a `NotificationService` to read.
final class StepClock: Sendable {
    let nanos = Mutex<UInt64>(1_000_000_000)
}

@MainActor
@Suite("Notification styles")
struct NotificationStyleTests {
    private func context() -> RenderContext {
        RenderContext(
            availableWidth: 60, availableHeight: 16, tuiContext: TUIContext(), identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
    }

    /// The screen a toast of `style` saying `message` is drawn on.
    private func screen(_ message: String, style: NotificationStyle) -> [String] {
        var context = context()
        // Read a second after the post, past the fade-in, on the service's own clock.
        let clock = StepClock()
        let service = NotificationService(nowNanos: { clock.nanos.withLock { $0 } })
        service.post(message, style: style)
        clock.nanos.withLock { $0 += 1_000_000_000 }
        context.environment.notificationService = service
        let buffer = renderToBuffer(Text("Base").notificationHost(), context: context)
        // Long past its end, so the animation task the render started stops.
        clock.nanos.withLock { $0 += 60_000_000_000 }
        return buffer.compositingOverlays(maxWidth: 60, maxHeight: 16, palette: context.environment.palette).lines
    }

    @Test(
        "Each style leads with its glyph, and plain with none",
        arguments: [
            (NotificationStyle.plain, nil), (.info, "\u{2139}\u{FE0F}"), (.success, "\u{2705}"),
            (.warning, "\u{26A0}\u{FE0F}"), (.error, "\u{274C}"),
        ] as [(NotificationStyle, String?)])
    func glyph(style: NotificationStyle, glyph: String?) throws {
        let lines = screen("Message", style: style)
        let row = try #require(lines.first { $0.stripped.contains("Message") }).stripped
        let words = row.split(separator: " ").map(String.init)
        let before = try #require(words.firstIndex(of: "Message"))
        // The glyph is the word before the message, inside the border's line.
        #expect(before > 0)
        if let glyph { #expect(words[before - 1] == glyph) } else { #expect(words[before - 1] == "│") }
    }

    @Test(
        "A styled toast's glyph is in the palette's colour for its style",
        arguments: [
            (NotificationStyle.info, Color.palette.info), (.success, .palette.success),
            (.warning, .palette.warning), (.error, .palette.error),
        ])
    func colour(style: NotificationStyle, colour: Color) throws {
        let glyph = try #require(style.glyph)
        let drawn = try #require(sgrState(of: glyph, in: screen("Message", style: style)))
        let reference = renderToBuffer(Text("Z").foregroundStyle(colour), context: context())
        let expected = try #require(sgrState(of: "Z", in: reference.lines))
        #expect(drawn.foregroundColour == expected.foregroundColour)
        #expect(drawn.isBold)
    }

    @Test("Each glyph is an emoji two cells wide, in a form that is emoji everywhere", arguments: NotificationStyle.allCases)
    func glyphIsTwoCellEmoji(style: NotificationStyle) throws {
        guard let glyph = style.glyph else { return }
        let character = try #require(glyph.count == 1 ? glyph.first : nil)
        #expect(character.terminalWidth == 2, "\(glyph)")
        // Emoji by presentation: by default (✅ ❌), or asked for with U+FE0F
        // where the base is text by default (ℹ ⚠).
        let base = try #require(character.unicodeScalars.first)
        #expect(base.properties.isEmojiPresentation || character.unicodeScalars.contains("\u{FE0F}"), "\(glyph)")
    }

    @Test("A long message wraps inside the toast, every word kept")
    func wraps() {
        let message = "The quick brown fox jumps over the lazy dog and keeps running for a while"
        let lines = screen(message, style: .warning)
        let toastRows = lines.filter { $0.stripped.contains("│") }
        #expect(toastRows.count >= 2, "\(lines.map(\.stripped))")
        let words = Set(toastRows.flatMap { $0.stripped.split(separator: " ").map(String.init) })
        for word in message.split(separator: " ") { #expect(words.contains(String(word)), "\(word)") }
        for row in toastRows.map(\.stripped) {
            let first = row.firstIndex(of: "│")!, last = row.lastIndex(of: "│")!
            #expect(row.distance(from: first, to: last) < 40, "\(row)")
        }
    }
}
