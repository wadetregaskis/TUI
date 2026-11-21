//  🖥️ TUI — A Terminal UI framework for Swift
//  PostKeyEventTests.swift
//
//  `\.postKeyEvent` (A-POSTKEY-1, 2026-11-20): a key an app posts goes down
//  the whole input chain as a typed one does, the focus path's onKeyPress
//  handlers and the focused control included, its phase as posted; and a key
//  posted from inside a key handler waits for the next frame, never running
//  the chain from inside itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// What the handlers heard, and the action as the views found it, kept for a
/// test to call between frames, as a gamepad's callback would.
@MainActor
private final class PostLog {
    var entries: [String] = []
    var postKeyEvent: PostKeyEventAction?
    /// How deep in key handlers the chain is now, and the deepest it has been.
    var depth = 0
    var deepest = 0
}

/// A focused button inside a container that hears every key, phases and all.
private struct PostPage: View {
    let log: PostLog
    @Environment(\.postKeyEvent) private var postKeyEvent

    var body: some View {
        log.postKeyEvent = postKeyEvent
        return VStack {
            Button("Go") { log.entries.append("button") }
        }
        .onKeyPress(phases: .all) { press in
            log.entries.append("container \(press.phase == .up ? "up" : "down") \(press.characters)")
            return .ignored
        }
    }
}

/// A focusable view whose handler, on P, posts P again: twice more, then no
/// more.
private struct EchoPage: View {
    let log: PostLog
    @Environment(\.postKeyEvent) private var postKeyEvent

    var body: some View {
        let postKeyEvent = postKeyEvent
        return Text("echo").focusable()
            .onKeyPress("p") {
                log.depth += 1
                log.deepest = max(log.deepest, log.depth)
                log.entries.append("p")
                if log.entries.count < 3 { postKeyEvent(KeyEvent(character: "p")) }
                log.depth -= 1
                return .handled
            }
    }
}

// MARK: - Tests

@MainActor
@Suite("Posting a key event through the whole input chain", .serialized)
struct PostKeyEventTests {
    @Test("A posted key reaches the onKeyPress round the focused control, and then the control")
    func reachesTheWholeChain() throws {
        let log = PostLog()
        let app = TestApp(width: 30, height: 6) { PostPage(log: log) }
        app.advance(by: .milliseconds(20))
        let post = try #require(log.postKeyEvent)
        post(KeyEvent(key: .enter))
        #expect(log.entries.isEmpty, "posting delivers nothing while the call returns")
        app.advance(by: .milliseconds(20))
        // The focus path's handler first, then the focused button: what a
        // typed Return reaches, and `FocusManager.dispatchKeyEvent` does not.
        #expect(log.entries == ["container down \r", "button"])
    }

    @Test("A posted release reaches a handler that asks for releases, and nothing else")
    func deliversTheReleasePhase() throws {
        let log = PostLog()
        let app = TestApp(width: 30, height: 6) { PostPage(log: log) }
        app.advance(by: .milliseconds(20))
        let post = try #require(log.postKeyEvent)
        // A TestApp's terminal reports no releases, as a legacy encoding does
        // not: a posted one is delivered all the same.
        post(KeyEvent(key: .enter, phase: .release))
        app.advance(by: .milliseconds(20))
        #expect(log.entries == ["container up \r"], "the button acts on a key going down, not on its release")
    }

    @Test("A key posted from inside a key handler waits for the next frame, not running the chain inside itself")
    func postingFromAHandlerDoesNotRecurse() {
        let log = PostLog()
        let app = TestApp(width: 30, height: 6) { EchoPage(log: log) }
        app.advance(by: .milliseconds(20))
        app.press(.character("p"))
        // The typed P, then each P it posted, one a frame: three handler runs,
        // none of them inside another.
        #expect(log.entries == ["p", "p", "p"])
        #expect(log.deepest == 1, "a posted key was handled inside the handler that posted it")
    }
}
