//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuitKeyMaskTests.swift
//
//  The owner's rule of 2026-10-06: the user's quit key, ⌃\, stays the
//  driver's — the way out of a hung app — unless the app binds it, or binds
//  ⌃4, ⌃| or ⌃⇧\ where the terminal may send ⌃\'s byte for them. Then the
//  driver's quit is masked and the byte reaches the app. Which bindings
//  count (what the framework can know without running the app's code), and
//  that the line discipline is set only when the answer changes.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

/// Renders a page the way the run loop brackets a frame, and asks a real
/// `InputHandler` over the same services whether the frame's bindings need
/// the quit key masked.
@MainActor
private final class MaskHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()
    let context: RenderContext
    var handler: InputHandler

    init() {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        statusBar.focusManager = focusManager
        environment.statusBar = statusBar
        context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: tui.dragAndDropSession,
            onQuit: {}, onSuspend: {})
    }

    /// Two frames, so the first control has taken the focus.
    func render(_ view: some View) {
        frame(view)
        frame(view)
    }

    private func frame(_ view: some View) {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        statusBar.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
    }

    /// Whether the user's quit key, ⌃\'s 0x1C, needs masking for what was
    /// rendered, in the legacy encoding of a terminal that may send its byte
    /// for the chords in `aliasing` (of ⌃4, and ⌃| and ⌃⇧\).
    func masks(aliasing: TerminalClient.QuitByteAliases = .all, byte: UInt8? = 0x1C) -> Bool {
        handler.quitKeyBindings(byte: byte, hostAliases: aliasing).masksQuitKey(inLegacyEncoding: true)
    }
}

/// A line discipline that records what raw mode sets, for a scripted
/// terminal — the process's own belongs to whatever runs the tests.
@MainActor
private final class FakeLineDiscipline {
    let original = TerminalLineDisciplineTests.cooked()
    private(set) var sets: [(attributes: termios, when: Int32)] = []

    var discipline: LineDiscipline {
        LineDiscipline(get: { [original] in original }, set: { [self] in sets.append(($0, $1)) })
    }

    /// The quit key in the last attributes set.
    var lastQuitKey: cc_t? {
        sets.last.map { TerminalLineDisciplineTests.character($0.attributes, VQUIT) }
    }
}

@MainActor
@Suite("The user's quit key is masked while the app binds a chord its byte could be")
struct QuitKeyMaskTests {
    private static let off = Terminal.disabledControlCharacter

    // MARK: - Which bindings count

    @Test("Nothing bound: the driver keeps the quit key")
    func nothingBound() {
        let harness = MaskHarness()
        harness.render(Button("Plain") {})
        #expect(!harness.masks())
        #expect(!harness.masks(byte: nil), "no quit key at all")
    }

    @Test("A ⌃\\ shortcut masks it, with or without Option, on any terminal")
    func backslashShortcutMasks() {
        for modifiers: EventModifiers in [.control, [.control, .option]] {
            let harness = MaskHarness()
            harness.render(Button("Mine") {}.keyboardShortcut("\\", modifiers: modifiers))
            #expect(harness.masks(aliasing: .all) && harness.masks(aliasing: []), "\(modifiers)")
        }
    }

    /// SwiftUI's ⌘4 is ⌃4 under the default `.commandKey(.control)`, and on a
    /// terminal that sends ⌃\'s 0x1C for it the driver would quit the app
    /// instead: masked there. Where the keys arrive apart — the kitty
    /// keyboard protocol, a host measured not to alias — the quit stays live.
    @Test("⌘4, ⌃| and ⌃⇧\\ mask it only where the terminal may send ⌃\\'s byte for them")
    func aliasesMaskWhereTheyAlias() {
        let pages: [(String, AnyView)] = [
            ("⌘4", AnyView(Button("Four") {}.keyboardShortcut("4"))),
            ("⌃|", AnyView(Button("Bar") {}.keyboardShortcut("|", modifiers: .control))),
            ("⌃⌥4", AnyView(Button("Four") {}.keyboardShortcut("4", modifiers: [.control, .option]))),
        ]
        for (name, page) in pages {
            let harness = MaskHarness()
            harness.render(page)
            #expect(harness.masks(aliasing: .all), "\(name), aliasing")
            #expect(!harness.masks(aliasing: []), "\(name), apart")
        }
        let option = MaskHarness()
        option.render(Button("Four") {}.keyboardShortcut("4").commandKey(.option))
        #expect(!option.masks(), "⌘4 as ⌥4 shares no byte")
    }

    /// An `onKeyPress` declares its keys, so the framework can ask it
    /// without running the app's action — but it hears a key only with the
    /// focus on its view or inside it.
    @Test("An onKeyPress on the key masks it while the focus is inside it")
    func onKeyPressOnTheFocusPath() {
        let onKey = MaskHarness()
        onKey.render(Button("Focused") {}.onKeyPress("\\") { .handled })
        #expect(onKey.masks(aliasing: []), "onKeyPress(\"\\\\\") hears ⌃\\")

        let bar = MaskHarness()
        bar.render(Button("Focused") {}.onKeyPress("|") { .handled })
        #expect(bar.masks(aliasing: .all), "onKeyPress(\"|\") hears ⌃|")
        #expect(!bar.masks(aliasing: []), "…only where ⌃| may be ⌃\\'s byte")

        let elsewhere = MaskHarness()
        elsewhere.render(
            VStack {
                Button("Focused") {}
                Button("Other") {}.onKeyPress("\\") { .handled }
            })
        #expect(!elsewhere.masks(), "a handler the focus is not inside hears nothing")

        let catchAll = MaskHarness()
        catchAll.render(Button("Focused") {}.onKeyPress { _ in .handled })
        #expect(!catchAll.masks(), "a handler for every key declares none: only its action knows")

        let releases = MaskHarness()
        releases.render(Button("Focused") {}.onKeyPress("\\", phases: .up) { _ in .handled })
        #expect(!releases.masks(), "a handler for releases takes no press")
    }

    /// A set of characters asks for what is typed, not for chords: Control
    /// is not looked at in its matching, so `.decimalDigits` would claim ⌃4
    /// and `.punctuationCharacters` ⌃\\. Counted as declared, a number field
    /// masked the user's quit key, and a hung app could not be quit by ⌃\\
    /// while it was focused (the coordinator's ruling, round 6).
    @Test("An onKeyPress on a set of characters does not mask it: it asks for typed text, not chords")
    func characterSetsDeclareNoChord() {
        for (name, set) in [("decimal digits", CharacterSet.decimalDigits), ("punctuation", .punctuationCharacters),
                            ("alphanumerics", .alphanumerics), ("symbols", .symbols)] {
            let harness = MaskHarness()
            harness.render(Button("Focused") {}.onKeyPress(characters: set) { _ in .handled })
            #expect(!harness.masks(aliasing: .all), "\(name)")
        }
    }

    // MARK: - What it costs a frame

    /// Asked after every frame, the question used to make its candidate
    /// chords each time: five arrays a frame for every app. The byte is the
    /// user's, fixed while the app runs, so they are made once a byte and
    /// kept (round 6) — the same storage every time it is asked.
    @Test("The quit key's candidate chords are made once, not after every frame")
    func candidateChordsAreMadeOnce() {
        func storage(_ chords: [KeyEvent]?) -> UnsafePointer<KeyEvent>? {
            chords?.withUnsafeBufferPointer { $0.baseAddress }
        }
        let first = QuitKeyChords.of(0x1C)
        let second = QuitKeyChords.of(0x1C)
        let own: Int? = first?.own.count, aliases: Int? = first?.aliases(on: .all).count
        #expect(own == 2 && aliases == 6, "⌃\\ and ⌃⌥\\; ⌃4, ⌃| and ⌃⇧\\, with and without ⌥")
        #expect(storage(first?.own) == storage(second?.own) && storage(first?.aliases(on: .all)) == storage(second?.aliases(on: .all)))
        #expect(QuitKeyChords.of(0x18)?.own.first == KeyEvent(key: .character("x"), ctrl: true))
        #expect(QuitKeyChords.of(0x18)?.aliases(on: .all).isEmpty == true, "only ⌃\\'s byte is sent for other chords")
        #expect(QuitKeyChords.of(0x7F) == nil && QuitKeyChords.of(0x41) == nil, "no Control chord sends them")
    }

    /// The status bar's items are bindings that count, but none takes a
    /// Control or Option chord — the shortcut vocabulary spells none — and
    /// the quit key's chords are all Control chords. So the question asked
    /// after every frame does not gather the items, which sets, sorts and
    /// filters every one of them (round 6: gathered once a frame, for an
    /// answer that could only be no).
    @Test("Asking about the quit key's chords does not gather the status bar's items")
    func statusBarItemsAreNotGathered() {
        let harness = MaskHarness()
        harness.render(Text("Page"))
        let probe = MatchProbe()
        harness.statusBar.setItemsSilently([probe])
        #expect(harness.statusBar.currentItems.contains { $0.id == probe.id }, "on the bar")
        #expect(!harness.masks(aliasing: .all))
        #expect(probe.asked == 0, "never asked whether it takes one")
        #expect(!harness.statusBar.handleKeyEvent(KeyEvent(key: .character("p"))) && probe.asked == 1, "a bare key is")
    }

    /// An item that counts the keys it is asked about.
    private final class MatchProbe: StatusBarItemProtocol, @unchecked Sendable {
        let id = "probe"
        let shortcut = "p"
        let label = "probe"
        var triggerKey: Key? { .character("p") }
        private(set) var asked = 0

        func matches(_ event: KeyEvent) -> Bool {
            asked += 1
            return false
        }
    }

    // MARK: - The retry, for the bindings that count

    /// Where the byte reaches the chain — masked for another binding, or the
    /// quit key turned off and on again — an unclaimed ⌃\ goes round as ⌃4,
    /// ⌃| and ⌃⇧\ to the bindings declared for them, and to nothing else. A
    /// number field's digits heard it once, as ⌃\, which is no digit: offered
    /// it again as ⌃4 (the whole chain, as before round 6), they typed a 4
    /// for the user's quit key, and the app did not quit.
    @Test("A focused field's digits are not offered ⌃\\ again as ⌃4: the unclaimed ⌃\\ quits, and nothing is typed")
    func digitsAreNotOfferedTheRetry() {
        let harness = MaskHarness()
        let typed = Typed()
        harness.render(
            TextField("Number", text: .constant(""))
                .onKeyPress(characters: .decimalDigits) { press in
                    typed.characters.append(press.characters)
                    return .handled
                })
        var quits = 0
        harness.handler.quitKey = { 0x1C }
        harness.handler.quitByteAliasing = { .all }
        harness.handler.onQuitKey = { quits += 1 }
        #expect(harness.handler.handle(KeyEvent(key: .character("\\"), ctrl: true)))
        #expect(typed.characters.isEmpty && quits == 1)
    }

    /// And a binding declared for ⌃| — an `onKeyPress` on the key, on the
    /// focus path — is offered it, and takes it.
    @Test("A focused view's onKeyPress(\"|\") takes the ⌃\\ the retry offers as ⌃|")
    func declaredKeyTakesTheRetry() {
        let harness = MaskHarness()
        let typed = Typed()
        harness.render(
            Button("Focused") {}.onKeyPress("|") {
                typed.characters.append("|")
                return .handled
            })
        var quits = 0
        harness.handler.quitKey = { 0x1C }
        harness.handler.quitByteAliasing = { .all }
        harness.handler.onQuitKey = { quits += 1 }
        #expect(harness.handler.handle(KeyEvent(key: .character("\\"), ctrl: true)))
        #expect(typed.characters == ["|"] && quits == 0)
    }

    /// A key-specific `onKeyPress` declares a Control chord only on a key
    /// that names one (`KeyEquivalent.namesControlChord`). It matches on the
    /// key alone — `KeyPress(⌃4).key` is `"4"` — so a PIN field's digits
    /// hear ⌃4; counted as declared, they masked the user's quit key, and the
    /// unclaimed ⌃\\ went round to them as ⌃4 and typed a 4 instead of
    /// quitting (the coordinator's ruling, 2026-10-06).
    @Test("A PIN field's onKeyPress on the digit keys neither masks the quit key nor is offered ⌃\\ as ⌃4")
    func digitKeysDeclareNoChord() {
        let harness = MaskHarness()
        let typed = Typed()
        harness.render(
            TextField("PIN", text: .constant(""))
                .onKeyPress(keys: Set("0123456789".map { KeyEquivalent($0) })) { press in
                    typed.characters.append(press.characters)
                    return .handled
                })
        #expect(!harness.masks(aliasing: .all), "a digit names no Control chord")

        var quits = 0
        harness.handler.quitKey = { 0x1C }
        harness.handler.quitByteAliasing = { .all }
        harness.handler.onQuitKey = { quits += 1 }
        #expect(harness.handler.handle(KeyEvent(key: .character("\\"), ctrl: true)))
        #expect(typed.characters.isEmpty && quits == 1, "the unclaimed ⌃\\ quits, and nothing is typed")

        // The field still hears its digits, and ⌃4 itself where the
        // terminal sends it apart (the kitty keyboard protocol): matching is
        // unchanged, only what counts as declared.
        #expect(harness.handler.handle(KeyEvent(key: .character("4"))))
        #expect(harness.handler.handle(KeyEvent(key: .character("4"), ctrl: true)))
        #expect(typed.characters == ["4", "4"])
    }

    /// What a handler took.
    private final class Typed {
        var characters: [String] = []
    }

    @Test("The status bar's quit key and the scene's undo keys count too")
    func statusBarAndUndoKeys() {
        let quit = MaskHarness()
        quit.statusBar.quitShortcut = QuitShortcut(key: .character("\\"), ctrl: true, shortcutSymbol: "^\\")
        quit.render(Text("Page"))
        #expect(quit.masks(), "the app's quit on ⌃\\")

        let undo = MaskHarness()
        let keys = AppUndoKeys()
        keys.publish(UndoShortcuts([.undo: [KeyboardShortcut("\\", modifiers: .control)]]), commandKey: .control)
        undo.handler.undoKeys = keys
        undo.render(Text("Page"))
        #expect(!undo.masks(), "no undo manager: the keys bind nothing")
        undo.handler.undoManager = UndoManager()
        #expect(undo.masks(), "undo on ⌃\\")
    }

    /// The quit key is wherever the user put it: a moved one is masked for a
    /// binding on its own chord, and ⌃\ is then an ordinary key.
    @Test("A moved quit key is masked for its own chord, and ⌃\\ is not")
    func movedQuitKey() {
        let backslash = MaskHarness()
        backslash.render(Button("Mine") {}.keyboardShortcut("\\", modifiers: .control))
        #expect(!backslash.masks(byte: 0x18), "stty quit ^X")
        let ctrlX = MaskHarness()
        ctrlX.render(Button("Cut") {}.keyboardShortcut("x"))
        #expect(ctrlX.masks(byte: 0x18), "⌘X under .control is ⌃X")
        #expect(!ctrlX.masks(byte: 0x1C))
    }

    // MARK: - The line discipline

    /// "tcsetattr only when it changes": the mask is asked after every frame,
    /// and the line discipline is the kernel's, so an unchanged answer must
    /// cost nothing. Set at once (`TCSANOW`), never flushing typed-ahead
    /// input, and kept across a suspend.
    @Test("The line discipline is set only when the mask changes, at once, and a resume keeps it")
    func setOnlyOnChange() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        let line = FakeLineDiscipline()
        terminal.scriptedLineDiscipline = line.discipline
        terminal.enableRawMode()
        #expect(line.sets.count == 1 && line.sets.last?.when == TCSAFLUSH)
        #expect(line.lastQuitKey == 0x1C, "raw mode keeps the quit key live")
        #expect(terminal.quitKeyByte == 0x1C)

        terminal.maskQuitKey(for: .unbound)
        #expect(line.sets.count == 1, "unchanged: nothing set")
        terminal.maskQuitKey(for: .ownChord)
        #expect(line.sets.count == 2 && line.sets.last?.when == TCSANOW)
        #expect(line.lastQuitKey == Self.off)
        terminal.maskQuitKey(for: .ownChord)
        terminal.maskQuitKey(for: .ownChord)
        #expect(line.sets.count == 2, "unchanged: nothing set")
        #expect(terminal.quitKeyByte == 0x1C, "the user's quit key is still ⌃\\, masked or not")

        // A suspend puts the user's own back; the resume is masked again.
        terminal.disableRawMode()
        #expect(line.sets.count == 3 && line.sets.last?.when == TCSAFLUSH)
        #expect(line.sets.last.map { TerminalLineDisciplineTests.same($0.attributes, line.original) } == true)
        terminal.enableRawMode()
        #expect(line.sets.count == 4 && line.lastQuitKey == Self.off)

        terminal.maskQuitKey(for: .unbound)
        #expect(line.sets.count == 5 && line.sets.last?.when == TCSANOW && line.lastQuitKey == 0x1C)
        terminal.disableRawMode()
    }

    @Test("Out of raw mode the mask is remembered, not set")
    func notRawNothingSet() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        let line = FakeLineDiscipline()
        terminal.scriptedLineDiscipline = line.discipline
        terminal.maskQuitKey(for: .ownChord)
        #expect(line.sets.isEmpty)
        terminal.enableRawMode()
        #expect(line.sets.count == 1 && line.lastQuitKey == Self.off, "raw mode is made masked")
        terminal.disableRawMode()
    }

    // MARK: - Under the kitty keyboard protocol

    /// Under the kitty keyboard protocol ⌃4 arrives as itself, so a ⌘4
    /// shortcut (⌃4 under `.commandKey(.control)`) leaves the driver's quit
    /// live. But the stall watchdog's pop would put the terminal back in its
    /// legacy encoding, where kitty, Ghostty, WezTerm and foot send ⌃\'s 0x1C
    /// for ⌃4: the user's ⌃4 during a slow frame would be the driver's quit,
    /// and end the app. So while one is on screen there is no watchdog — as
    /// in the legacy encoding, where the quit is masked for it (round 6: it
    /// was armed on the protocol's mask, which ignores ⌃4).
    @Test("A ⌘4 shortcut leaves the quit live under the kitty protocol, with no stall watchdog; masked without it")
    func aliasUnderTheProtocol() {
        let harness = MaskHarness()
        harness.render(Button("Four") {}.keyboardShortcut("4"))
        let bindings = harness.handler.quitKeyBindings(byte: 0x1C, hostAliases: .all)
        #expect(bindings == .aliasOnly)
        #expect(harness.handler.quitKeyBindings(byte: 0x1C, hostAliases: []) == .unbound, "a host that keeps ⌃4 apart")

        let (terminal, _) = ScriptedTerminalOutput.terminal()
        let line = FakeLineDiscipline()
        terminal.scriptedLineDiscipline = line.discipline
        terminal.enableRawMode()
        terminal.maskQuitKey(for: bindings)
        #expect(terminal.quitKeyMasked && line.lastQuitKey == Self.off, "the legacy encoding: ⌃4 is the byte")

        terminal.maskQuitKey(for: .unbound)
        terminal.negotiateKeyboardEnhancement(firstAnswer: .requested, timeout: 0.01)
        #expect(terminal.writeGate.isArmed, "nothing bound: armed")
        terminal.maskQuitKey(for: bindings)
        #expect(!terminal.quitKeyMasked && line.lastQuitKey == 0x1C, "under the protocol ⌃4 is no 0x1C")
        #expect(!terminal.writeGate.isArmed, "after a pop it would be: no watchdog")
        terminal.maskQuitKey(for: .ownChord)
        #expect(terminal.quitKeyMasked && !terminal.writeGate.isArmed)
        terminal.maskQuitKey(for: .unbound)
        #expect(!terminal.quitKeyMasked && terminal.writeGate.isArmed)
        terminal.disableRawMode()
    }

    // MARK: - Which hosts send ⌃\'s byte for which chords

    /// The owner's `cat -v` readings of 2026-10-06 (Terminal compatibility survey.md,
    /// "The three that share ⌃\'s 0x1C"): Apple Terminal 2.14 sends the quit
    /// byte for ⌃⇧\ (⌃| on a US layout) and nothing for ⌃4; iTerm2 3.7.3 and
    /// Warp 0.2026.09.30 send it for both; Ghostty 1.3.1, in its legacy
    /// encoding, for ⌃4, while ⌃⇧\ is `CSI 124;5u`. Hosts not measured may
    /// alias both. Until then every host was taken to alias every chord.
    @Test("Each measured host aliases only the chords it was measured to send ⌃\\'s byte for")
    func measuredHostAliases() {
        #expect(TerminalClient.quitByteAliases(.appleTerminal) == [.controlShiftBackslash])
        #expect(TerminalClient.quitByteAliases(.iTerm2) == [.controlFour, .controlShiftBackslash])
        #expect(TerminalClient.quitByteAliases(.warp) == [.controlFour, .controlShiftBackslash])
        #expect(TerminalClient.quitByteAliases(.ghostty) == [.controlFour])
        #expect(TerminalClient.quitByteAliases(.tmux) == .all, "not measured: may alias both")
        #expect(TerminalClient.quitByteAliases(.unidentified) == .all, "not measured: may alias both")
    }

    /// So a ⌘4 shortcut masks the quit key on iTerm2, Warp and Ghostty and
    /// not on Apple Terminal, where ⌃4 sends nothing — no byte of the quit
    /// key's to take for it — and a ⌃| one, a shortcut's or an `onKeyPress`'s,
    /// on Apple Terminal, iTerm2 and Warp and not on Ghostty, which sends the
    /// chord (typed as ⌃⇧\) apart.
    @Test("A ⌘4 binding masks the quit key only on a host that sends ⌃\\'s byte for ⌃4; a ⌃| one only where ⌃⇧\\ does")
    func masksPerChordAndHost() {
        let hosts: [TerminalClient.Program] = [.appleTerminal, .iTerm2, .warp, .ghostty, .tmux]
        let pages: [(String, AnyView, Set<TerminalClient.Program>)] = [
            ("⌘4", AnyView(Button("Four") {}.keyboardShortcut("4")), [.iTerm2, .warp, .ghostty, .tmux]),
            ("⌃|", AnyView(Button("Bar") {}.keyboardShortcut("|", modifiers: .control)),
             [.appleTerminal, .iTerm2, .warp, .tmux]),
            ("onKeyPress(\"|\")", AnyView(Button("Bar") {}.onKeyPress("|") { .handled }),
             [.appleTerminal, .iTerm2, .warp, .tmux]),
        ]
        for (name, page, masking) in pages {
            let harness = MaskHarness()
            harness.render(page)
            for host in hosts {
                let masks = harness.masks(aliasing: TerminalClient.quitByteAliases(host))
                #expect(masks == masking.contains(host), "\(name) on \(host)")
            }
        }
    }
}

#endif
