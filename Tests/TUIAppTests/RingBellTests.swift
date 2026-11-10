//  🖥️ TUI — A Terminal UI framework for Swift
//  RingBellTests.swift
//
//  `\.ringBell`: an app's own control saying that input was refused, with
//  the bell TUI's own controls ring (deviation T8). One `BEL` with the next
//  frame, which it asks for; once a frame, whoever rang it; never a
//  notification.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// The actions as the app's views find them, kept for a test to call between
/// frames, as an event handler would.
@MainActor
private final class BellBox {
    var ringBell: RingBellAction?
    var requestAttention: RequestAttentionAction?
}

private struct BellApp: App {
    let box: BellBox
    init() { box = BellBox() }
    init(_ box: BellBox) { self.box = box }

    var body: some Scene {
        WindowGroup { BellReader(box: box) }
    }
}

private struct BellReader: View {
    let box: BellBox
    @Environment(\.ringBell) private var ringBell
    @Environment(\.requestAttention) private var requestAttention

    var body: some View {
        box.ringBell = ringBell
        box.requestAttention = requestAttention
        return Text("waiting")
    }
}

// MARK: - Tests

@MainActor
@Suite("Ringing the bell for refused input", .serialized)
struct RingBellTests {
    private var now: Int64 = 0

    private mutating func launched(postsNotifications: Bool = false) -> (TestApp, BellBox) {
        let box = BellBox()
        let app = TestApp(BellApp(box), width: 30, height: 6)
        app.services.terminalFeatures = TerminalFeatures(showsProgress: false, postsNotifications: postsNotifications)
        frame(app)
        return (app, box)
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    @Test("A ring is one BEL with the next frame, which it asks for")
    mutating func ringsWithTheNextFrame() {
        let (app, box) = launched()
        app.services.appState.didRender()
        box.ringBell?()
        #expect(app.services.appState.needsRender, "the ring asks for a frame")
        #expect(app.bellsWritten == 0, "nothing is written between frames")
        frame(app)
        #expect(app.bellsWritten == 1)
        frame(app)
        #expect(app.bellsWritten == 1, "once")
    }

    @Test("Rings between two frames, the app's and TUI's own controls', ring once")
    mutating func coalescedWithTheControls() {
        let (app, box) = launched()
        box.ringBell?()
        box.ringBell?()
        app.services.terminalBell.ring()
        box.requestAttention?("")
        frame(app)
        #expect(app.bellsWritten == 1)
        box.ringBell?()
        frame(app)
        #expect(app.bellsWritten == 2, "each frame rings for its own")
    }

    @Test("It rings where the terminal posts notifications, and posts none")
    mutating func neverANotification() {
        let (app, box) = launched(postsNotifications: true)
        box.ringBell?()
        frame(app)
        #expect(app.bellsWritten == 1)
        #expect(app.hostWrites.isEmpty)
    }

    @Test("Outside a running app the action does nothing")
    func outsideAnApp() {
        EnvironmentValues().ringBell()
    }
}
