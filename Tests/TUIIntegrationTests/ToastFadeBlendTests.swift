//  🖥️ TUI — A Terminal UI framework for Swift
//  ToastFadeBlendTests.swift
//
//  A toast's fades take it toward what is behind it, as a window fading over a
//  page does: at opacity 0 the page shows through unchanged, half way a mix of
//  the two, and at 1 the toast. The fade used to be applied INSIDE the toast,
//  so it faded toward the toast's own surface, which a floating layer paints
//  opaque: the frame a toast was posted on, and every frame of its fades, drew
//  a box of blank cells over the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing
import TUICore

import TUI
@testable import TUIApp
@testable import TUIChrome
@testable import TUIFoundation
@testable import TUITestSupport

/// A clock the tests step by hand, for the service.
private final class FadeClock: Sendable {
    let nanos = Mutex<UInt64>(5_000_000_000)
    var now: UInt64 { nanos.withLock { $0 } }
    func advance(seconds: Double) { nanos.withLock { $0 += UInt64(seconds * 1_000_000_000) } }
}

@MainActor
@Suite("A toast's fades blend it with the page")
struct ToastFadeBlendTests {
    /// The page's field: a colour nothing else uses, so a cell wearing it shows the page.
    private static let page = [255, 0, 255]

    private let clock = FadeClock()

    /// Six rows of `#` over the page's colour, a toast posted over them, and
    /// the screen composited as the render loop composites it at the clock's
    /// instant `seconds` after the post: the rows composited, and where the
    /// toast's layer sits.
    private func screen(secondsAfterPost seconds: Double, duration: Double = 3) throws
        -> (lines: [String], x: Int, y: Int, width: Int, height: Int)
    {
        let clock = clock
        let service = NotificationService(nowNanos: { clock.now })
        defer { service.clear() }
        service.post("Toast", duration: duration)
        clock.advance(seconds: seconds)
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.notificationService = service
        let context = RenderContext(availableWidth: 40, availableHeight: 8, environment: environment, tuiContext: tui)
        let view = ZStack(alignment: .topLeading) {
            Color.rgb(255, 0, 255)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in Text(String(repeating: "#", count: 40)) }
            }
        }
        .notificationHost()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight, palette: context.environment.palette)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        let layer = try #require(buffer.overlays.first, "no toast layer: it must stay drawn, and reachable, at age 0")
        let placed = layer.placed(maxWidth: context.availableWidth, maxHeight: context.availableHeight)
        return (composited.lines, placed.x, placed.y, placed.content.width, placed.content.height)
    }

    /// The red, green and blue of the field at `column` of `line`.
    private func fieldColour(_ line: String, _ column: Int) -> [Int]? {
        guard case .rgb(let red, let green, let blue) = line.ansiSGRStateAt(visibleColumn: column).backgroundColour
        else { return nil }
        return [red, green, blue]
    }

    /// The text of the rows the toast covers, cut to its columns.
    private func covered(_ shot: (lines: [String], x: Int, y: Int, width: Int, height: Int)) -> [String] {
        (shot.y..<(shot.y + shot.height)).map { row in
            String(shot.lines[row].stripped.dropFirst(shot.x).prefix(shot.width))
        }
    }

    @Test("At age 0 the page shows through the toast's box unchanged")
    func posted() throws {
        let shot = try screen(secondsAfterPost: 0)
        #expect(
            covered(shot).allSatisfy { $0 == String(repeating: "#", count: shot.width) },
            "the page's glyphs, all of them: \(covered(shot))")
        // Inside the border: the blank cell before the message.
        let field = try #require(fieldColour(shot.lines[shot.y + 1], shot.x + 1))
        #expect(field == Self.page, "the page's own field, not the toast's surface: \(field)")
    }

    @Test("Fully faded in, the toast covers the page")
    func faded() throws {
        let shot = try screen(secondsAfterPost: 1)
        #expect(covered(shot).joined().contains("Toast"))
        #expect(!covered(shot).joined().contains("#"), "nothing of the page shows through: \(covered(shot))")
        let field = try #require(fieldColour(shot.lines[shot.y + 1], shot.x + 1))
        #expect(field != Self.page)
    }

    /// Half way in, and half way out: a mix of the page and the toast, both
    /// ways the same.
    @Test("Half way through either fade, the field is a mix of the page and the toast", arguments: [0.1, 3.35])
    func halfWay(seconds: Double) throws {
        let opaque = try screen(secondsAfterPost: 1)
        let surface = try #require(fieldColour(opaque.lines[opaque.y + 1], opaque.x + 1))
        let shot = try screen(secondsAfterPost: seconds)
        let field = try #require(fieldColour(shot.lines[shot.y + 1], shot.x + 1))
        // Each channel half way between the two, give or take the rounding.
        for channel in 0..<3 {
            let half = (Self.page[channel] + surface[channel]) / 2
            #expect(abs(field[channel] - half) <= 2, "page \(Self.page), toast \(surface), drawn \(field)")
        }
    }

    @Test("At the end of the fade-out the page shows through again")
    func fadingOut() throws {
        // 3.5 s is its whole life: a hundredth short of it, opacity 1/30.
        let shot = try screen(secondsAfterPost: 3.49)
        #expect(
            covered(shot).allSatisfy { $0 == String(repeating: "#", count: shot.width) },
            "the page's glyphs, all of them: \(covered(shot))")
        let field = try #require(fieldColour(shot.lines[shot.y + 1], shot.x + 1))
        let offPage = (0..<3).map { abs(field[$0] - Self.page[$0]) }.reduce(0, +)
        #expect(offPage <= 3 * 12, "within a thirtieth of the page's field: \(field)")
    }
}
