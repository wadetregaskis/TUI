//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyNotationTests.swift
//
//  Keys spelled out for a terminal font with no glyph for macOS's symbols: the
//  names, where they come from — the user's `TUIKIT_KEY_SYMBOLS=0`, the app's
//  `Scene.keyNotation(_:)` — and where they are drawn: the status bar and a
//  menu's shortcut column.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("Key notation")
struct KeyNotationTests {

    // MARK: - The names

    @Test("Spelled out, each symbol is its name, and a modifier is joined to its key by a hyphen")
    func spelledOut() {
        let notation = KeyNotation.spelledOut
        #expect(notation.spelling("⌃⇧Z") == "Ctrl-Shift-Z")
        #expect(notation.spelling("⌃⌥⇧⌘S") == "Ctrl-Alt-Shift-Cmd-S")
        #expect(notation.spelling("⎋") == "Esc")
        #expect(notation.spelling("⇧⇥") == "Shift-Tab")
        #expect(notation.spelling("⌥⌫") == "Alt-Backspace")
        #expect(notation.spelling("⌦") == "Del")
        #expect(notation.spelling("↩") == "Return")
        #expect(notation.spelling("⇞/⇟") == "PgUp/PgDn")
        #expect(notation.spelling("↖ ↘") == "Home End")
        // The arrows are drawn in every terminal font, and stay.
        #expect(notation.spelling("⌥↑") == "Alt-↑")
        // A modifier on its own is just its name.
        #expect(notation.spelling("⇧") == "Shift")
        #expect(notation.spelling("⇧ more") == "Shift more")
    }

    /// Text that already joins a modifier to its key keeps its own joiner:
    /// a hyphen of ours after it read `Shift--click` and `Ctrl-+C`. A `-` or
    /// `+` that ends the chord is the key itself, and is joined as any key is.
    @Test("A modifier the text already joins to its key keeps that joiner, and minus or plus as the key is joined")
    func modifierWithItsOwnJoiner() {
        let notation = KeyNotation.spelledOut
        #expect(notation.spelling("⇧-click") == "Shift-click")
        #expect(notation.spelling("⌘-click to open") == "Cmd-click to open")
        #expect(notation.spelling("⌃+C") == "Ctrl+C")
        #expect(notation.spelling("⌃⇧-Z") == "Ctrl-Shift-Z")
        // Control-minus and Control-plus: the key is the - or the +.
        #expect(notation.spelling("⌃-") == "Ctrl--")
        #expect(notation.spelling("⌃+") == "Ctrl-+")
        #expect(notation.spelling("⌃- smaller") == "Ctrl-- smaller")
        #expect(notation.spelling("⌃⇧-") == "Ctrl-Shift--")
    }

    /// The `-` or `+` is a joiner only when a key follows it. Before
    /// punctuation it is the key: `⌃+/⌃-` names Control-plus and
    /// Control-minus, and read as a joiner it came out `Ctrl+/Ctrl--`.
    @Test("A minus or plus before punctuation is the key, and a key symbol after one is joined")
    func minusOrPlusBeforePunctuationIsTheKey() {
        let notation = KeyNotation.spelledOut
        #expect(notation.spelling("⌃+/⌃-") == "Ctrl-+/Ctrl--")
        #expect(notation.spelling("⌃-|⌃+") == "Ctrl--|Ctrl-+")
        #expect(notation.spelling("⌃+,") == "Ctrl-+,")
        #expect(notation.spelling("⌥-↑") == "Alt-↑")
        #expect(notation.spelling("⌃+⎋") == "Ctrl+Esc")
        #expect(notation.spelling("⌃+1") == "Ctrl+1")
    }

    @Test("What names no key reads the same in both notations")
    func otherTextIsUntouched() {
        for text in ["q", "1-9", "c|C", "+|-", "↑↓", "F12", "Space", ""] {
            #expect(KeyNotation.spelledOut.spelling(text) == text)
        }
    }

    @Test("Under the symbols, the text is the text")
    func symbolsAreIdentity() {
        #expect(KeyNotation.symbols.spelling("⌃⇧Z") == "⌃⇧Z")
    }

    @Test("Every symbol the formatter draws, but the arrows, has a name")
    func everySymbolHasAName() {
        let keys: [Key] = [.escape, .enter, .tab, .backspace, .delete, .home, .end, .pageUp, .pageDown]
        let symbols = keys.map(KeySymbols.key) + Array("⌃⌥⇧⌘").map(String.init)
        for symbol in symbols {
            let name = KeyNotation.spelledOut.spelling(symbol)
            #expect(name != symbol && name.allSatisfy(\.isASCII), "\(symbol) is spelled \(name)")
        }
        #expect(KeyNotation.names.count == symbols.count, "a name for a symbol nothing draws")
    }

    // MARK: - Where the notation comes from

    @Test("The user asks with TUIKIT_KEY_SYMBOLS=0, and nothing else asks")
    func environmentVariable() {
        #expect(TerminalClient.keyNotationRequested(environment: ["TUIKIT_KEY_SYMBOLS": "0"]) == .spelledOut)
        #expect(TerminalClient.keyNotationRequested(environment: ["TUIKIT_KEY_SYMBOLS": "1"]) == .symbols)
        #expect(TerminalClient.keyNotationRequested(environment: [:]) == .symbols)
        #expect(EnvironmentValues().keyNotation == .symbols, "a key's default does not read the process")
    }

    @Test("The app's scene spells keys out, and never turns the symbols back on")
    func sceneSetting() {
        func root(_ scene: some Scene, user: KeyNotation) -> KeyNotation {
            var environment = EnvironmentValues()
            environment.keyNotation = user
            scene.sceneConfiguration.applyEnvironmentWrites(to: &environment)
            return environment.keyNotation
        }
        #expect(root(WindowGroup { Text("app") }.keyNotation(.spelledOut), user: .symbols) == .spelledOut)
        #expect(root(WindowGroup { Text("app") }.keyNotation(.symbols), user: .symbols) == .symbols)
        #expect(
            root(WindowGroup { Text("app") }.keyNotation(.symbols), user: .spelledOut) == .spelledOut,
            "the user's ask stands")
        #expect(root(WindowGroup { Text("app") }, user: .symbols) == .symbols)
    }

    // MARK: - Where it is drawn

    @Test("The status bar writes its keys in the notation in force")
    func statusBar() {
        let bar = StatusBar(
            items: [
                StatusBarItem(shortcut: Shortcut.escape, label: "back"),
                StatusBarItem(shortcut: Shortcut.ctrl("z"), label: "undo"),
                StatusBarItem(shortcut: "q", label: "quit"),
            ],
            style: .compact)
        func drawn(_ notation: KeyNotation) -> String {
            var context = RenderContext(availableWidth: 80, availableHeight: 4, tuiContext: TUIContext())
                .isolatingRenderCache()
            context.environment.keyNotation = notation
            return renderToBuffer(bar, context: context).lines.map(\.stripped).joined()
        }
        let symbols = drawn(.symbols)
        #expect(symbols.contains("⎋ back") && symbols.contains("⌃Z undo"), "\(symbols)")
        let names = drawn(.spelledOut)
        #expect(names.contains("Esc back") && names.contains("Ctrl-Z undo") && names.contains("q quit"), "\(names)")
        #expect(!names.contains("⎋") && !names.contains("⌃"), "\(names)")
    }

    @Test("The user's TUIKIT_KEY_SYMBOLS=0, as the app runner reads it, reaches the status bar")
    func userSettingReachesTheStatusBar() {
        let asked = TerminalClient.keyNotationRequested(environment: ["TUIKIT_KEY_SYMBOLS": "0"])
        let harness = RenderLoopHarness()
        _ = harness.loop(KeyNotationProbeApp(), keyNotation: asked).render()
        #expect(harness.terminal.writtenOutput.joined().stripped.contains("Esc back"))

        let unset = RenderLoopHarness()
        _ = unset.loop(KeyNotationProbeApp()).render()
        #expect(unset.terminal.writtenOutput.joined().stripped.contains("⎋ back"))

        let appAsked = RenderLoopHarness()
        _ = appAsked.loop(KeyNotationProbeApp(notation: .spelledOut)).render()
        #expect(appAsked.terminal.writtenOutput.joined().stripped.contains("Esc back"), "the scene's own ask")
    }

    @Test("A menu row writes its shortcut in the notation in force")
    func menuRows() {
        func drawn(_ notation: KeyNotation) -> String {
            let tui = TUIContext()
            let focusManager = FocusManager()
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.keyNotation = notation
            let context = RenderContext(
                availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
            let view = Text("Right-click me").contextMenu {
                Button("Cut") {}.keyboardShortcut("x", modifiers: [.control, .shift])
            }
            func render() -> FrameBuffer {
                tui.mouseEventDispatcher.beginRenderPass()
                tui.keyEventDispatcher.clearHandlers()
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                focusManager.beginRenderPass()
                let buffer = renderToBuffer(view, context: context)
                tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
                return buffer
            }
            _ = render()
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
            return (render().overlays.first?.content.lines ?? []).map(\.stripped).joined(separator: "\n")
        }
        let symbols = drawn(.symbols)
        #expect(symbols.contains("Cut") && symbols.contains("⌃⇧X"), "\(symbols)")
        let names = drawn(.spelledOut)
        #expect(names.contains("Cut") && names.contains("Ctrl-Shift-X"), "\(names)")
    }
}

/// An app whose page publishes an Escape item, its scene saying
/// `.keyNotation(notation)` where that is given.
private struct KeyNotationProbeApp: App {
    let notation: KeyNotation?

    init() { self.init(notation: nil) }

    init(notation: KeyNotation?) {
        self.notation = notation
    }

    var body: some Scene {
        WindowGroup {
            Text("page")
                .statusBarItems {
                    StatusBarItem(shortcut: Shortcut.escape, label: "back")
                }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
        .keyNotation(notation ?? .symbols)
    }
}
