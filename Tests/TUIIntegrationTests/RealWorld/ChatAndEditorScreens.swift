//  🖥️ TUI — A Terminal UI framework for Swift
//  ChatAndEditorScreens.swift
//
//  Real-world screens: a chat anchored to its bottom that grows as messages
//  arrive, a log that appends while the person reads it, and an editor: a row
//  of buttons, a TextEditor and a status line under it. The newest message
//  must stay in sight, the status line must never be pushed off, and the
//  editor's last line must be reachable.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

/// Messages over a field and a Send button, the newest at the bottom.
private struct ChatPage: View {
    @State private var messages = (1...6).map { "Message \($0)" }
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(messages, id: \.self) { Text($0) }
                }
            }
            .defaultScrollAnchor(.bottom)
            HStack {
                TextField("Message", text: $draft).focusID("draft")
                Button("Send") { messages.append("Message \(messages.count + 1)") }.focusID("send")
            }
        }
    }
}

/// A log of lines over a status line, with a button that appends.
private struct LogPage: View {
    @State private var lines = (1...30).map { "log line \($0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Append") { lines.append("log line \(lines.count + 1)") }.focusID("append")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
            }
            .defaultScrollAnchor(.bottom)
            Text("\(lines.count) lines")
        }
    }
}

/// A toolbar of buttons, a text editor of `lineCount` lines, a status line.
private struct EditorPage: View {
    @State private var text: String

    init(lineCount: Int) {
        _text = State(initialValue: (1...lineCount).map { "line \($0)" }.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Save") {}.focusID("save")
                Button("Undo") {}.focusID("undo")
                Spacer()
            }
            TextEditor(text: $text).focusID("editor")
            Text("Ln 1, Col 1 — UTF-8")
        }
    }
}

@MainActor
@Suite("Real world: chat, log and editor screens")
struct ChatAndEditorScreens {
    @Test("A chat anchored to its bottom: the newest message shows at launch and after each Send",
          arguments: TerminalSize.all)
    func chat(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { ChatPage() }
        LayoutSanity.check(app, "launch")
        #expect(app.screen.contains("Message 6"), "the newest message is not in sight:\n\(app.screen)")
        for _ in 0..<4 where app.focusedID != "send" { app.press(.tab) }
        for sent in 7...12 {
            app.press(.enter)
            LayoutSanity.check(app, "sent \(sent)")
            #expect(app.screen.contains("Message \(sent)"), "message \(sent) is not in sight:\n\(app.screen)")
        }
    }

    @Test("A growing log: the last line and the status line stay in sight", arguments: TerminalSize.all)
    func growingLog(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { LogPage() }
        LayoutSanity.check(app, "launch")
        #expect(app.screen.contains("log line 30"), "the last line is not in sight:\n\(app.screen)")
        for appended in 31...34 {
            app.press(.enter)
            LayoutSanity.check(app, "appended \(appended)")
            #expect(app.screen.contains("log line \(appended)"), "line \(appended) is not in sight:\n\(app.screen)")
            #expect(app.screen.contains("\(appended) lines"), "the status line is gone:\n\(app.screen)")
        }
    }

    @Test("An editor of 80 lines: the status line stays, End of document reaches the last line",
          arguments: TerminalSize.all)
    func editor(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { EditorPage(lineCount: 80) }
        LayoutSanity.check(app, "launch")
        #expect(app.screen.contains("Ln 1"), "the status line is pushed off:\n\(app.screen)")
        for _ in 0..<4 where app.focusedID != "editor" { app.press(.tab) }
        #expect(app.focusedID == "editor")
        LayoutSanity.reach("line 80", in: app, by: .pageDown, limit: 60)
        #expect(app.screen.contains("Ln 1"), "the status line is pushed off:\n\(app.screen)")
        app.type("tail")
        LayoutSanity.check(app, "typed")
    }

    @Test("An editor of 3 lines: no filler between its lines, the wheel moves nothing out of place",
          arguments: TerminalSize.all)
    func shortEditor(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { EditorPage(lineCount: 3) }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectContiguous(app, ["line 1", "line 2", "line 3"], "the editor's lines")
        app.scroll(.down, by: 3, at: CellPoint(x: 2, y: 2))
        LayoutSanity.check(app, "wheel")
    }
}
