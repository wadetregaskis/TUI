//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardWriterTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - A writer with stated answers

/// What a test writer was asked to do with this machine's clipboard.
final class SystemClipboardLog: @unchecked Sendable {
    var writes: [String] = []
}

extension ClipboardWriter {
    /// A writer whose terminal, locality and helper are the test's.
    static func stated(
        terminal: TerminalClient.ClipboardWriteSupport, isLocal: Bool, hasHelper: Bool = true,
        helperWorks: Bool = true, log: SystemClipboardLog = SystemClipboardLog(),
        now: @escaping @Sendable () -> UInt64 = { 0 }
    ) -> ClipboardWriter {
        ClipboardWriter(
            terminalSupport: { terminal }, isLocal: { isLocal }, hasSystemHelper: hasHelper,
            systemWrite: { text in
                log.writes.append(text)
                return helperWorks
            },
            systemRead: { log.writes.last }, nowNanos: now, requestFrame: {})
    }
}

// MARK: - The sequence

@Suite("OSC 52: the write's spelling")
struct ClipboardSequenceTests {
    @Test("A copy is ESC ] 52 ; c ; base64 ESC backslash")
    func spelling() {
        #expect(ClipboardSequence.write("hi") == "\u{1B}]52;c;aGk=\u{1B}\\")
    }

    /// Ghostty clears the clipboard on a payload that is not valid base64, and
    /// an empty payload is the cheapest way to send one.
    @Test("An empty copy sends nothing at all")
    func emptySendsNothing() {
        #expect(ClipboardSequence.write("") == nil)
    }

    /// Foundation can wrap base64 at 64 or 76 characters; a line break inside
    /// the payload makes it invalid, and Ghostty clears the clipboard.
    @Test("A long, multi-line, non-ASCII copy is one unwrapped, valid payload")
    func longPayloadIsUnwrapped() throws {
        let text = String(repeating: "Größe 😀 ありがとう\n\ttabbed line\r\n", count: 200)
        let sequence = try #require(ClipboardSequence.write(text))
        let prefix = "\u{1B}]52;c;"
        let suffix = "\u{1B}\\"
        #expect(sequence.hasPrefix(prefix))
        #expect(sequence.hasSuffix(suffix))
        let payload = String(sequence.dropFirst(prefix.count).dropLast(suffix.count))
        #expect(!payload.contains("\n") && !payload.contains("\r"))
        #expect(payload.allSatisfy { $0.isLetter || $0.isNumber || "+/=".contains($0) })
        let decoded = try #require(Data(base64Encoded: payload))
        #expect(String(bytes: decoded, encoding: .utf8) == text)
    }

    @Test("One selector, and it is c")
    func oneSelector() throws {
        let sequence = try #require(ClipboardSequence.write("x"))
        #expect(sequence.components(separatedBy: ";").count == 3)
        #expect(sequence.components(separatedBy: ";")[1] == "c")
    }
}

// MARK: - The terminal's answer

@Suite("OSC 52: which terminals write it")
struct ClipboardTerminalSupportTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let environment: [String: String]
        let program: TerminalClient.Program
        let deviceAttributes: String?
        let tmuxSetClipboard: String?
        let expected: TerminalClient.ClipboardWriteSupport
        var testDescription: String { name }

        static let rows: [Self] = [
            Self(
                name: "Ghostty", environment: [:], program: .ghostty, deviceAttributes: nil,
                tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "iTerm2, its setting unknowable", environment: [:], program: .iTerm2,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .unconfirmed),
            Self(
                name: "Apple Terminal", environment: [:], program: .appleTerminal, deviceAttributes: nil,
                tmuxSetClipboard: nil, expected: .unsupported),
            Self(
                name: "Warp, unmeasured", environment: [:], program: .warp, deviceAttributes: nil,
                tmuxSetClipboard: nil, expected: .unsupported),
            Self(
                name: "An unidentified terminal", environment: ["TERM": "xterm-256color"],
                program: .unidentified, deviceAttributes: "\u{1B}[?62;22c", tmuxSetClipboard: nil,
                expected: .unsupported),
            Self(
                name: "kitty over ssh, by TERM", environment: ["TERM": "xterm-kitty"], program: .unidentified,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "kitty, by its window id", environment: ["KITTY_WINDOW_ID": "1"],
                program: .unidentified, deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "WezTerm", environment: ["TERM_PROGRAM": "WezTerm"], program: .unidentified,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "foot", environment: ["TERM": "foot-extra"], program: .unidentified,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "An unknown terminal whose DA1 lists 52", environment: [:], program: .unidentified,
                deviceAttributes: "\u{1B}[?64;1;2;4;6;17;18;21;22;52c", tmuxSetClipboard: nil,
                expected: .unconfirmed),
            Self(
                name: "DA1 never takes a terminal off", environment: [:], program: .ghostty,
                deviceAttributes: "\u{1B}[?62;22c", tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "tmux, set-clipboard on", environment: [:], program: .tmux, deviceAttributes: nil,
                tmuxSetClipboard: "on", expected: .unconfirmed),
            Self(
                name: "tmux, set-clipboard external (its default)", environment: [:], program: .tmux,
                deviceAttributes: nil, tmuxSetClipboard: "external", expected: .unsupported),
            Self(
                name: "tmux, not answering", environment: [:], program: .tmux, deviceAttributes: nil,
                tmuxSetClipboard: nil, expected: .unsupported),
            Self(
                name: "tmux ignores a kitty variable left over from the server's start",
                environment: ["KITTY_WINDOW_ID": "1"], program: .tmux, deviceAttributes: nil,
                tmuxSetClipboard: "external", expected: .unsupported),
            // GNU screen drops an application's OSC 52; the terminal its
            // environment names (inherited, and stale once reattached) wrote
            // "Sent" (iTerm2) or "Copied" (Ghostty) of a write screen dropped.
            Self(
                name: "Inside GNU screen, in iTerm2", environment: ["STY": "4242.pts-0.desk", "TERM_PROGRAM": "iTerm.app"],
                program: .iTerm2, deviceAttributes: nil, tmuxSetClipboard: nil, expected: .unsupported),
            Self(
                name: "Inside GNU screen, in Ghostty", environment: ["STY": "4242.pts-0.desk"], program: .ghostty,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .unsupported),
            Self(
                name: "Inside GNU screen, in kitty by TERM", environment: ["STY": "4242.pts-0.desk", "TERM": "xterm-kitty"],
                program: .unidentified, deviceAttributes: "\u{1B}[?64;52c", tmuxSetClipboard: nil,
                expected: .unsupported),
            Self(
                name: "TUIKIT_OSC52=1 outranks screen", environment: ["TUIKIT_OSC52": "1", "STY": "4242.pts-0.desk"],
                program: .appleTerminal, deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "TUIKIT_OSC52=1 turns it on", environment: ["TUIKIT_OSC52": "1"],
                program: .appleTerminal, deviceAttributes: nil, tmuxSetClipboard: nil, expected: .honoured),
            Self(
                name: "TUIKIT_OSC52=0 turns it off", environment: ["TUIKIT_OSC52": "0"], program: .ghostty,
                deviceAttributes: nil, tmuxSetClipboard: nil, expected: .unsupported),
        ]
    }

    @Test("The ladder", arguments: Row.rows)
    func ladder(_ row: Row) {
        #expect(
            TerminalClient.clipboardWrites(
                environment: row.environment, program: row.program,
                primaryDeviceAttributes: row.deviceAttributes, tmuxSetClipboard: row.tmuxSetClipboard)
                == row.expected)
    }

    /// An exit test, because it is about the live answer, which reads the
    /// process's environment and the process-wide simulated program. Apple
    /// Terminal is named before any detector runs, so the answer cannot be the
    /// terminal running the suite.
    @Test("Simulating a program does not send copies to a terminal that is not there")
    func simulationDoesNotChangeTheAnswer() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                for name in ["TUIKIT_OSC52", "TMUX", "KITTY_WINDOW_ID", "LC_TERMINAL"] {
                    ProcessWideState.setEnvironment(name, to: nil)
                }
                ProcessWideState.setEnvironment("TUIKIT_TERM_PROGRAM", to: "Apple_Terminal")
                ProcessWideState.setEnvironment("TERM", to: "xterm-256color")
                #expect(TerminalClient.clipboardWrites == .unsupported)
                ProcessWideState.simulated = .ghostty
                #expect(
                    TerminalClient.clipboardWrites == .unsupported,
                    "drawn as Ghostty, the copy still goes to the Apple Terminal in front of the user")
            }
        }
    }

    @Test("Only Ghostty, of the programs TUIkit knows, writes by default")
    func honouredPrograms() {
        let honoured = TerminalClient.Program.allCases.filter(TerminalClient.honoursClipboardWrites)
        #expect(honoured == [.ghostty])
    }

    @Test("DA1's 52 is a parameter, not a substring")
    func deviceAttributesParameter() {
        #expect(TerminalClient.deviceAttributesAdvertiseClipboard("\u{1B}[?1;2;52c"))
        #expect(!TerminalClient.deviceAttributesAdvertiseClipboard("\u{1B}[?1;2;152c"))
        #expect(!TerminalClient.deviceAttributesAdvertiseClipboard("\u{1B}[?521c"))
        #expect(!TerminalClient.deviceAttributesAdvertiseClipboard("\u{1B}[>52c"))
    }
}

// MARK: - The route

@Suite("Clipboard: the one route a copy takes")
struct ClipboardRouteTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let terminal: TerminalClient.ClipboardWriteSupport
        let hasHelper: Bool
        let isLocal: Bool
        let expected: ClipboardRoute
        var testDescription: String { "\(terminal), helper \(hasHelper), local \(isLocal)" }
    }

    static let rows: [Row] = [
        // A terminal that writes by default is used over ssh and at the desk alike.
        Row(terminal: .honoured, hasHelper: true, isLocal: true, expected: .terminal(confirmed: true)),
        Row(terminal: .honoured, hasHelper: true, isLocal: false, expected: .terminal(confirmed: true)),
        // This machine's clipboard only when it is the user's, and then it beats a maybe.
        Row(terminal: .unconfirmed, hasHelper: true, isLocal: true, expected: .system),
        Row(terminal: .unsupported, hasHelper: true, isLocal: true, expected: .system),
        Row(terminal: .unconfirmed, hasHelper: true, isLocal: false, expected: .terminal(confirmed: false)),
        Row(terminal: .unconfirmed, hasHelper: false, isLocal: true, expected: .terminal(confirmed: false)),
        // Never the server's clipboard.
        Row(terminal: .unsupported, hasHelper: true, isLocal: false, expected: .none),
        Row(terminal: .unsupported, hasHelper: false, isLocal: true, expected: .none),
    ]

    @Test("The rule", arguments: rows)
    func rule(_ row: Row) {
        #expect(
            ClipboardRoute.choose(terminal: row.terminal, hasSystemHelper: row.hasHelper, isLocal: { row.isLocal })
                == row.expected)
    }

    @Test("Locality is not asked when the terminal settles it")
    func localityAskedOnlyWhenNeeded() {
        var asked = false
        _ = ClipboardRoute.choose(terminal: .honoured, hasSystemHelper: true) {
            asked = true
            return true
        }
        #expect(!asked)
    }
}

// MARK: - The writer

@MainActor
@Suite("Clipboard writer")
struct ClipboardWriterTests {
    @Test("A terminal that writes by default is sent the copy, queued for the next frame")
    func honouredTerminal() {
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: true, log: log)
        #expect(writer.write("hi", announcingSuccess: false) == .copied)
        #expect(log.writes.isEmpty)
        #expect(writer.takePendingSequences() == "\u{1B}]52;c;aGk=\u{1B}\\")
        #expect(writer.takePendingSequences().isEmpty)
    }

    @Test("At the desk, a terminal that may not write it gives way to this machine's clipboard")
    func localBeatsUnconfirmed() {
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(terminal: .unconfirmed, isLocal: true, log: log)
        #expect(writer.write("hi", announcingSuccess: false) == .copied)
        #expect(log.writes == ["hi"])
        #expect(writer.takePendingSequences().isEmpty)
    }

    @Test("Over ssh, the server's clipboard is never written")
    func remoteNeverWritesTheServer() {
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, log: log)
        #expect(writer.write("secret", announcingSuccess: false) == .unavailable)
        #expect(log.writes.isEmpty)
        #expect(writer.takePendingSequences().isEmpty)
        #expect(writer.statusNote(atNanos: 0)?.text == ClipboardWriteResult.unavailable.statusLine)
    }

    @Test("A maybe is reported as sent, not as copied")
    func unconfirmedIsSent() {
        let writer = ClipboardWriter.stated(terminal: .unconfirmed, isLocal: false)
        #expect(writer.write("hi", announcingSuccess: false) == .sentToTerminal)
        #expect(writer.takePendingSequences().contains("\u{1B}]52;c;"))
        #expect(writer.statusNote(atNanos: 0)?.text == ClipboardWriteResult.sentToTerminal.statusLine)
    }

    @Test("A failed helper is reported")
    func helperFails() {
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, helperWorks: false)
        #expect(writer.write("hi", announcingSuccess: false) == .failed)
        #expect(writer.statusNote(atNanos: 0)?.text == ClipboardWriteResult.failed.statusLine)
    }

    @Test("An empty copy sends nothing and says nothing")
    func emptyCopy() {
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: true, log: log)
        #expect(writer.write("", announcingSuccess: true) == .nothingToCopy)
        #expect(writer.takePendingSequences().isEmpty)
        #expect(log.writes.isEmpty)
        #expect(writer.statusNote(atNanos: 0) == nil)
    }

    @Test("A plain success is announced only when asked")
    func quietSuccess() {
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: true)
        writer.write("a", announcingSuccess: false)
        #expect(writer.statusNote(atNanos: 0) == nil)
        writer.write("b", announcingSuccess: true)
        #expect(writer.statusNote(atNanos: 0)?.text == ClipboardWriteResult.copied.statusLine)
    }

    @Test("The status line goes after three seconds")
    func noteExpires() throws {
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, now: { 1_000 })
        writer.write("x", announcingSuccess: false)
        let note = try #require(writer.statusNote(atNanos: 1_000))
        #expect(note.expiresAtNanos == 1_000 + ClipboardWriter.noteDuration)
        #expect(writer.statusNote(atNanos: note.expiresAtNanos - 1) != nil)
        #expect(writer.statusNote(atNanos: note.expiresAtNanos) == nil)
    }

    @Test("A paste chord reads this machine's clipboard only when it is the user's")
    func readsOnlyHere() {
        let log = SystemClipboardLog()
        log.writes = ["on this machine"]
        #expect(ClipboardWriter.stated(terminal: .honoured, isLocal: true, log: log).read() == "on this machine")
        #expect(ClipboardWriter.stated(terminal: .honoured, isLocal: false, log: log).read() == nil)
        #expect(
            ClipboardWriter.stated(terminal: .unsupported, isLocal: true, hasHelper: false, log: log).read() == nil)
    }

    /// Over ssh the server's clipboard is not read, but what the app copied
    /// itself is the app's to give back, as the server's pasteboard used to.
    @Test("Away from this machine a paste chord finds the app's own latest copy, whatever became of it")
    func readsTheAppsOwnCopyAway() {
        let log = SystemClipboardLog()
        log.writes = ["someone else's"]
        for terminal in [TerminalClient.ClipboardWriteSupport.honoured, .unconfirmed, .unsupported] {
            let writer = ClipboardWriter.stated(terminal: terminal, isLocal: false, log: log)
            writer.write("first", announcingSuccess: false)
            writer.write("mine", announcingSuccess: false)
            writer.write("", announcingSuccess: false)
            #expect(writer.read() == "mine")
        }
        #expect(log.writes == ["someone else's"])
        // Here, this machine's clipboard is the truth, whatever the app copied.
        let here = ClipboardWriter.stated(terminal: .honoured, isLocal: true, log: log)
        here.write("mine", announcingSuccess: false)
        #expect(here.read() == "someone else's")
    }

    /// Away from this machine — over ssh, or under a session keeper at the
    /// desk, where the desk's clipboard is no longer read — the app's own copy
    /// may be older than what the user last copied on their machine: the
    /// status bar says which it was, and where theirs is.
    @Test("A paste chord that finds the app's own copy says so")
    func pasteOfTheAppsCopySaysSo() {
        let writer = ClipboardWriter.stated(terminal: .honoured, isLocal: false)
        writer.write("mine", announcingSuccess: false)
        #expect(writer.statusNote(atNanos: 0) == nil)
        #expect(writer.read() == "mine")
        #expect(
            writer.statusNote(atNanos: 0)?.text
                == LocalizationService.shared.string(for: LocalizationKey.StatusBar.pastedAppCopy))
    }

    @Test("A paste chord that finds nothing says to use the terminal's paste")
    func emptyPasteSaysSo() {
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: false)
        #expect(writer.statusNote(atNanos: 0) == nil)
        #expect(writer.read() == nil)
        #expect(
            writer.statusNote(atNanos: 0)?.text
                == LocalizationService.shared.string(for: LocalizationKey.StatusBar.pasteWithTerminal))
        // One that finds something says nothing.
        let found = ClipboardWriter.stated(terminal: .unsupported, isLocal: true)
        _ = found.read()
        #expect(found.statusNote(atNanos: 0) == nil)
    }

    @Test("A writer asks for the frame that sends its copy")
    func requestsAFrame() {
        let frames = SystemClipboardLog()
        let writer = ClipboardWriter(
            terminalSupport: { .honoured }, isLocal: { false }, hasSystemHelper: false,
            systemWrite: { _ in false }, systemRead: { nil }, nowNanos: { 0 },
            requestFrame: { frames.writes.append("frame") })
        writer.write("x", announcingSuccess: false)
        #expect(frames.writes == ["frame"])
    }
}

// MARK: - This machine's helpers

@Suite("Clipboard: this machine's helpers")
struct SystemClipboardHelperTests {
    #if os(macOS)
        @Test("macOS copies with pbcopy and pastes with pbpaste")
        func macOS() {
            let helpers = SystemClipboard.helpers(environment: [:], exists: { _ in true })
            #expect(helpers.map(\.copyTool) == ["/usr/bin/pbcopy"])
            #expect(helpers.map(\.pasteTool) == ["/usr/bin/pbpaste"])
        }
    #else
        @Test("Wayland first, then X11, and only with a display to talk to")
        func linux() {
            let all: (String) -> Bool = { _ in true }
            let both = SystemClipboard.helpers(
                environment: ["WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0"], exists: all)
            #expect(both.map(\.copyTool) == ["/usr/bin/wl-copy", "/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(both.first?.pasteTool == "/usr/bin/wl-paste")
            let x11 = SystemClipboard.helpers(environment: ["DISPLAY": ":0"], exists: all)
            #expect(x11.map(\.copyTool) == ["/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(SystemClipboard.helpers(environment: [:], exists: all).isEmpty)
        }
    #endif
}

// MARK: - Through a field, and out of the run loop

@MainActor
@Suite("Clipboard writer, in an app")
struct ClipboardWriterAppTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct FieldPage: View {
        let text: Box
        var body: some View {
            TextField("Field", text: Binding(get: { text.value }, set: { text.value = $0 }))
        }
    }

    /// A field takes the clipboard of the environment it is created in, which
    /// in an app is the app's writer — not the headless one, which knows no
    /// terminal and would write this machine's clipboard over ssh.
    @Test("A field's Ctrl-C goes through the app's writer", arguments: [true, false])
    func fieldCopiesThroughTheWriter(confirmed: Bool) {
        let writer = ClipboardWriter.stated(terminal: confirmed ? .honoured : .unconfirmed, isLocal: false)
        let harness = InputChainHarness { $0.clipboardAccess = ClipboardAccess(writer: writer) }
        let page = FieldPage(text: Box("abcd"))
        harness.frame(page)
        harness.frame(page)
        for _ in 0..<2 {
            harness.press(KeyEvent(key: .left, shift: true))
            harness.frame(page)
        }
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        #expect(writer.takePendingSequences() == ClipboardSequence.write("cd"))
        // A field's success is quiet; a maybe is not.
        #expect((writer.statusNote(atNanos: 0) != nil) == !confirmed)
    }

    /// Over ssh this machine's clipboard is the server's: a paste chord must
    /// not bring its contents — someone else's — into the field. (Nor
    /// anything else here: the app has copied nothing.)
    @Test("A field's Ctrl-V reads this machine's clipboard only at this machine", arguments: [true, false])
    func fieldPastesOnlyHere(isLocal: Bool) {
        let log = SystemClipboardLog()
        log.writes = ["server"]
        let writer = ClipboardWriter.stated(terminal: .unconfirmed, isLocal: isLocal, log: log)
        let harness = InputChainHarness { $0.clipboardAccess = ClipboardAccess(writer: writer) }
        let text = Box("")
        let page = FieldPage(text: text)
        harness.frame(page)
        harness.frame(page)
        harness.press(KeyEvent(key: .character("v"), ctrl: true))
        harness.frame(page)
        #expect(text.value == (isLocal ? "server" : ""))
    }

    struct TwoFields: View {
        let first: Box
        let second: Box
        var body: some View {
            VStack {
                TextField("First", text: Binding(get: { first.value }, set: { first.value = $0 }))
                TextField("Second", text: Binding(get: { second.value }, set: { second.value = $0 }))
            }
        }
    }

    /// The round trip the server's pasteboard used to carry over ssh, before
    /// the clipboard stopped writing it.
    @Test("Over ssh a field's Ctrl-C pastes into another field with Ctrl-V")
    func fieldRoundTripAway() {
        let log = SystemClipboardLog()
        log.writes = ["server"]
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, log: log)
        let harness = InputChainHarness { $0.clipboardAccess = ClipboardAccess(writer: writer) }
        let page = TwoFields(first: Box("abcd"), second: Box(""))
        harness.frame(page)
        harness.frame(page)
        for _ in 0..<2 {
            harness.press(KeyEvent(key: .left, shift: true))
            harness.frame(page)
        }
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        harness.frame(page)
        harness.press(KeyEvent(key: .tab))
        harness.frame(page)
        harness.press(KeyEvent(key: .character("v"), ctrl: true))
        harness.frame(page)
        #expect(page.second.value == "cd")
        #expect(log.writes == ["server"], "and the server's clipboard was neither written nor read")
    }

    struct Token: CustomStringConvertible, Equatable {
        let name: String
        var description: String { name }
    }

    final class Tokens: @unchecked Sendable {
        var pasted: [Token] = []
        var buttoned: [Token] = []
    }

    @Test("Over ssh a value the app copied pastes back as itself, by the chord and by a PasteButton")
    func valueRoundTripAway() {
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: false)
        let typed = TypedClipboard()
        func harness() -> InputChainHarness {
            InputChainHarness {
                $0.clipboardAccess = ClipboardAccess(writer: writer)
                $0.typedClipboard = typed
            }
        }
        let tokens = Tokens()
        let chords = [KeyEvent(key: .character("c"), ctrl: true), KeyEvent(key: .character("v"), ctrl: true)]
        let consumed = harness().play(chords) {
            Text("token").focusable()
                .copyable([Token(name: "ace")])
                .pasteDestination(for: Token.self) { tokens.pasted += $0 }
        }
        #expect(consumed == [true, true])
        #expect(tokens.pasted == [Token(name: "ace")])
        _ = harness().play([KeyEvent(key: .enter)]) {
            PasteButton(payloadType: Token.self) { tokens.buttoned += $0 }
        }
        #expect(tokens.buttoned == [Token(name: "ace")])
    }

    struct Page: App {
        var body: some Scene {
            WindowGroup { Text("PAGE") }
        }
    }

    @Test("The run loop writes a queued copy, and the status bar says what became of it")
    func runLoopSendsAndSays() {
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .unconfirmed, isLocal: false, now: { 0 })
        let harness = RenderLoopHarness(tuiContext: tui)
        let loop = harness.loop(Page())
        loop.render(frameNowNanos: 0)
        tui.clipboardWriter.write("hi", announcingSuccess: false)
        loop.render(frameNowNanos: 1)
        #expect(harness.terminal.allOutput.contains("\u{1B}]52;c;aGk=\u{1B}\\"))
        let line = ClipboardWriteResult.sentToTerminal.statusLine ?? "?"
        #expect(harness.terminal.allOutput.contains(line))
    }

    /// e7ce4b0f7's question, answered (decisions D4X, "Review 2"): Ctrl-Z
    /// draws one frame at `.background` before the terminal is handed back
    /// (`renderOutsidePacer`, then `suspendUntilContinued`), and that frame
    /// writes a copy still queued, as every frame does.
    @Test("The frame drawn at .background before a suspend writes a queued copy")
    func backgroundFrameSendsTheQueue() {
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .honoured, isLocal: false, now: { 0 })
        let harness = RenderLoopHarness(tuiContext: tui)
        let loop = harness.loop(Page())
        loop.render(frameNowNanos: 0)
        tui.clipboardWriter.write("hi", announcingSuccess: false)
        tui.scenePhase = .background
        loop.render(frameNowNanos: 1)
        #expect(harness.terminal.allOutput.contains("\u{1B}]52;c;aGk=\u{1B}\\"))
        #expect(tui.clipboardWriter.takePendingSequences().isEmpty)
    }

    /// The same page filling the window down to a last row, with the line of
    /// key hints in the bottom bar: a row the bar gains moves the last row up.
    struct HintedPage: App {
        var body: some Scene {
            WindowGroup {
                VStack(spacing: 0) {
                    Spacer()
                    Text("LAST")
                }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
            }
        }
    }

    /// The row the page's last line is drawn on.
    private func lastRow<A: App>(_ loop: RenderLoop<A>) -> Int? {
        loop.diffWriter.shownLines.lastIndex { $0.stripped.contains("LAST") }
    }

    /// A row added to the bar is a row taken from the page, which moves a
    /// centred page — and with it whatever was just copied.
    @Test("The line about a copy takes the items' place, so the bar keeps its height")
    func noteKeepsTheBarsHeight() {
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, now: { 0 })
        let harness = RenderLoopHarness(tuiContext: tui)
        let loop = harness.loop(HintedPage())
        loop.render(frameNowNanos: 0)
        let last = lastRow(loop)
        #expect(last != nil)
        tui.clipboardWriter.write("x", announcingSuccess: false)
        loop.render(frameNowNanos: 1)
        #expect(harness.statusBar.showsNoteInPlaceOfItems)
        #expect(lastRow(loop) == last)
        let noted = loop.diffWriter.shownLines.map(\.stripped)
        #expect(noted.contains { $0.contains(harness.statusBar.tooltipLines.first ?? "?") }, "\(noted)")
        #expect(!noted.contains { $0.contains("quit") }, "in the items' place: \(noted)")
        // And the items come back when it goes.
        loop.render(frameNowNanos: Int64(ClipboardWriter.noteDuration) + 1)
        #expect(!harness.statusBar.showsNoteInPlaceOfItems)
        #expect(lastRow(loop) == last)
        #expect(loop.diffWriter.shownLines.contains { $0.stripped.contains("quit") })
    }

    /// With no line of key hints there are no items for it to stand in for: it
    /// takes a row of its own, as a tooltip does.
    @Test("With no line of key hints the line about a copy takes a row of its own")
    func noteWithoutTheLine() {
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, now: { 0 })
        let harness = RenderLoopHarness(tuiContext: tui)
        let loop = harness.loop(Page())
        loop.render(frameNowNanos: 0)
        tui.clipboardWriter.write("x", announcingSuccess: false)
        loop.render(frameNowNanos: 1)
        #expect(!harness.statusBar.showsNoteInPlaceOfItems)
        let note = harness.statusBar.tooltipLines.first ?? "?"
        #expect(loop.diffWriter.shownLines.contains { $0.stripped.contains(note) })
    }

    /// Where the line is wider than the bar, it is cut rather than wrapped: a
    /// second row would be a row taken from the page all the same.
    @Test("On a narrow terminal the line about a copy is cut to one row", arguments: [20, 30, 40])
    func narrowNoteKeepsTheBarsHeight(width: Int) {
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: false, now: { 0 })
        let harness = RenderLoopHarness(tuiContext: tui)
        harness.terminal.size = (width, 24)
        let loop = harness.loop(HintedPage())
        loop.render(frameNowNanos: 0)
        let last = lastRow(loop)
        tui.clipboardWriter.write("x", announcingSuccess: false)
        loop.render(frameNowNanos: 1)
        #expect(harness.statusBar.showsNoteInPlaceOfItems)
        #expect(harness.statusBar.tooltipLines.count == 1)
        #expect(lastRow(loop) == last)
    }
}
