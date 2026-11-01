//  🖥️ TUI — A Terminal UI framework for Swift
//  SwipeWheelTests.swift
//
//  A list row's swipe actions revealed by the horizontal wheel — what a
//  trackpad's sideways swipe sends where a terminal reports it (owner,
//  2026-10-26, A48): a burst of ticks is one gesture; the first reveals, a
//  second the same way is the full swipe, one the other way slides them away;
//  and sideways ticks leaked into a vertical scroll reveal nothing. Replayed
//  as bytes through the terminal's own parser as well as as events.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Inbox {
    var ran: [String] = []
}

private struct InboxApp: App {
    let inbox: Inbox?

    init() { inbox = nil }

    init(_ inbox: Inbox) { self.inbox = inbox }

    var body: some Scene {
        WindowGroup {
            if let inbox {
                List {
                    ForEach(1...3, id: \.self) { index in
                        Text("message\(index)")
                            .swipeActions {
                                Button("Delete", role: .destructive) { inbox.ran.append("delete\(index)") }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Unread") { inbox.ran.append("unread\(index)") }
                            }
                    }
                }
            }
        }
        .mouseSupport(.full)
    }
}

@MainActor
private final class Harness {
    let inbox = Inbox()
    let app: TestApp
    private var now: Int64 = 0

    init() {
        app = TestApp(InboxApp(inbox), width: 40, height: 10)
        frame()
        frame()
    }

    /// One frame, `milliseconds` after the last: the time the next events
    /// arrive at.
    func frame(after milliseconds: Int64 = 16) {
        now += milliseconds * 1_000_000
        app.frame(atNanos: now)
    }

    /// A burst of `ticks` wheel ticks over `row`'s text, a frame apart, as a
    /// trackpad's swipe sends them, then a pause longer than a burst's gap.
    func burst(_ button: MouseButton, over row: String, ticks: Int = 6) throws {
        try burst(button, at: position(of: row), ticks: ticks)
    }

    /// The same at `point` — for a row whose text revealed actions now cover.
    func burst(_ button: MouseButton, at point: (x: Int, y: Int), ticks: Int = 6) throws {
        for _ in 0..<ticks {
            app.send(MouseEvent(button: button, phase: .pressed, x: point.x, y: point.y))
            frame(after: 8)
        }
        frame(after: 400)
    }

    func shows(_ text: String) -> Bool { app.screen.contains(text) }

    func position(of text: String) throws -> (x: Int, y: Int) {
        let y = try #require(app.screen.styledLines.firstIndex { $0.stripped.contains(text) }, "\(text) is not drawn")
        let line = app.screen.styledLines[y].stripped
        let range = try #require(line.range(of: text))
        return (line.distance(from: line.startIndex, to: range.lowerBound), y)
    }

    var screen: String { app.screen.lines.joined(separator: "\n") }
}

@MainActor
@Suite("A list row's swipe actions, from the horizontal wheel", .serialized)
struct SwipeWheelTests {
    @Test("A burst to the right reveals the row's trailing actions, on that row, the cursor moved there")
    func burstReveals() throws {
        let harness = Harness()
        try harness.burst(.scrollRight, over: "message2")
        let delete = try harness.position(of: "Delete")
        #expect(harness.app.screen.styledLines[delete.y].stripped.contains("message2"), "\(harness.screen)")
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.inbox.ran == ["delete2"], "one burst revealed and pressed nothing: \(harness.inbox.ran)")
    }

    @Test("A second burst the same way is the full swipe; one the other way slides them away")
    func secondBurst() throws {
        let harness = Harness()
        try harness.burst(.scrollRight, over: "message1")
        try harness.burst(.scrollRight, over: "message1")
        #expect(harness.inbox.ran == ["delete1"])
        #expect(!harness.shows("Delete"), "\(harness.screen)")
        let third = try harness.position(of: "message3")
        try harness.burst(.scrollLeft, at: third)
        #expect(harness.shows("Unread"), "\(harness.screen)")
        try harness.burst(.scrollRight, at: third)
        #expect(!harness.shows("Unread"), "\(harness.screen)")
        #expect(harness.inbox.ran == ["delete1"])
    }

    @Test("Sideways ticks inside a vertical scroll reveal nothing")
    func axisLock() throws {
        let harness = Harness()
        let point = try harness.position(of: "message2")
        harness.app.send(MouseEvent(button: .scrollDown, phase: .pressed, x: point.x, y: point.y))
        harness.frame(after: 8)
        harness.app.send(MouseEvent(button: .scrollRight, phase: .pressed, x: point.x, y: point.y))
        harness.frame(after: 8)
        #expect(!harness.shows("Delete"), "\(harness.screen)")
    }

    /// A trackpad swipe as Apple Terminal and iTerm2 report it: SGR wheel
    /// reports, button 67 (wheel right) at the pointer's cell, several per read
    /// and one split across two reads. Representative, not recorded: a
    /// recording needs a person at a trackpad (owed, A48).
    @Test("A swipe's bytes, through the terminal's own parser, reveal and then full-swipe")
    func bytesThroughTheParser() throws {
        let harness = Harness()
        let point = try harness.position(of: "message1")
        let report = Array("\u{1B}[<67;\(point.x + 1);\(point.y + 1)M".utf8)
        let terminal = Terminal()
        let queue = ByteQueue()
        terminal.readSource = { buffer in
            guard !queue.bytes.isEmpty else { return 0 }
            let count = min(queue.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = queue.bytes[index] }
            queue.bytes.removeFirst(count)
            return count
        }
        func swipe() {
            // Three reads of two reports each, the last split mid-sequence.
            for read in 0..<3 {
                queue.bytes += report + report
                if read == 2 { queue.bytes += report.prefix(4) }
                while let input = terminal.readEvent() {
                    if case .mouse(let event) = input { harness.app.send(event) }
                }
                if read == 2 {
                    queue.bytes += report.dropFirst(4)
                    while let input = terminal.readEvent() {
                        if case .mouse(let event) = input { harness.app.send(event) }
                    }
                }
                harness.frame(after: 8)
            }
            harness.frame(after: 400)
        }
        swipe()
        #expect(harness.shows("Delete"), "\(harness.screen)")
        swipe()
        #expect(harness.inbox.ran == ["delete1"], "\(harness.inbox.ran)")
    }
}

/// The byte source's queue, shared by the read closure and the test.
private final class ByteQueue {
    var bytes: [UInt8] = []
}
