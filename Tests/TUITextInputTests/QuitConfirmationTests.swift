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
    private let quitTitle = "Quit "

    /// A fresh app, drawn once.
    private func app(
        _ confirmation: QuitConfirmation = .automatic, model: Model = Model(), bindsControlC: Bool = false
    ) -> HeadlessApp<Page> {
        Page.model = model
        Page.confirmation = confirmation
        Page.bindsControlC = bindsControlC
        let app = HeadlessApp(Page(), width: 80, height: 24)
        app.frame(atNanos: 0)
        return app
    }

    private func asks(_ app: HeadlessApp<Page>) -> Bool {
        app.screen.contains { $0.stripped.contains(quitTitle) && $0.stripped.contains("?") }
    }

    private func press(_ event: KeyEvent, on app: HeadlessApp<Page>, at nanos: inout Int64) {
        app.send(event)
        nanos += 20_000_000
        app.frame(atNanos: nanos)
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

    @Test("⌃C with nothing taking it asks, and quits nothing")
    func controlCAsks() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("Under `.always`, ⌃Q asks too")
    func always() {
        let app = app(.always)
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("Under `.whenWarned`, ⌃C quits at once")
    func whenWarned() {
        let app = app(.whenWarned)
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
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

    @Test("A focused field with text selected copies; with none, ⌃C goes on to ask")
    func fieldCopies() {
        let app = HeadlessApp(Field(), width: 80, height: 24)
        var now: Int64 = 0
        app.frame(atNanos: now)
        app.send(controlC)
        now += 20_000_000
        app.frame(atNanos: now)
        #expect(app.screen.contains { $0.stripped.contains("Quit ") }, "nothing selected, so it isn't the field's")
        app.send(KeyEvent(key: .escape))
        now += 20_000_000
        app.frame(atNanos: now)
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

    @Test("The menu bar's Copy pressing ⌘C asks nothing: only a typed ⌃C does")
    func pressedKeyDoesNotAsk() {
        let prompt = QuitPrompt(requestFrame: {})
        let tui = TUIContext()
        var quits = 0
        let handler = InputHandler(
            statusBar: StatusBarState(), keyEventDispatcher: tui.keyEventDispatcher, focusManager: FocusManager(),
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts, dragAndDropSession: nil,
            onQuit: { quits += 1 }, onSuspend: {}, quitPrompt: prompt)
        handler.perform(.key(controlC))
        #expect(!prompt.isAsking)
        handler.handle(controlC)
        #expect(prompt.isAsking)
        #expect(quits == 0)
    }

    // MARK: The dialog's keys

    @Test("Return stays: the focus starts on Cancel")
    func returnStays() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(!asks(app))
    }

    @Test("Escape stays")
    func escapeStays() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        press(KeyEvent(key: .escape), on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(!asks(app))
    }

    @Test("Tab and Return quit")
    func tabReturnQuits() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        press(KeyEvent(key: .tab), on: app, at: &now)
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.quitsRequested == 1)
    }

    @Test("⌃Q at the dialog does nothing: it is still up, and nothing quit")
    func quitKeyAtTheDialog() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        press(controlQ, on: app, at: &now)
        #expect(app.quitsRequested == 0)
        #expect(asks(app))
    }

    @Test("A second ⌃C at the dialog quits, and the dialog says so; a repeat doesn't count")
    func secondControlC() {
        let app = app()
        var now: Int64 = 0
        press(controlC, on: app, at: &now)
        #expect(app.screen.contains { $0.stripped.contains("again to quit") })
        press(KeyEvent(key: .character("c"), ctrl: true, phase: .repeat), on: app, at: &now)
        #expect(app.quitsRequested == 0)
        press(controlC, on: app, at: &now)
        #expect(app.quitsRequested == 1)
    }

    @Test("Asked by ⌃Q, the dialog has no such line, though a ⌃C there quits as well")
    func quitKeyDialogSaysNothingOfAgain() {
        let model = Model()
        model.warning = "Uploading"
        let app = app(model: model)
        var now: Int64 = 0
        press(controlQ, on: app, at: &now)
        #expect(asks(app))
        #expect(!app.screen.contains { $0.stripped.contains("again to quit") })
        press(controlC, on: app, at: &now)
        #expect(app.quitsRequested == 1)
    }

    @Test("The page behind keeps its state, and its focus, through the dialog")
    func pageSurvives() {
        let app = app()
        var now: Int64 = 0
        press(KeyEvent(key: .enter), on: app, at: &now)
        #expect(app.screen.contains { $0.stripped.contains("Tap 1") })
        let focused = app.focusedID

        press(controlC, on: app, at: &now)
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
        let keys: [QuitRequest] = [.quitKey, .interruptKey, .signalKey]
        prompt.confirmation = .automatic
        #expect(keys.map(prompt.asks(before:)) == [false, true, true])
        prompt.confirmation = .always
        #expect(keys.map(prompt.asks(before:)) == [true, true, true])
        prompt.confirmation = .whenWarned
        #expect(keys.map(prompt.asks(before:)) == [false, false, false])
        prompt.noteWarnings(["Saving"])
        #expect(keys.map(prompt.asks(before:)) == [true, true, true])
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
