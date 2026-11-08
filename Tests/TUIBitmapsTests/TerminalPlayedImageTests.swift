//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalPlayedImageTests.swift
//
//  On a terminal that plays frames by itself, an animated `Image` hands them over
//  after one pass: then a tick costs nothing, and what stops the picture is the
//  frame on screen no longer showing it.
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

private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page
    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.page = { fatalError("built with init(_:)") } }
    init(@ViewBuilder _ page: @escaping @MainActor () -> Page) { self.page = page }
    var body: some Scene { WindowGroup { page() } }
}

/// What the page shows, for a test to change between frames.
@Observable
@MainActor
private final class Page {
    var isThere = true
    var isFarBelow = false
    var isFaded = false
}

@MainActor
@Suite("A terminal plays an animated Image by itself")
struct TerminalPlayedImageTests {
    private func threeFrames(repeats: Int? = 0) -> GIFFixture {
        GIFFixture(
            frames: [.init(grey: 0, delay: 10), .init(grey: 127, delay: 20), .init(grey: 60, delay: 10)],
            repeats: repeats)
    }

    private func milli(_ value: Int64) -> Int64 { value * 1_000_000 }

    private func picture(_ path: String) -> some View {
        Image(.file(path)).frame(width: 8, height: 4)
    }

    private func draw(_ app: HeadlessApp, at now: Int64) {
        KittyGraphics.withSupport(true) { app.frame(atNanos: now) }
    }

    /// Draws at `start` until the frames have landed and the view has asked for its
    /// next one.
    private func untilPlaying(_ app: HeadlessApp, at start: Int64) async throws {
        await settle(until: {
            draw(app, at: start)
            return app.nextWake(after: start) != nil
        })
    }

    /// Follows the wakes until there are none, and says when that was.
    @discardableResult
    private func untilHandedOver(_ app: HeadlessApp, from start: Int64) -> Int64 {
        var now = start
        var steps = 0
        while let next = app.nextWake(after: now), steps < 64 {
            now = next
            draw(app, at: now)
            steps += 1
        }
        return now
    }

    /// What `body` wrote of the picture commands.
    private func written(by app: HeadlessApp, _ body: () -> Void) -> String {
        app.clearGraphicsWritten()
        body()
        return app.graphicsWritten
    }

    @Test("Its first pass sends each frame at its time, selects it by number and changes no cell")
    func firstPass() async throws {
        let path = try threeFrames().write()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            let cells = app.screen
            #expect(app.graphicsWritten.contains(",r=1,z=100,q=2"), "the first frame's gap, which only a control can set")

            let second = try #require(app.nextWake(after: 0))
            let toSecond = written(by: app) { draw(app, at: second) }
            #expect(toSecond.contains("a=f,X=1,z=200,q=2"), "the second's own")
            #expect(toSecond.contains(",c=2,q=2"))
            #expect(!toSecond.contains("s=3"), "the terminal has not got them all")
            #expect(app.screen == cells, "the picture is one image, whichever frame shows")

            let third = try #require(app.nextWake(after: second))
            let toThird = written(by: app) { draw(app, at: third) }
            #expect(toThird.contains("a=f,X=1,z=100,q=2"))
            #expect(toThird.contains(",c=3,q=2"))
            #expect(toThird.contains("s=3,v=1,q=2"), "for ever, as the file says")
            #expect(app.screen == cells)
        }
    }

    @Test("Handed over, a tick costs nothing: no bytes, no wake")
    func handedOverIsSilent() async throws {
        let path = try threeFrames().write()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)
            #expect(handedOver <= milli(400), "within its first pass")
            #expect(app.nextWake(after: handedOver) == nil)
            let bytes = app.bytesWritten
            for second in 1...5 { draw(app, at: handedOver + milli(Int64(second) * 1_000)) }
            #expect(app.bytesWritten == bytes)
        }
    }

    @Test(
        "The terminal is told as many passes as the file asks for, counting the one it is in",
        arguments: [(repeats: nil, loops: 2), (repeats: 1, loops: 3), (repeats: 4, loops: 6)] as [(repeats: Int?, loops: Int)])
    func loopCounts(repeats: Int?, loops: Int) async throws {
        let path = try threeFrames(repeats: repeats).write()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            untilHandedOver(app, from: 0)
            #expect(app.graphicsWritten.contains("s=3,v=\(loops),q=2"), "\(app.graphicsWritten.suffix(60))")
        }
    }

    @Test("Scrolled off the screen the terminal stops it, and back it runs on, with nothing sent again")
    func scrolledOff() async throws {
        let path = try threeFrames().write()
        let page = Page()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(
                PageApp {
                    ScrollView {
                        VStack(spacing: 0) {
                            Text("Above").frame(height: page.isFarBelow ? 60 : 1)
                            picture(path)
                        }
                    }
                }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)

            page.isFarBelow = true
            let leaving = written(by: app) {
                draw(app, at: handedOver + 1)
                draw(app, at: handedOver + 2)
            }
            #expect(leaving.contains("s=1,q=2"))

            page.isFarBelow = false
            let returning = written(by: app) {
                draw(app, at: handedOver + 3)
                draw(app, at: handedOver + 4)
            }
            #expect(returning.contains("s=3,v=1,q=2"))
            #expect(!returning.contains("a=f"), "the terminal still has them")
            #expect(!returning.contains("c="), "from the frame it stopped on")
        }
    }

    @Test("Under .hidden() the terminal is never told to run it")
    func hidden() async throws {
        let path = try threeFrames().write()
        await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path).hidden() }, width: 20, height: 10)
            app.recordsGraphics = true
            for _ in 0..<20 {
                draw(app, at: 0)
                await finishStartedTasks(of: app.lifecycle)
            }
            #expect(!app.graphicsWritten.contains("s=3"))
            #expect(app.nextWake(after: 0) == nil)
        }
    }

    @Test("Reduce Motion stops it where it respects that, and running again carries on")
    func reduceMotion() async throws {
        let path = try threeFrames().write()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)

            app.configureEnvironment { $0.accessibilityReduceMotion = true }
            let stopping = written(by: app) { draw(app, at: handedOver + 1) }
            #expect(stopping.contains("s=1,q=2"))

            app.configureEnvironment { $0.accessibilityReduceMotion = false }
            let starting = written(by: app) { draw(app, at: handedOver + 2) }
            #expect(starting.contains("s=3,v=1,q=2"))
        }
    }

    @Test("Told to play regardless, Reduce Motion leaves it running")
    func reduceMotionOverridden() async throws {
        let path = try threeFrames().write()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(
                PageApp { picture(path).imageAnimationRespectsReduceMotion(false) }, width: 20, height: 10)
            app.recordsGraphics = true
            app.configureEnvironment { $0.accessibilityReduceMotion = true }
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)
            #expect(app.graphicsWritten.contains("s=3,v=1,q=2"))
            let later = written(by: app) { draw(app, at: handedOver + 1) }
            #expect(!later.contains("s=1"))
        }
    }

    @Test("A view that has gone deletes the frames, and returning starts from the first")
    func goneAndBack() async throws {
        let path = try threeFrames().write()
        let page = Page()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(
                PageApp {
                    if page.isThere { picture(path) }
                }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)

            page.isThere = false
            let leaving = written(by: app) {
                draw(app, at: handedOver + 1)
                draw(app, at: handedOver + 2)
            }
            #expect(leaving.contains("a=d,d=I"), "\(leaving)")

            page.isThere = true
            app.clearGraphicsWritten()
            let back = handedOver + 3
            try await untilPlaying(app, at: back)
            #expect(!app.graphicsWritten.contains("s=3"), "a new first pass")
            let next = try #require(app.nextWake(after: back))
            #expect(next >= back + milli(100), "its first frame's whole delay")
            draw(app, at: next)
            #expect(app.graphicsWritten.contains(",c=2,q=2"))
        }
    }

    @Test("A copy of the picture, which only has its first frame, puts it back on this clock")
    func copied() async throws {
        let path = try threeFrames().write()
        let page = Page()
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(
                PageApp { picture(path).opacity(page.isFaded ? 0.5 : 1) }, width: 20, height: 10)
            try await untilPlaying(app, at: 0)
            let handedOver = untilHandedOver(app, from: 0)
            #expect(app.nextWake(after: handedOver) == nil)

            page.isFaded = true
            draw(app, at: handedOver + 1)
            draw(app, at: handedOver + 2)
            let due = try #require(app.nextWake(after: handedOver + 2), "this clock again")
            let before = app.screen
            draw(app, at: due)
            #expect(app.screen != before, "the cells name each frame again")
        }
    }

    @Test("A frame cleared by its file's disposal keeps its transparency, sent to replace what is under it")
    func transparency() async throws {
        // Each frame a block on nothing, the one before it cleared away.
        let fixture = GIFFixture(
            frames: [
                .init(grey: 40, rect: (0, 0, 4, 8), delay: 10, disposal: 2, transparent: 127),
                .init(grey: 80, rect: (4, 0, 4, 8), delay: 10, disposal: 2, transparent: 127),
            ], repeats: 0)
        let path = try fixture.write()
        let decoded = try #require(AnimatedImageDecoder.decode(atPath: path, maxPixelCount: nil))
        #expect(decoded.frames[1].image.pixels.contains { $0.a == 0 }, "the file's own transparency, decoded")
        try await KittyGraphics.withPlaysFramesItself(true) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            untilHandedOver(app, from: 0)
            let frame = try #require(app.graphicsWritten.range(of: "a=f,X=1"))
            #expect(app.graphicsWritten[frame.lowerBound...].hasPrefix("a=f,X=1,z=100,q=2,f=32,"), "with its alpha")
        }
    }

    @Test("Where the terminal did not say it can, no picture command goes that this feature adds")
    func otherHosts() async throws {
        let path = try threeFrames().write()
        try await KittyGraphics.withPlaysFramesItself(false) {
            let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
            app.recordsGraphics = true
            try await untilPlaying(app, at: 0)
            var now: Int64 = 0
            for _ in 0..<8 {
                guard let next = app.nextWake(after: now) else { break }
                now = next
                draw(app, at: now)
            }
            #expect(!app.graphicsWritten.contains("a=f"))
            #expect(!app.graphicsWritten.contains("a=a"))
            #expect(app.nextWake(after: now) != nil, "this clock goes on")
        }
    }

    @Test("Bytes a tick, on each path")
    func bytesPerTick() async throws {
        let fixture = GIFFixture(
            width: 96, height: 96,
            frames: [.init(grey: 0, delay: 10), .init(grey: 127, delay: 20), .init(grey: 60, delay: 10)], repeats: 0)
        let path = try fixture.write()
        func cost(plays: Bool) async throws -> Int {
            try await KittyGraphics.withPlaysFramesItself(plays) {
                let app = HeadlessApp(PageApp { picture(path) }, width: 20, height: 10)
                try await untilPlaying(app, at: 0)
                // Past the first pass, in which each path sends the frames.
                var now: Int64 = 0
                while let next = app.nextWake(after: now), next <= milli(400) {
                    now = next
                    draw(app, at: now)
                }
                let before = app.bytesWritten
                var ticks = 0
                while let next = app.nextWake(after: now), next <= milli(800) {
                    now = next
                    draw(app, at: now)
                    ticks += 1
                }
                return ticks == 0 ? 0 : (app.bytesWritten - before) / ticks
            }
        }
        let each = try await cost(plays: false)
        let handed = try await cost(plays: true)
        #expect(each > 200, "\(each) a tick, naming 32 cells")
        #expect(handed == 0)
    }
}
