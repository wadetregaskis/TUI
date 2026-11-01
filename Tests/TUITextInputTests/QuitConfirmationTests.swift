//  🖥️ TUI — A Terminal UI framework for Swift
//  QuitConfirmationTests.swift
//
//  Which ways of quitting ask first, through the real render loop and input
//  chain: what the dialog says, its keys, what comes ahead of it, and what it
//  leaves alone. The driver's half, and a hung app, are
//  `Tools/Smoke/quit_key_smoke.py`'s; what looks for the key among unread
//  input is here too, against a pipe.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport
import TUITextInput

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

@MainActor
@Suite("Quit confirmation")
struct QuitConfirmationTests {
    /// State a test changes between frames.
    final class Model {
        var warning: String?
        var progress: TerminalProgress?
        var count = 0
    }

    /// The app under test: `model`'s warning, and a counter in `@State`, so a
    /// test can see that a dialog costs the page nothing.
    private struct Page: App {
        nonisolated(unsafe) static var model = Model()
        nonisolated(unsafe) static var confirmation = QuitConfirmation.automatic
        nonisolated(unsafe) static var bindsControlC = false

        var body: some Scene {
            WindowGroup {
                PageContent(model: Self.model, bindsControlC: Self.bindsControlC)
            }
            .quitConfirmation(Self.confirmation)
        }
    }

    private struct PageContent: View {
        let model: Model
        let bindsControlC: Bool
        @State private var taps = 0

        var body: some View {
            VStack {
                Button("Tap \(taps)") { taps += 1 }
                if bindsControlC {
                    Button("Bound") { model.count += 1 }
                        .keyboardShortcut("c", modifiers: .control)
                }
            }
            .quitWarning(model.warning ?? "", isActive: model.warning != nil)
            .terminalProgress(model.progress)
        }
    }

    private let controlC = KeyEvent(key: .character("c"), ctrl: true)
    private let controlQ = KeyEvent(key: .character("q"), ctrl: true)
    private let controlBackslash = KeyEvent(key: .character("\\"), ctrl: true)
    private let quitTitle = "Quit "

    /// A fresh app, drawn once.
    private func app(
        _ confirmation: QuitConfirmation = .automatic, model: Model = Model(), bindsControlC: Bool = false
    ) -> HeadlessApp {
        Page.model = model
        Page.confirmation = confirmation
        Page.bindsControlC = bindsControlC
        let app = HeadlessApp(Page(), width: 80, height: 24)
        app.frame(atNanos: 0)
        return app
    }

    private func asks(_ app: HeadlessApp) -> Bool {
        app.screen.contains { $0.stripped.contains(quitTitle) && $0.stripped.contains("?") }
    }

    private func press(_ event: KeyEvent, on app: HeadlessApp, at nanos: inout Int64) {
        app.send(event)
        nanos += 20_000_000
        app.frame(atNanos: nanos)
    }

    /// An app with the dialog up: `.always`, so ⌃Q asks.
    private func askingApp(at nanos: inout Int64) -> HeadlessApp {
        let app = app(.always)
        press(controlQ, on: app, at: &nanos)
        return app
    }

    /// An input chain of its own, for what a `HeadlessApp` leaves out: the user's
    /// quit key and the signal it sends, which `signals` counts apart from `quits`.
    private func chain(prompt: QuitPrompt, quits: @escaping () -> Void, signals: @escaping () -> Void) -> InputHandler {
        let tui = TUIContext()
        var handler = InputHandler(
            statusBar: StatusBarState(), keyEventDispatcher: tui.keyEventDispatcher, focusManager: FocusManager(),
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts, dragAndDropSession: nil,
            onQuit: quits, onSuspend: {}, quitPrompt: prompt)
        handler.quitKey = { 0x1C }
        handler.onQuitKey = signals
        return handler
    }

    // MARK: Which keys ask

    @Test("⌃Q quits at once, with nothing to warn of")
    func controlQQuits() {
        let app = app()
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 1)
        #expect(!asks(app))
    }

    @Test("⌃C with nothing taking it goes nowhere, under any setting and with a warning active")
    func controlCGoesNowhere() {
        for warning in [nil, "Uploading"] {
            for confirmation in [QuitConfirmation.automatic, .always, .whenWarned] {
                let model = Model()
                model.warning = warning
                let app = app(confirmation, model: model)
                var now: Int64 = 0
                press(controlC, on: app, at: &now)
                #expect(app.quitsRequested == 0, "\(confirmation), \(String(describing: warning))")
                #expect(!asks(app), "\(confirmation), \(String(describing: warning))")
            }
        }
    }

    @Test("Under `.always`, ⌃Q asks too")
    func always() {
        let app = app(.always)
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("Under `.whenWarned`, ⌃Q quits at once")
    func whenWarned() {
        let app = app(.whenWarned)
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 1)
        #expect(!asks(app))
    }

    @Test("A warning makes every key ask, under any setting, and the dialog names it")
    func warningAsks() {
        for confirmation in [QuitConfirmation.automatic, .always, .whenWarned] {
            let model = Model()
            model.warning = "Uploading 6 photos"
            let app = app(confirmation, model: model)
            var now: Int64 = 0
            press(controlQ, on: app, at: &now)
            #expect(app.quitsRequested == 0, "\(confirmation)")
            #expect(asks(app), "\(confirmation)")
            #expect(app.screen.contains { $0.stripped.contains("Uploading 6 photos") }, "\(confirmation)")
        }
    }

    @Test("A warning that stops being active stops asking")
    func warningEnds() {
        let model = Model()
        model.warning = "Uploading"
        let app = app(model: model)
        var now: Int64 = 0
        model.warning = nil
        now += 20_000_000
        app.frame(atNanos: now)
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 1)
    }

    @Test("A running progress report asks, and a paused one doesn't")
    func progressAsks() {
        let model = Model()
        model.progress = .value(0.5)
        let running = app(model: model)
        var now: Int64 = 0
        press(controlQ, on: running, at: &now)
        #expect(running.quitsRequested == 0)
        #expect(running.screen.contains { $0.stripped.contains("Work in progress") })

        let pausedModel = Model()
        pausedModel.progress = .paused(0.5)
        let paused = app(model: pausedModel)
        press(controlQ, on: paused, at: &now)
        #expect(paused.quitsRequested == 1)
    }

    // MARK: What comes ahead of it

    @Test("The app's binding on ⌃C wins")
    func bindingWins() {
        let model = Model()
        let app = app(model: model, bindsControlC: true)
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        #expect(model.count == 1)
        #expect(!asks(app))
    }

    @Test("A focused field's ⌃C asks nothing, with text selected or with none")
    func fieldCopies() {
        let app = HeadlessApp(Field(), width: 80, height: 24)
        var now: Int64 = 0
        app.frame(atNanos: now)
        app.send(controlC)
        now += 20_000_000
        app.frame(atNanos: now)
        #expect(!app.screen.contains { $0.stripped.contains("Quit ") }, "nothing selected, so it goes nowhere")
        app.send(KeyEvent(key: .left, shift: true))
        now += 20_000_000
        app.frame(atNanos: now)
        app.send(controlC)
        now += 20_000_000
        app.frame(atNanos: now)
        #expect(!app.screen.contains { $0.stripped.contains("Quit ") }, "the selection is copied instead")
        #expect(app.quitsRequested == 0)
    }

    /// An app whose only control is a field holding some text.
    private struct Field: App {
        var body: some Scene {
            WindowGroup { TextField("Name", text: .constant("some text")) }
        }
    }

    @Test("The chain reports an unbound ⌃C unconsumed, typed or pressed by the menu bar's Copy")
    func controlCIsUnconsumed() {
        let prompt = QuitPrompt(requestFrame: {})
        var quits = 0
        var signals = 0
        let handler = chain(prompt: prompt, quits: { quits += 1 }, signals: { signals += 1 })
        #expect(!handler.handle(controlC))
        handler.perform(.key(controlC))
        #expect(!prompt.isAsking)
        #expect(quits == 0)
        #expect(signals == 0)
    }

    // MARK: The dialog's keys

    @Test("Return stays: the focus starts on Cancel")
    func returnStays() {
        var now: Int64 = 0
        let app = askingApp(at: &now)
        #expect(asks(app))
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(!asks(app))
    }

    @Test("Escape stays")
    func escapeStays() {
        var now: Int64 = 0
        let app = askingApp(at: &now)
        #expect(asks(app))
        press(KeyEvent(key: .escape), on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(!asks(app))
    }

    @Test("Tab and Return quit")
    func tabReturnQuits() {
        var now: Int64 = 0
        let app = askingApp(at: &now)
        press(KeyEvent(key: .tab), on: app, at: &now)
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.quitsRequested == 1)
    }

    @Test("⌃Q at the dialog does nothing: it is still up, and nothing quit")
    func quitKeyAtTheDialog() {
        var now: Int64 = 0
        let app = askingApp(at: &now)
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("⌃C at the dialog does nothing: it is still up, and nothing quit")
    func controlCAtTheDialog() {
        var now: Int64 = 0
        let app = askingApp(at: &now)
        press(controlC, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("A second ⌃\\ at the dialog quits, and the dialog says so; a repeat doesn't count")
    func secondControlBackslash() {
        let prompt = QuitPrompt(requestFrame: {})
        var quits = 0
        var signals = 0
        let handler = chain(prompt: prompt, quits: { quits += 1 }, signals: { signals += 1 })
        #expect(handler.handle(controlBackslash))
        #expect(prompt.isAsking)
        #expect(prompt.message.contains("again to quit"))
        #expect(signals == 0)
        handler.handle(KeyEvent(key: .character("\\"), ctrl: true, phase: .repeat))
        #expect(signals == 0)
        handler.handle(controlC)
        #expect(prompt.isAsking, "⌃C is not the key that asked")
        #expect(signals == 0)
        handler.handle(controlBackslash)
        #expect(signals == 1)
        #expect(quits == 0)
    }

    @Test("Asked by ⌃Q, the dialog has no such line, and a ⌃C there does nothing")
    func quitKeyDialogSaysNothingOfAgain() {
        let model = Model()
        model.warning = "Uploading"
        let app = app(model: model)
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(asks(app))
        #expect(!app.screen.contains { $0.stripped.contains("again to quit") })
        press(controlC, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("The page behind keeps its state, and its focus, through the dialog")
    func pageSurvives() {
        let app = app(.always)
        var now: Int64 = 0
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.screen.contains { $0.stripped.contains("Tap 1") })
        let focused = app.focusedID

        press(controlQ, on: app, at: &now)
        #expect(asks(app))
        #expect(app.focusedID != focused, "the dialog holds the focus")

        press(KeyEvent(key: .escape), on: app, at: &now)
        now += 20_000_000
        app.frame(atNanos: now)
        #expect(app.focusedID == focused)
        #expect(app.screen.contains { $0.stripped.contains("Tap 1") })

        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.screen.contains { $0.stripped.contains("Tap 2") }, "and Return is the page's again")
    }

    // MARK: The prompt's reckoning

    @Test("Warnings are listed once each, in the order drawn")
    func warningsDistinct() {
        let prompt = QuitPrompt(requestFrame: {})
        prompt.noteWarnings(["Saving", "Uploading", "Saving"])
        #expect(prompt.warnings == ["Saving", "Uploading"])
        #expect(prompt.message.contains("• Saving\n• Uploading"))
    }

    @Test("Each key's rule, by setting and by whether a warning is active")
    func theTable() {
        let prompt = QuitPrompt(requestFrame: {})
        let keys: [QuitRequest] = [.quitKey, .signalKey]
        prompt.confirmation = .automatic
        #expect(keys.map(prompt.asks(before:)) == [false, true])
        prompt.confirmation = .always
        #expect(keys.map(prompt.asks(before:)) == [true, true])
        prompt.confirmation = .whenWarned
        #expect(keys.map(prompt.asks(before:)) == [false, false])
        prompt.noteWarnings(["Saving"])
        #expect(keys.map(prompt.asks(before:)) == [true, true])
    }
}

// MARK: - The key among unread input

@Suite("The quit key among unread input")
struct UnreadQuitKeyTests {
    private let quit: UInt8 = 0x1C

    private func holds(_ text: String) -> Bool {
        UnreadQuitKey.isIn(Array(text.utf8), byte: quit)
    }

    @Test("Its byte, anywhere")
    func byte() {
        #expect(holds("\u{1C}"))
        #expect(holds("abc\u{1C}def"))
        #expect(holds("\u{1B}\u{1C}"), "with Option, as a legacy encoding sends it")
        #expect(!holds("abc"))
        #expect(!holds(""))
    }

    @Test("Not in a bracketed paste")
    func paste() {
        #expect(!holds("\u{1B}[200~text \u{1C} more\u{1B}[201~"))
        #expect(holds("\u{1B}[200~text\u{1B}[201~\u{1C}"))
        #expect(!holds("\u{1B}[200~text \u{1C} still going"))
    }

    @Test("Its kitty keyboard protocol report")
    func report() {
        #expect(holds("\u{1B}[92;5u"))
        #expect(holds("x\u{1B}[92;5:1u"), "with the event type, a press")
        #expect(holds("\u{1B}[92;5:2u"), "a repeat")
        #expect(holds("\u{1B}[92;69u"), "with Caps Lock on")
        #expect(holds("\u{1B}[92;133u"), "with Num Lock on")
        #expect(holds("\u{1B}[92:124;5u"), "with alternate keys reported")
    }

    @Test("Not a report of anything else")
    func otherReports() {
        #expect(!holds("\u{1B}[92;5:3u"), "a release")
        #expect(!holds("\u{1B}[92;7u"), "with Option too: a chord of its own there")
        #expect(!holds("\u{1B}[92u"), "with no modifiers")
        #expect(!holds("\u{1B}[99;5u"), "⌃C")
        #expect(!holds("\u{1B}[92;5~"), "not a key report")
        #expect(!holds("\u{1B}[92;5"), "cut off")
    }

    @Test("A moved quit key, by its own byte and report")
    func movedKey() {
        let controlB: UInt8 = 0x02
        #expect(UnreadQuitKey.isIn([0x02], byte: controlB))
        #expect(UnreadQuitKey.isIn(Array("\u{1B}[98;5u".utf8), byte: controlB))
        #expect(!UnreadQuitKey.isIn([0x1C], byte: controlB))
    }
}

// MARK: - The watch

#if !canImport(WASILibc)
@Suite("The quit key's watch")
struct UnreadQuitKeyWatchTests {
    /// A flag a test can wait on from another thread.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func raise() {
            lock.lock()
            count += 1
            lock.unlock()
        }
        var raised: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func waitUntilRaised(within seconds: TimeInterval) async -> Bool {
            let deadline = Date(timeIntervalSinceNow: seconds)
            while Date() < deadline {
                if raised > 0 { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return raised > 0
        }
    }

    private struct Rig {
        let watch: UnreadQuitKeyWatch
        let quits: Flag
        let writeEnd: Int32
        let readEnd: Int32
    }

    private func makeRig(grace: TimeInterval = 0.1) throws -> Rig {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        let flags = fcntl(ends[0], F_GETFL)
        _ = fcntl(ends[0], F_SETFL, flags | O_NONBLOCK)
        let quits = Flag()
        let watch = UnreadQuitKeyWatch(
            input: SharedStandardInput(descriptor: ends[0]), grace: grace, quit: { quits.raise() })
        return Rig(watch: watch, quits: quits, writeEnd: ends[1], readEnd: ends[0])
    }

    private func read(_ rig: Rig) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = bytes.withUnsafeMutableBufferPointer { rig.watch.input.read(into: $0) }
        return count > 0 ? Array(bytes[..<count]) : []
    }

    @Test("The key waits two seconds unread, by default")
    func defaultGrace() {
        #expect(UnreadQuitKeyWatch().grace == 2.0)
    }

    @Test("Unread, the key quits no sooner than the grace is up")
    func keyWaitsOutTheGrace() async throws {
        let grace: TimeInterval = 0.5
        let rig = try makeRig(grace: grace)
        defer {
            rig.watch.stop()
            close(rig.writeEnd)
            close(rig.readEnd)
        }
        rig.watch.start()
        rig.watch.setArmed(byte: 0x1C)
        let pressed = Date()
        var byte: UInt8 = 0x1C
        _ = write(rig.writeEnd, &byte, 1)
        #expect(await rig.quits.waitUntilRaised(within: 5))
        #expect(Date().timeIntervalSince(pressed) >= grace)
    }

    @Test("Unread, the key quits; and nothing else about it waits on the loop")
    func keyQuits() async throws {
        let rig = try makeRig()
        defer {
            rig.watch.stop()
            close(rig.writeEnd)
            close(rig.readEnd)
        }
        rig.watch.start()
        rig.watch.setArmed(byte: 0x1C)
        var byte: UInt8 = 0x1C
        _ = write(rig.writeEnd, &byte, 1)
        #expect(await rig.quits.waitUntilRaised(within: 3))
    }

    @Test("Other keys it holds for the loop, in order, and tells it")
    func otherKeysHeld() async throws {
        let rig = try makeRig()
        defer {
            rig.watch.stop()
            close(rig.writeEnd)
            close(rig.readEnd)
        }
        let held = Flag()
        rig.watch.start(inputHeld: { held.raise() })
        rig.watch.setArmed(byte: 0x1C)
        _ = write(rig.writeEnd, "ab", 2)
        #expect(await held.waitUntilRaised(within: 3))
        #expect(rig.watch.input.holdsInput)
        _ = write(rig.writeEnd, "c", 1)
        #expect(read(rig) == Array("ab".utf8), "what it held comes first")
        #expect(read(rig) == Array("c".utf8))
        #expect(rig.quits.raised == 0)
    }

    @Test("Input the loop goes on reading is left to the loop")
    func aReadingLoop() async throws {
        let rig = try makeRig(grace: 0.3)
        defer {
            rig.watch.stop()
            close(rig.writeEnd)
            close(rig.readEnd)
        }
        rig.watch.start()
        rig.watch.setArmed(byte: 0x1C)
        var byte: UInt8 = 0x1C
        _ = write(rig.writeEnd, &byte, 1)
        #expect(read(rig) == [0x1C])
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(rig.quits.raised == 0)
        #expect(!rig.watch.input.holdsInput)
    }

    @Test("Disarmed, it does nothing")
    func disarmed() async throws {
        let rig = try makeRig()
        defer {
            rig.watch.stop()
            close(rig.writeEnd)
            close(rig.readEnd)
        }
        rig.watch.start()
        var byte: UInt8 = 0x1C
        _ = write(rig.writeEnd, &byte, 1)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(rig.quits.raised == 0)
        #expect(read(rig) == [0x1C])
    }
}
#endif
