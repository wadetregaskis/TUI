//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InteractiveResizeChangeTests.swift
//
//  `onInteractiveResizeChange` reads a burst of terminal resizes as a live
//  resize: `true` at the first frame drawn at a new size after a quiet period,
//  `false` at the frame its timeout's wake asks for.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What the action was told, in order.
@MainActor
private final class ResizeLog {
    var calls: [Bool] = []
    /// How many times the observed view's `body` ran: a memo that serves it
    /// runs none.
    var bodies = 0
}

/// One line carrying the modifier, behind `.equatable()` when `behindMemo` (a
/// memo that would serve it if the modifier did not refuse one).
private struct ResizeApp: App {
    let log: ResizeLog
    let timeout: Duration?
    let behindMemo: Bool

    init() { self.init(log: ResizeLog()) }

    init(log: ResizeLog, timeout: Duration? = nil, behindMemo: Bool = false) {
        self.log = log
        self.timeout = timeout
        self.behindMemo = behindMemo
    }

    var body: some Scene {
        WindowGroup {
            ResizePage(log: log, timeout: timeout, behindMemo: behindMemo)
        }
    }
}

private struct ResizePage: View {
    let log: ResizeLog
    let timeout: Duration?
    let behindMemo: Bool

    var body: some View {
        if behindMemo {
            VStack {
                Text("above")
                Watcher(log: log).equatable()
            }
        } else if let timeout {
            Watcher(log: log).interactiveResizeTimeout(timeout)
        } else {
            Watcher(log: log)
        }
    }
}

/// The observed line. Equal to every other, so `.equatable()` would serve it
/// from its memo on every frame after the first if the modifier let it.
private struct Watcher: View, Equatable {
    let log: ResizeLog

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        log.bodies += 1
        return Text("watching").onInteractiveResizeChange { [log] in log.calls.append($0) }
    }
}

/// Whether the observed line is on screen, toggled between frames.
@Observable
@MainActor
private final class Presence {
    var shown = true
}

private struct ComingAndGoingApp: App {
    let log: ResizeLog
    let presence: Presence

    init() { self.init(log: ResizeLog(), presence: Presence()) }

    init(log: ResizeLog, presence: Presence) {
        self.log = log
        self.presence = presence
    }

    var body: some Scene {
        WindowGroup {
            ComingAndGoingPage(log: log, presence: presence)
        }
    }
}

private struct ComingAndGoingPage: View {
    let log: ResizeLog
    let presence: Presence

    var body: some View {
        if presence.shown {
            Watcher(log: log)
        } else {
            Text("gone")
        }
    }
}

@MainActor
@Suite("onInteractiveResizeChange")
struct InteractiveResizeChangeTests {
    private static let frame: Int64 = 16_666_667

    @Test("A burst of resizes reports true at its first frame and false once the default 200 ms pass quietly")
    func aBurstBeginsAndEnds() {
        let log = ResizeLog()
        let app = HeadlessApp(ResizeApp(log: log), width: 40, height: 10)
        app.frame(atNanos: 0)
        #expect(log.calls.isEmpty, "the action ran as the view appeared")

        app.resize(width: 50, height: 10)
        app.frame(atNanos: Self.frame)
        #expect(log.calls == [true])
        app.resize(width: 60, height: 12)
        app.frame(atNanos: 2 * Self.frame)
        #expect(log.calls == [true], "a resize inside the burst began another")

        // The burst ends 200 ms after the last frame drawn at a new size, and
        // the modifier asked for the frame that finds it so.
        let endsAt = 2 * Self.frame + 200_000_000
        #expect(app.nextWake(after: 2 * Self.frame) == endsAt)
        app.frame(atNanos: endsAt - 1)
        #expect(log.calls == [true], "the burst ended before its timeout")
        app.frame(atNanos: endsAt)
        #expect(log.calls == [true, false])
        #expect(app.nextWake(after: endsAt) == nil, "a quiet terminal still asks for frames")

        // And the next burst begins again.
        app.resize(width: 40, height: 10)
        app.frame(atNanos: endsAt + Self.frame)
        #expect(log.calls == [true, false, true])
    }

    @Test("A size report that leaves the grid as it was is not a resize")
    func aSameSizeReportIsNotAResize() {
        let log = ResizeLog()
        let app = HeadlessApp(ResizeApp(log: log), width: 40, height: 10)
        app.frame(atNanos: 0)
        app.resize(width: 40, height: 10)
        app.frame(atNanos: Self.frame)
        #expect(log.calls.isEmpty)
    }

    @Test("The timeout is the environment's: a view may set its own")
    func theTimeoutIsTheEnvironments() {
        let log = ResizeLog()
        let app = HeadlessApp(ResizeApp(log: log, timeout: .milliseconds(500)), width: 40, height: 10)
        app.frame(atNanos: 0)
        app.resize(width: 50, height: 10)
        app.frame(atNanos: Self.frame)
        app.frame(atNanos: Self.frame + 400_000_000)
        #expect(log.calls == [true], "the default timeout ended the burst")
        app.frame(atNanos: Self.frame + 500_000_000)
        #expect(log.calls == [true, false])
    }

    /// The burst goes out and back, so the frame that ends it is drawn at the
    /// size of the frame before it began — the one frame a memo could have
    /// stored this subtree at. A size change clears the render cache, which is
    /// what lets the modifier leave the memo above it on.
    @Test("Behind an equatable memo the end of a burst is heard, and the memo still serves an idle frame")
    func aMemoNeitherSwallowsTheEndNorIsTurnedOff() {
        let log = ResizeLog()
        let app = HeadlessApp(ResizeApp(log: log, behindMemo: true), width: 40, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        app.resize(width: 50, height: 10)
        app.frame(atNanos: 2 * Self.frame)
        #expect(log.calls == [true])
        app.resize(width: 40, height: 10)
        app.frame(atNanos: 3 * Self.frame)
        let endsAt = 3 * Self.frame + 200_000_000
        app.frame(atNanos: endsAt)
        #expect(log.calls == [true, false])

        let bodies = log.bodies
        app.frame(atNanos: endsAt + Self.frame)
        #expect(log.bodies == bodies, "listening for resizes turned the memo above off")
        #expect(log.calls == [true, false])
    }

    /// The documented edge of "the calls alternate": they do for as long as
    /// the view is on screen, and one that leaves mid-burst hears no `false`.
    @Test("A view that leaves during a burst hears no false, and back inside it hears true again")
    func aViewLeavingMidBurst() {
        let log = ResizeLog()
        let presence = Presence()
        let app = HeadlessApp(ComingAndGoingApp(log: log, presence: presence), width: 40, height: 10)
        app.frame(atNanos: 0)
        app.resize(width: 50, height: 10)
        app.frame(atNanos: Self.frame)
        #expect(log.calls == [true])

        presence.shown = false
        app.frame(atNanos: 2 * Self.frame)
        let endsAt = Self.frame + 200_000_000
        app.frame(atNanos: endsAt)
        #expect(log.calls == [true], "a view no longer on screen heard the burst end")

        // Back during the next burst: it starts again from `false`.
        presence.shown = true
        app.resize(width: 60, height: 10)
        app.frame(atNanos: endsAt + Self.frame)
        #expect(log.calls == [true, true])
        app.frame(atNanos: endsAt + Self.frame + 200_000_000)
        #expect(log.calls == [true, true, false])
    }
}
