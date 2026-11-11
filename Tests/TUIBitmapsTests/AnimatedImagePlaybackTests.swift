//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImagePlaybackTests.swift
//
//  `Image(.file(path))` of an animated file plays by itself, on the frame clock,
//  and only while it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport
import TUIView

private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page
    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.page = { fatalError("built with init(_:)") } }
    init(@ViewBuilder _ page: @escaping @MainActor () -> Page) { self.page = page }
    var body: some Scene { WindowGroup { page() } }
}

/// Draws its content, throws that drawing away, and draws it again, on every
/// walk: what a geometry owner does whose reader drew from a wrong answer
/// (`CoordinateSpaceModifier`), here on every frame rather than on the odd one.
private struct DrawnTwice<Content: View>: View, Renderable {
    let content: Content
    var body: Never { fatalError("DrawnTwice renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring else { return TUIView.renderToBuffer(content, context: context) }
        let checkpoint = RenderWalkCheckpoint(context: context)
        defer { checkpoint.keep() }
        _ = TUIView.renderToBuffer(content, context: context)
        checkpoint.rollBack(context: context)
        return TUIView.renderToBuffer(content, context: context)
    }
}

/// Whether the page shows its picture, for a test to change between frames.
@Observable
@MainActor
private final class Showing {
    var picture = true
    var path = ""
}

@MainActor
@Suite("An animated Image plays by itself")
struct AnimatedImagePlaybackTests {
    /// Three frames of 100, 200 and 100 ms: black, white, and half of each, to
    /// draw differently at any colour depth.
    private func threeFrames(repeats: Int? = 0) -> GIFFixture {
        GIFFixture(
            frames: [.init(grey: 0, delay: 10), .init(grey: 127, delay: 20), .init(grey: 0, rect: (0, 0, 4, 8), delay: 10)],
            repeats: repeats)
    }

    private func milli(_ value: Int64) -> Int64 { value * 1_000_000 }

    private func picture(_ path: String) -> some View {
        Image(.file(path)).frame(width: 8, height: 4)
    }

    /// Draws at `start` until the frames have landed and the view has asked for
    /// its next one, or a good while has gone by. Frames decode on a task, which
    /// has to be waited for here as a running app's loop waits for it.
    private func untilPlaying(
        _ app: HeadlessApp, at start: Int64, draw: (() -> Void)? = nil
    ) async throws {
        await TUITestSupport.settle(until: {
            if let draw { draw() } else { app.frame(atNanos: start) }
            return app.nextWake(after: start) != nil
        })
    }

    /// Lets anything already started finish, however long a decode could take,
    /// then draws: for a test that nothing is asked for afterwards. Awaits the
    /// decodes themselves, a frame at a time, where it slept 5 ms a frame.
    private func settle(_ app: HeadlessApp, at start: Int64) async throws {
        for _ in 0..<12 {
            app.frame(atNanos: start)
            await finishStartedTasks(of: app.lifecycle)
        }
    }

    @Test("Its frames advance on the clock, honouring the file's delays, and loop")
    func advances() async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)

        let first = app.screen
        // Each due at the delays, up to the next tick of 1/60 s.
        let due = try #require(app.nextWake(after: 0))
        #expect(due >= milli(100) && due < milli(100) + 16_666_667)
        app.frame(atNanos: due - 1)
        #expect(app.screen == first, "not due yet")

        app.frame(atNanos: due)
        let second = app.screen
        #expect(second != first)
        let dueThird = try #require(app.nextWake(after: due))
        #expect(dueThird >= milli(300) && dueThird < milli(300) + 16_666_667)

        app.frame(atNanos: dueThird)
        let third = app.screen
        #expect(third != second && third != first)

        let dueLoop = try #require(app.nextWake(after: dueThird))
        #expect(dueLoop >= milli(400) && dueLoop < milli(400) + 16_666_667)
        app.frame(atNanos: dueLoop)
        #expect(app.screen == first, "round to the first again")
    }

    @Test("A file:// URL plays just as a file path does")
    func playsFileURL() async throws {
        let path = try threeFrames().write()
        let fileURL = URL(fileURLWithPath: path).absoluteString
        let app = HeadlessApp(PageApp { Image(.url(fileURL)).frame(width: 8, height: 4) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)

        let first = app.screen
        let due = try #require(app.nextWake(after: 0))
        app.frame(atNanos: due)
        let second = app.screen
        #expect(second != first)
    }

    /// The frame a picture is first shown in starts its frames decoding, and
    /// that start waits for the drawing to be kept. One drawn again in that
    /// frame, its first drawing thrown away, must start them all the same: it
    /// did not, and the picture never played, which the file panels' preview
    /// met now and then under load (`FilePanelAnimatedPreviewTests`).
    @Test("A picture drawn again in the frame it is first shown, its first drawing thrown away, still plays")
    func playsWhenItsFirstDrawingIsDiscarded() async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(PageApp { DrawnTwice(content: picture(path)) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)

        let first = app.screen
        let due = try #require(app.nextWake(after: 0))
        app.frame(atNanos: due)
        #expect(app.screen != first, "the next frame")
    }

    @Test("Its loop count ends on the last frame, and then nothing is asked for", arguments: [nil, 1] as [Int?])
    func loopsEnd(repeats: Int?) async throws {
        let path = try threeFrames(repeats: repeats).write()
        let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)
        let plays = Int64((repeats ?? 0) + 1)

        // A loop's worth of wakes, as the loop would follow them.
        var now: Int64 = 0
        var last: [String] = []
        while let next = app.nextWake(after: now) {
            #expect(next <= plays * milli(400) + 16_666_667, "past the plays")
            now = next
            app.frame(atNanos: now)
            last = app.screen
        }
        #expect(now >= plays * milli(400))
        let written = app.bytesWritten
        app.frame(atNanos: now + milli(5_000))
        #expect(app.nextWake(after: now + milli(5_000)) == nil)
        #expect(app.screen == last)
        #expect(app.bytesWritten == written, "silent after the end")
    }

    @Test("A picture that does not animate asks for nothing, and neither does a page of one")
    func stillIsSilent() async throws {
        for path in [
            try GIFFixture(frames: [.init(grey: 60)], repeats: 0).write(),
            try BitmapFixture(width: 8, height: 8, left: (10, 10, 10), right: (200, 200, 200)).path,
        ] {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            try await settle(app, at: 0)
            #expect(app.nextWake(after: 0) == nil, "\(path)")
        }
    }

    @Test(
        "The override decides whether Reduce Motion stills a picture, and only then",
        arguments: [
            (reduceMotion: true, respects: true, plays: false),
            (reduceMotion: true, respects: false, plays: true),
            (reduceMotion: false, respects: true, plays: true),
            (reduceMotion: false, respects: false, plays: true),
        ])
    func override(reduceMotion: Bool, respects: Bool, plays: Bool) async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(
            PageApp { picture(path).imageAnimationRespectsReduceMotion(respects) }, width: 20, height: 10)
        app.configureEnvironment { $0.accessibilityReduceMotion = reduceMotion }
        if plays {
            try await untilPlaying(app, at: 0)
            let first = app.screen
            let due = try #require(app.nextWake(after: 0))
            app.frame(atNanos: due)
            #expect(app.screen != first, "the next frame")
        } else {
            try await settle(app, at: 0)
            #expect(app.nextWake(after: 0) == nil, "nothing to wake for")
        }
    }

    @Test("Left alone, a picture respects Reduce Motion, and a subtree's setting reaches it")
    func overrideDefaultAndSubtree() async throws {
        #expect(EnvironmentValues().imageAnimationRespectsReduceMotion)
        let path = try threeFrames().write()
        let app = HeadlessApp(
            PageApp { VStack { picture(path) }.imageAnimationRespectsReduceMotion(false) }, width: 20, height: 10)
        app.configureEnvironment { $0.accessibilityReduceMotion = true }
        try await untilPlaying(app, at: 0)
    }

    @Test("Reduce Motion shows the first frame, still")
    func reduceMotion() async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
        app.configureEnvironment { $0.accessibilityReduceMotion = true }
        try await settle(app, at: 0)
        #expect(app.nextWake(after: 0) == nil)
        let still = app.screen
        #expect(still.joined().contains { !$0.isWhitespace }, "it drew something")
        app.frame(atNanos: milli(150))
        #expect(app.screen == still)

        // And its first frame, what plays first without the setting.
        let playing = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
        try await untilPlaying(playing, at: 0)
        #expect(playing.screen == still)
    }

    @Test("Under .hidden() nothing is asked for")
    func hidden() async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(PageApp { picture(path).hidden() }, width: 20, height: 10)
        try await settle(app, at: 0)
        #expect(app.nextWake(after: 0) == nil)
    }

    @Test("Below a scroll view's window it stops, and back in view it carries on from where it was", arguments: [false, true])
    func offTheWindow(lazily: Bool) async throws {
        let path = try threeFrames().write()
        let showing = Showing()
        let app = HeadlessApp(
            PageApp {
                ScrollView {
                    let above = Text("Above").frame(height: showing.picture ? 1 : 60)
                    if lazily {
                        LazyVStack(spacing: 0) {
                            above
                            picture(path)
                        }
                    } else {
                        VStack(spacing: 0) {
                            above
                            picture(path)
                        }
                    }
                }
            }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)
        let due = try #require(app.nextWake(after: 0))
        app.frame(atNanos: due)
        let second = app.screen
        #expect(app.nextWake(after: due) != nil)

        showing.picture = false
        // The frame that moves it, and the one after the report of that.
        app.frame(atNanos: due + 1)
        app.frame(atNanos: due + 2)
        #expect(app.nextWake(after: due + 2) == nil, "off the end of the viewport")
        let written = app.bytesWritten
        app.frame(atNanos: due + milli(5_000))
        #expect(app.bytesWritten == written, "silent")

        showing.picture = true
        let back = due + milli(10_000)
        try await untilPlaying(app, at: back)
        #expect(app.screen == second, "the frame it stopped on")
        // Most of its 200 ms still to run, however long it was gone.
        let next = try #require(app.nextWake(after: back))
        #expect(next > back + milli(150) && next <= back + milli(217))
    }

    @Test("Far below a scroll view's window it never starts")
    func neverStarts() async throws {
        let path = try threeFrames().write()
        let app = HeadlessApp(
            PageApp {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Above").frame(height: 60)
                        picture(path)
                    }
                }
            }, width: 20, height: 10)
        try await settle(app, at: 0)
        #expect(app.nextWake(after: 0) == nil)
    }

    @Test("Gone, it stops and lets its frames go; back, it starts from the first again")
    func disappears() async throws {
        let path = try threeFrames().write()
        let showing = Showing()
        let app = HeadlessApp(
            PageApp {
                if showing.picture { picture(path) }
            }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)
        let first = app.screen
        let second = try #require(app.nextWake(after: 0))
        app.frame(atNanos: second)
        #expect(app.screen != first)

        showing.picture = false
        app.frame(atNanos: milli(150))
        #expect(app.nextWake(after: milli(150)) == nil, "not drawn, nothing is due")

        showing.picture = true
        // Frames decode again, as the ones it had were let go.
        app.frame(atNanos: milli(151))
        #expect(app.nextWake(after: milli(151)) == nil)
        try await untilPlaying(app, at: milli(10_000))
        #expect(app.screen == first, "from the first frame")
    }

    @Test("Another source plays instead")
    func sourceChanges() async throws {
        let (one, other) = (try threeFrames().write(), try threeFrames().write())
        let which = Showing()
        which.path = one
        let app = HeadlessApp(PageApp { picture(which.path) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)
        let started = try #require(app.nextWake(after: 0))
        which.path = other
        app.frame(atNanos: started)
        try await untilPlaying(app, at: started)
        // Its own clock: its first frame's delay from when it first drew.
        let due = try #require(app.nextWake(after: started))
        #expect(due >= started + milli(100))
    }

    // MARK: - Converting the frames

    @Test("A setting changed while it plays: the old frames go on playing until the new ones are all converted")
    func settingChangeKeepsPlaying() async throws {
        // `picture` says which setting: true colour, then mono.
        let mode = Showing()
        mode.path = try threeFrames().write()
        let app = HeadlessApp(
            PageApp { picture(mode.path).imageColorMode(mode.picture ? .trueColor : .mono) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0)
        // A loop at the first setting, so every frame has been drawn at it.
        var now: Int64 = 0
        var looks: [[String]] = [app.screen]
        while let next = app.nextWake(after: now), next < milli(400) {
            now = next
            app.frame(atNanos: now)
            looks.append(app.screen)
        }
        #expect(looks.count == 3)
        mode.picture = false
        app.frame(atNanos: now)
        #expect(app.screen == looks[2], "drawn as it was, not converted here")
        await finishStartedTasks(of: app.lifecycle)
        app.frame(atNanos: now)
        #expect(app.screen != looks[2], "all converted: the new setting")
    }

    // MARK: - In the terminal's own pixels

    /// A whole loop in the terminal: the bytes each of two rounds cost.
    private func costOfTwoLoops(_ app: HeadlessApp, classic: Bool, from start: Int64) -> (first: Int, second: Int) {
        func drawn(_ draw: () -> Void) {
            KittyGraphics.withSupport(true) {
                if classic { KittyGraphics.withClassicPlacements(true, operation: draw) } else { draw() }
            }
        }
        var now = start
        let began = app.bytesWritten
        let oneLoopLater = start + milli(400)
        while let next = app.nextWake(after: now), next <= oneLoopLater {
            now = next
            drawn { app.frame(atNanos: now) }
        }
        let firstLoop = app.bytesWritten - began
        let secondBegan = app.bytesWritten
        while let next = app.nextWake(after: now), next <= oneLoopLater + milli(400) {
            now = next
            drawn { app.frame(atNanos: now) }
        }
        return (firstLoop, app.bytesWritten - secondBegan)
    }

    @Test("In placeholders or classic placements, a frame is sent once: the next time round costs only its cells", arguments: [false, true])
    func framesStayInTheTerminal(classic: Bool) async throws {
        // Large enough that its pixels would be plain in the byte count.
        let fixture = GIFFixture(
            width: 96, height: 96,
            frames: [.init(grey: 0, delay: 10), .init(grey: 127, delay: 20), .init(grey: 60, delay: 10)], repeats: 0)
        let path = try fixture.write()
        let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
        try await untilPlaying(app, at: 0) {
            KittyGraphics.withSupport(true) {
                if classic {
                    KittyGraphics.withClassicPlacements(true) { app.frame(atNanos: 0) }
                } else {
                    app.frame(atNanos: 0)
                }
            }
        }
        let cost = costOfTwoLoops(app, classic: classic, from: 0)
        #expect(cost.second > 0, "it goes on changing")
        // 8 × 4 cells: well under a kilobyte of naming, against tens of pixels'.
        #expect(cost.second * 4 < cost.first, "first \(cost.first) bytes, then \(cost.second)")
    }

    @Test("A frame past the terminal's budget is its own picture only while it shows")
    func placedFramesAreBounded() throws {
        let playback = ImageAnimationPlayback()
        let store = TerminalImageStore()
        let frame = ImageAnimationPlayback.terminalByteBudget / 4
        let tokens = (0..<8).map {
            playback.storeToken("view", frame: $0, of: 8, pixelBytes: frame, cells: 16, store: store)
        }
        #expect(tokens == ["view-frame-0", "view-frame-1", "view-frame-2", "view-frame-3", "view", "view", "view", "view"])
        // Few pixels, but so many cells that the store's record of them binds.
        let cells = ImageAnimationPlayback.placedFrameBudget / 48 / 2
        #expect(playback.storeToken("view", frame: 1, of: 8, pixelBytes: 16, cells: cells, store: store) == "view-frame-1")
        #expect(playback.storeToken("view", frame: 2, of: 8, pixelBytes: 16, cells: cells, store: store) == "view")
    }
}
