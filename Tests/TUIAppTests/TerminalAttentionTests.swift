//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalAttentionTests.swift
//
//  `\.requestAttention` (the Ghostty adoption study, C6): a desktop
//  notification (`OSC 9`) on a terminal that posts one, the bell on every
//  other; written with the next frame, which it asks for; each message once
//  and the bell once a frame; made safe as text, and kept from reading as a
//  ConEmu command.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

/// The action as the app's views find it, kept for a test to call between
/// frames, as an event handler or a task would.
@MainActor
private final class ActionBox {
    var requestAttention: RequestAttentionAction?
}

private struct AttentionApp: App {
    let box: ActionBox
    init() { box = ActionBox() }
    init(_ box: ActionBox) { self.box = box }

    var body: some Scene {
        WindowGroup { AttentionReader(box: box) }
    }
}

private struct AttentionReader: View {
    let box: ActionBox
    @Environment(\.requestAttention) private var requestAttention

    var body: some View {
        box.requestAttention = requestAttention
        return Text("waiting")
    }
}

// MARK: - Tests

@MainActor
@Suite("Asking for the person's attention", .serialized)
struct TerminalAttentionTests {
    private var now: Int64 = 0

    private static func notification(_ text: String) -> String { "\u{1B}]9;\(text)\u{1B}\\" }

    private mutating func launched(postsNotifications: Bool) -> (HeadlessApp, RequestAttentionAction) {
        let box = ActionBox()
        let app = HeadlessApp(AttentionApp(box), width: 30, height: 6)
        app.services.terminalFeatures = TerminalFeatures(showsProgress: false, postsNotifications: postsNotifications)
        frame(app)
        return (app, box.requestAttention!)
    }

    private mutating func frame(_ app: HeadlessApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    @Test("A terminal that posts notifications is sent the message with the next frame, which it asks for")
    mutating func postsANotification() {
        let (app, requestAttention) = launched(postsNotifications: true)
        app.services.appState.didRender()
        requestAttention("Build finished")
        #expect(app.services.appState.needsRender, "the request asks for a frame")
        #expect(app.hostWrites.isEmpty, "nothing is written between frames")
        frame(app)
        #expect(app.hostWrites == [Self.notification("Build finished")])
        #expect(app.bellsWritten == 0)
        frame(app)
        #expect(app.hostWrites.count == 1, "once")
    }

    @Test("Any other terminal is rung its bell")
    mutating func ringsElsewhere() {
        let (app, requestAttention) = launched(postsNotifications: false)
        requestAttention("Build finished")
        frame(app)
        #expect(app.hostWrites.isEmpty)
        #expect(app.bellsWritten == 1)
    }

    @Test("Requests between two frames post each message once, in order, and ring the bell once")
    mutating func coalesced() {
        let (posting, requestAttention) = launched(postsNotifications: true)
        requestAttention("one")
        requestAttention("two")
        requestAttention("one")
        frame(posting)
        #expect(posting.hostWrites == [Self.notification("one") + Self.notification("two")])

        let (ringing, ring) = launched(postsNotifications: false)
        ring("one")
        ring("two")
        ringing.services.terminalBell.ring()
        frame(ringing)
        #expect(ringing.bellsWritten == 1)
    }

    @Test("A message with nothing to say rings the bell even where notifications are posted")
    mutating func emptyRings() {
        let (app, requestAttention) = launched(postsNotifications: true)
        requestAttention("")
        frame(app)
        requestAttention(" \u{07}\u{1B} ")
        frame(app)
        #expect(app.hostWrites.isEmpty)
        #expect(app.bellsWritten == 2)
    }

    @Test("A message cannot end its sequence early, nor read as a ConEmu command")
    mutating func messageMadeSafe() {
        let (app, requestAttention) = launched(postsNotifications: true)
        requestAttention("Done\u{07}\u{1B}]0;pwned\u{1B}\\\nnext")
        frame(app)
        requestAttention("4;1;50 files copied")
        frame(app)
        #expect(app.hostWrites == [Self.notification("Done]0;pwned\\ next"), Self.notification(" 4;1;50 files copied")])
    }

    @Test("The notification's spelling: a leading digit is sent after a space; nothing but spaces is none")
    func spelling() {
        #expect(TerminalHostState.notification("Ready") == Self.notification("Ready"))
        #expect(TerminalHostState.notification("3 files") == Self.notification(" 3 files"))
        #expect(TerminalHostState.notification("x 3") == Self.notification("x 3"))
        #expect(TerminalHostState.notification("\t\n") == nil)
        #expect(TerminalHostState.notification("") == nil)
    }

    @Test("Outside a running app the action does nothing")
    func outsideAnApp() {
        EnvironmentValues().requestAttention("nobody hears this")
    }
}
