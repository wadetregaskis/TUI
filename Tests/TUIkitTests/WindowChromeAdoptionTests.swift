//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeAdoptionTests.swift
//
//  The window's bars hold last frame's rows, and a change the content declares
//  is adopted the frame after (the A28 design study's policy P2): a frame is
//  one walk, a still screen still gets the change, and a page that flips its
//  chrome with its own layout is held still and reported.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

/// Whether the probe page declares a header: reachable from an `App`, which
/// must be constructible with a bare `init()`.
private final class HeaderSwitch: @unchecked Sendable {
    static let shared = HeaderSwitch()
    var on = false
}

/// A page whose header comes and goes with ``HeaderSwitch``, over a leaf that
/// counts the walks that draw it.
private struct SwitchedHeaderApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                DrawnWalkCounter()
                if HeaderSwitch.shared.on {
                    Text("page").toolbar { ToolbarItem(placement: .navigation) { Text("HEADER") } }
                } else {
                    Text("page")
                }
            }
        }
    }
}

/// A leaf that counts the walks that DRAW it — not the measurements a stack
/// takes of it on the way. Renderable, because the phase is only visible from a
/// `RenderContext`.
private struct DrawnWalkCounter: View, Renderable {
    nonisolated(unsafe) static var drawn = 0

    var body: Never { fatalError("DrawnWalkCounter renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { Self.drawn += 1 }
        return FrameBuffer(lines: [""])
    }
}

/// A page that declares a header only when it has the height for its tall
/// variant — which it does not have once the header has taken its rows.
private struct OscillatingHeaderApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ViewThatFits(in: .vertical) {
                Text("tall").frame(height: 22).toolbar { ToolbarItem(placement: .navigation) { Text("HEADER") } }
                Text("short")
            }
        }
    }
}

/// A title, a subtitle under it, and an item: a two-row top bar from frame 1.
private struct TitledToolbarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .navigationTitle("NOTES")
                .navigationSubtitle("THREE")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button("NEW") {} } }
        }
    }
}

@MainActor
@Suite("The window's chrome is adopted a frame later", .serialized)
struct WindowChromeAdoptionTests {

    /// The screen's rows, escapes stripped.
    private func rows(_ loop: RenderLoop<some App>) -> [String] {
        loop.diffWriter.shownLines.map(\.stripped)
    }

    /// The screen row the page's text is on.
    private func pageRow(_ loop: RenderLoop<some App>) -> Int? {
        rows(loop).firstIndex { $0.contains("page") }
    }

    @Test("A header the page starts declaring is drawn one frame later, and one it stops declaring goes one frame later")
    func adoptionTakesOneFrame() {
        HeaderSwitch.shared.on = false
        let harness = RenderLoopHarness()
        let loop = harness.loop(SwitchedHeaderApp())
        _ = loop.render()
        #expect(!rows(loop)[1].contains("HEADER"), "pre-condition: no header")

        HeaderSwitch.shared.on = true
        _ = loop.render()
        #expect(!rows(loop).contains { $0.contains("HEADER") }, "the frame that declares it is laid out without it")
        #expect(loop.windowChrome.rows(.top) == 1, "and adopts it for the next")
        _ = loop.render()
        #expect(rows(loop)[1].contains("HEADER"), "the next frame draws it: \(rows(loop).prefix(4))")

        let withHeader = pageRow(loop)
        HeaderSwitch.shared.on = false
        _ = loop.render()
        #expect(
            rows(loop).prefix(3).allSatisfy { $0.allSatisfy(\.isWhitespace) },
            "the frame that drops it keeps its rows, blank: \(rows(loop).prefix(4))")
        #expect(pageRow(loop) == withHeader, "and lays the page out as before")
        _ = loop.render()
        #expect(loop.windowChrome.rows(.top) == 0)
        #expect(pageRow(loop) != withHeader, "the frame after gives the rows back to the page")
    }

    @Test("Every frame after the first is one walk, even when the header changes")
    func oneWalkPerFrame() {
        HeaderSwitch.shared.on = false
        let harness = RenderLoopHarness()
        let loop = harness.loop(SwitchedHeaderApp())
        _ = loop.render()
        HeaderSwitch.shared.on = true
        DrawnWalkCounter.drawn = 0
        _ = loop.render()
        _ = loop.render()
        HeaderSwitch.shared.on = false
        _ = loop.render()
        _ = loop.render()
        #expect(DrawnWalkCounter.drawn == 4, "four frames, four walks — none discarded")
    }

    @Test("A still screen is woken to adopt the change, and left idle once it has")
    func stillScreenGetsTheAdoption() {
        HeaderSwitch.shared.on = false
        let app = HeadlessApp(SwitchedHeaderApp(), width: 40, height: 12)
        app.frame(atNanos: 0)
        #expect(app.nextWake(after: 0) == nil, "pre-condition: nothing to wake for")

        HeaderSwitch.shared.on = true
        app.frame(atNanos: 1_000_000)
        #expect(app.nextWake(after: 1_000_000) != nil, "the declaring frame asks for the adopting one")
        app.frame(atNanos: 20_000_000)
        #expect(app.screen.contains { $0.stripped.contains("HEADER") })
        #expect(app.nextWake(after: 20_000_000) == nil, "and once adopted, nothing more")
    }

    @Test("A page that drops its header at the height the header leaves it is held still and reported")
    func oscillationPinsAndReports() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(OscillatingHeaderApp())
        var screens: [[String]] = []
        for _ in 0..<8 {
            _ = loop.render()
            screens.append(rows(loop))
        }
        #expect(loop.windowChrome.oscillationReports == [.top], "the flip is reported once")
        #expect(loop.windowChrome.rows(.top) == 1, "and held at the larger")
        #expect(screens[6] == screens[7], "the screen is still")
    }

    @Test("Frame 1 draws a top bar of a title and a subtitle at its full height, so frame 2 moves nothing")
    func firstFrameSeedsTheTitle() {
        let app = HeadlessApp(TitledToolbarApp(), width: 40, height: 12)
        app.frame(atNanos: 0)
        let first = app.screen.map(\.stripped)
        #expect(first[1].contains("NOTES") && first[1].contains("NEW"), "\(first)")
        #expect(first[2].contains("THREE"), "the subtitle's row: \(first)")
        app.frame(atNanos: 20_000_000)
        #expect(app.screen.map(\.stripped) == first, "nothing moved on frame 2")
    }
}
