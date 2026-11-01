//  🖥️ TUI — A Terminal UI framework for Swift
//  SwipeActionsTests.swift
//
//  A list row's swipe actions (owner, 2026-10-26, A48): revealed from the
//  keyboard on the cursor row — ⇧→ the leading edge's, ⇧← the trailing
//  edge's, ⌃L and ⌃T the same — drawn over the row's edge, holding the keys
//  while revealed (←/→ and Tab move, Return presses, Escape slides them away),
//  the same chord again the full swipe; a click on one presses it, a click
//  elsewhere slides them away.
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
private final class Mail {
    var ran: [String] = []
    var allowsFullSwipe = true
}

private struct MailApp: App {
    let mail: Mail?

    init() { mail = nil }

    init(_ mail: Mail) { self.mail = mail }

    var body: some Scene {
        WindowGroup {
            if let mail { MailPage(mail: mail) }
        }
        .mouseSupport(.full)
    }
}

private struct MailPage: View {
    let mail: Mail

    var body: some View {
        List {
            ForEach(1...3, id: \.self) { index in
                Text("message\(index)")
                    .swipeActions(allowsFullSwipe: mail.allowsFullSwipe) {
                        Button("Delete", role: .destructive) { mail.ran.append("delete\(index)") }
                        Button("Flag") { mail.ran.append("flag\(index)") }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Unread") { mail.ran.append("unread\(index)") }
                    }
            }
        }
    }
}

@MainActor
private final class Harness {
    let mail = Mail()
    let app: TestApp
    private var now: Int64 = 0

    init(allowsFullSwipe: Bool = true) {
        mail.allowsFullSwipe = allowsFullSwipe
        app = TestApp(MailApp(mail), width: 40, height: 10)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func key(_ key: Key, shift: Bool = false, ctrl: Bool = false) {
        app.send(KeyEvent(key: key, ctrl: ctrl, shift: shift))
        frame()
    }

    func shows(_ text: String) -> Bool { app.screen.contains(text) }

    func position(of text: String) throws -> (x: Int, y: Int) {
        let y = try #require(app.screen.styledLines.firstIndex { $0.stripped.contains(text) }, "\(text) is not drawn")
        let line = app.screen.styledLines[y].stripped
        let range = try #require(line.range(of: text))
        return (line.distance(from: line.startIndex, to: range.lowerBound), y)
    }

    func click(_ point: (x: Int, y: Int)) {
        app.send(MouseEvent(button: .left, phase: .pressed, x: point.x, y: point.y))
        app.send(MouseEvent(button: .left, phase: .released, x: point.x, y: point.y))
        frame()
    }

    var screen: String { app.screen.lines.joined(separator: "\n") }
}

@MainActor
@Suite("A list row's swipe actions", .serialized)
struct SwipeActionsTests {
    @Test("No actions are drawn until revealed")
    func hiddenAtFirst() {
        let harness = Harness()
        #expect(!harness.shows("Delete") && !harness.shows("Unread"), "\(harness.screen)")
    }

    @Test("⇧← reveals the trailing actions on the cursor row's line; Return presses the first")
    func trailingReveal() throws {
        let harness = Harness()
        harness.key(.left, shift: true)
        let delete = try harness.position(of: "Delete")
        let row = try harness.position(of: "message1")
        #expect(delete.y == row.y && delete.x > row.x, "\(harness.screen)")
        #expect(harness.shows("Flag"))
        harness.key(.enter)
        #expect(harness.mail.ran == ["delete1"])
        #expect(!harness.shows("Delete"), "pressing slid them away: \(harness.screen)")
    }

    @Test("→ moves to the next action, round the ends, and Return presses it")
    func arrowsMove() {
        let harness = Harness()
        harness.key(.left, shift: true)
        harness.key(.right)
        harness.key(.enter)
        #expect(harness.mail.ran == ["flag1"])
    }

    @Test("⇧→ reveals the leading actions, at the row's start")
    func leadingReveal() throws {
        let harness = Harness()
        harness.key(.down)
        harness.key(.right, shift: true)
        let unread = try harness.position(of: "Unread")
        let row = try #require(harness.app.screen.styledLines.firstIndex { $0.stripped.contains("message2") || $0.stripped.contains("Unread") })
        #expect(unread.y == row, "\(harness.screen)")
        harness.key(.enter)
        #expect(harness.mail.ran == ["unread2"])
    }

    @Test("The same chord again is the full swipe; where it is not allowed it only slides them away")
    func fullSwipe() {
        let harness = Harness()
        harness.key(.left, shift: true)
        harness.key(.left, shift: true)
        #expect(harness.mail.ran == ["delete1"])
        #expect(!harness.shows("Delete"), "\(harness.screen)")
        let refusing = Harness(allowsFullSwipe: false)
        refusing.key(.left, shift: true)
        refusing.key(.left, shift: true)
        #expect(refusing.mail.ran.isEmpty)
        #expect(!refusing.shows("Delete"), "\(refusing.screen)")
    }

    @Test("⌃T and ⌃L reveal as ⇧← and ⇧→ do")
    func controlChords() {
        let harness = Harness()
        harness.key(.character("t"), ctrl: true)
        #expect(harness.shows("Delete"), "\(harness.screen)")
        harness.key(.escape)
        harness.key(.character("l"), ctrl: true)
        #expect(harness.shows("Unread"), "\(harness.screen)")
    }

    @Test("Escape slides them away and the list has its keys back")
    func escapeHides() {
        let harness = Harness()
        harness.key(.left, shift: true)
        harness.key(.escape)
        #expect(!harness.shows("Delete"), "\(harness.screen)")
        harness.key(.down)
        harness.key(.left, shift: true)
        harness.key(.enter)
        #expect(harness.mail.ran == ["delete2"], "Down moved the cursor: \(harness.mail.ran)")
    }

    @Test("A click on an action presses it; a click elsewhere slides them away")
    func pointer() throws {
        let harness = Harness()
        harness.key(.left, shift: true)
        harness.click(try harness.position(of: "Flag"))
        #expect(harness.mail.ran == ["flag1"])
        harness.key(.left, shift: true)
        harness.click(try harness.position(of: "message3"))
        #expect(!harness.shows("Delete"), "\(harness.screen)")
        #expect(harness.mail.ran == ["flag1"])
    }
}
