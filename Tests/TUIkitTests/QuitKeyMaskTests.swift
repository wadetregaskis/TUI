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

@testable import TUIkit
@testable import TUIkitStyling

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
    /// rendered, on a terminal that may (`aliasing`) send its byte for ⌃4,
    /// ⌃| and ⌃⇧\.
    func masks(aliasing: Bool = true, byte: UInt8? = 0x1C) -> Bool {
        handler.quitKeyNeedsMasking(byte: byte, aliasing: aliasing)
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
            #expect(harness.masks(aliasing: true) && harness.masks(aliasing: false), "\(modifiers)")
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
            #expect(harness.masks(aliasing: true), "\(name), aliasing")
            #expect(!harness.masks(aliasing: false), "\(name), apart")
        }
        let option = MaskHarness()
        option.render(Button("Four") {}.keyboardShortcut("4").commandKey(.option))
        #expect(!option.masks(), "⌘4 as ⌥4 shares no byte")
    }

    /// An `onKeyPress` declares its keys or characters, so the framework can
    /// ask it without running the app's action — but it hears a key only
    /// with the focus on its view or inside it.
    @Test("An onKeyPress on the key or its characters masks it while the focus is inside it")
    func onKeyPressOnTheFocusPath() {
        let onKey = MaskHarness()
        onKey.render(Button("Focused") {}.onKeyPress("4") { .handled })
        #expect(onKey.masks(), "onKeyPress(\"4\") hears ⌃4")

        let characters = MaskHarness()
        characters.render(Button("Focused") {}.onKeyPress(characters: .punctuationCharacters) { _ in .handled })
        #expect(characters.masks(), "\\ is punctuation")

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

        terminal.maskQuitKey(false)
        #expect(line.sets.count == 1, "unchanged: nothing set")
        terminal.maskQuitKey(true)
        #expect(line.sets.count == 2 && line.sets.last?.when == TCSANOW)
        #expect(line.lastQuitKey == Self.off)
        terminal.maskQuitKey(true)
        terminal.maskQuitKey(true)
        #expect(line.sets.count == 2, "unchanged: nothing set")
        #expect(terminal.quitKeyByte == 0x1C, "the user's quit key is still ⌃\\, masked or not")

        // A suspend puts the user's own back; the resume is masked again.
        terminal.disableRawMode()
        #expect(line.sets.count == 3 && line.sets.last?.when == TCSAFLUSH)
        #expect(line.sets.last.map { TerminalLineDisciplineTests.same($0.attributes, line.original) } == true)
        terminal.enableRawMode()
        #expect(line.sets.count == 4 && line.lastQuitKey == Self.off)

        terminal.maskQuitKey(false)
        #expect(line.sets.count == 5 && line.sets.last?.when == TCSANOW && line.lastQuitKey == 0x1C)
        terminal.disableRawMode()
    }

    @Test("Out of raw mode the mask is remembered, not set")
    func notRawNothingSet() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        let line = FakeLineDiscipline()
        terminal.scriptedLineDiscipline = line.discipline
        terminal.maskQuitKey(true)
        #expect(line.sets.isEmpty)
        terminal.enableRawMode()
        #expect(line.sets.count == 1 && line.lastQuitKey == Self.off, "raw mode is made masked")
        terminal.disableRawMode()
    }
}

#endif
