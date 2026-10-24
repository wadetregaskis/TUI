//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardBackendTests.swift
//
//  This machine's clipboard is injected (`ClipboardBackend`): the app's run
//  loop installs the system's, every other context keeps its copies in
//  memory, and an environment no context reached has no clipboard at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Clipboard: the injected backend")
struct ClipboardBackendTests {
    @Test("An in-memory clipboard reads back the latest copy")
    func inMemoryRoundTrip() {
        let clipboard = InMemoryClipboard()
        #expect(clipboard.isAvailable)
        #expect(clipboard.read() == nil)
        #expect(clipboard.write("first"))
        #expect(clipboard.write("second"))
        #expect(clipboard.read() == "second")
    }

    /// The writer's rule is the same whichever clipboard stands behind it:
    /// the route to this machine's goes to the backend, and a paste reads it.
    @Test("A copy the rule sends to this machine's clipboard lands in the writer's backend")
    func writerUsesItsBackend() {
        let clipboard = InMemoryClipboard()
        let writer = ClipboardWriter(
            terminal: { TerminalClient.ClipboardDelivery(.unsupported) }, isLocal: { true }, system: clipboard,
            nowNanos: { 0 }, requestFrame: {})
        #expect(writer.write("copied", announcingSuccess: false) == .copied)
        #expect(clipboard.read() == "copied")
        #expect(writer.read() == "copied")
    }

    /// OSC 52 stays first: a terminal that writes it by default is sent the
    /// copy, and this machine's clipboard is not touched, local or not.
    @Test("A terminal that writes OSC 52 by default gets the copy, not the backend")
    func osc52StaysFirst() {
        let clipboard = InMemoryClipboard()
        let writer = ClipboardWriter(
            terminal: { TerminalClient.ClipboardDelivery(.honoured) }, isLocal: { true }, system: clipboard,
            nowNanos: { 0 }, requestFrame: {})
        #expect(writer.write("hi", announcingSuccess: false) == .copied)
        #expect(clipboard.read() == nil)
        #expect(writer.takePendingSequences() == ClipboardSequence.write("hi"))
    }

    /// The environment's default, met only where no context's services were
    /// applied, reaches no clipboard — never this machine's, which a stray
    /// render must not write.
    @Test("An environment no context reached has no clipboard")
    func environmentDefaultIsUnavailable() {
        let access = EnvironmentValues().clipboardAccess
        #expect(access.write("not for the pasteboard") == .unavailable)
        #expect(access.write("") == .nothingToCopy)
        #expect(access.read() == nil)
    }

    /// The one line that sends a running app's copies to this machine's
    /// clipboard: the runner builds its context with the system's backend.
    /// Built with the default instead, every local copy — Ctrl-C in a field, a
    /// mouse selection — would land in memory and still report `.copied`, and
    /// nothing else in the suite would notice.
    @Test("The app's runner gives its context this machine's clipboard")
    func runnerInstallsTheSystemClipboard() {
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        let runner = AppRunner(app: FocusStillApp(), appState: AppState())
        #expect(runner.tuiContext.clipboardWriter.system is SystemClipboard.Backend)
        #expect(TUIContext().clipboardWriter.system is InMemoryClipboard, "every other context's")
    }

    /// A context's services bring its writer: the environment a render gets
    /// copies through the context, not the default.
    @Test("A context's services hand its controls the context's writer")
    func contextServicesBringTheWriter() {
        let log = SystemClipboardLog()
        let tui = TUIContext()
        tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        #expect(environment.clipboardAccess.write("through the context") == .copied)
        #expect(log.writes == ["through the context"])
    }
}
