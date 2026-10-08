//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputHandlerQuitKeyTests.swift
//
//  The user's quit key, ⌃\, where it reaches the input chain: as a kitty
//  keyboard protocol report, or as its byte where the driver's quit is
//  masked or off. The app's bindings have it first; only an unclaimed one
//  quits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitStyling

@MainActor
@Suite("The user's quit key in the input chain")
struct InputHandlerQuitKeyTests {

    /// A minimal ``Cyclable`` for the theme and appearance managers.
    private struct FakeCyclable: Cyclable {
        let id: String
        let name: String
    }

    /// What the chain did with the keys.
    private final class Probe {
        /// `SIGQUIT`s the chain asked for (`onQuitKey`).
        var quits = 0
        /// The app's own quits (`onQuit`, the status bar's `q`).
        var appQuits = 0
        /// The bindings that ran, by name.
        var fired: [String] = []
    }

    private struct Fixture {
        var handler: InputHandler
        let dispatcher: KeyEventDispatcher
        let shortcuts: KeyboardShortcutRegistry
        let statusBar: StatusBarState
        let probe: Probe
    }

    /// An `InputHandler` over fresh collaborators, the user's quit key
    /// `quitKey` (`nil`: none, as after `stty quit undef`), on a terminal
    /// that may send ⌃\'s byte for the chords in `aliasing` — of ⌃4, and ⌃|
    /// and ⌃⇧\ — and sends the rest apart.
    private func makeFixture(quitKey: UInt8? = 0x1C, aliasing: TerminalClient.QuitByteAliases = []) -> Fixture {
        let statusBar = StatusBarState()
        let dispatcher = KeyEventDispatcher()
        let shortcuts = KeyboardShortcutRegistry()
        let probe = Probe()
        var handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: dispatcher,
            focusManager: FocusManager(),
            paletteManager: ThemeManager(items: [FakeCyclable(id: "p", name: "p")]),
            appearanceManager: ThemeManager(items: [FakeCyclable(id: "a", name: "a")]),
            keyboardShortcuts: shortcuts,
            dragAndDropSession: nil,
            onQuit: { probe.appQuits += 1 },
            onSuspend: {}
        )
        handler.quitKey = { quitKey }
        handler.onQuitKey = { probe.quits += 1 }
        handler.quitByteAliasing = { aliasing }
        return Fixture(
            handler: handler, dispatcher: dispatcher, shortcuts: shortcuts, statusBar: statusBar, probe: probe)
    }

    private static func control(_ character: Character, alt: Bool = false, shift: Bool = false,
                                phase: KeyEvent.Phase = .press) -> KeyEvent {
        KeyEvent(key: .character(character), ctrl: true, alt: alt, shift: shift, phase: phase)
    }

    private func bind(_ fixture: Fixture, _ key: KeyEquivalent, as name: String) {
        fixture.shortcuts.register(KeyboardShortcut(key, modifiers: .control)) { fixture.probe.fired.append(name) }
    }

    /// The owner's decision (2026-10-06): an app's own ⌃\ overrides the quit.
    /// Until then the chain raised the signal for the report ahead of every
    /// layer, so no binding could have the key; now it goes down the chain
    /// as any key, and only a ⌃\ nothing took quits.
    @Test("The user's quit key goes to the app's bindings first, and quits only where none takes it")
    func bindingsComeFirst() {
        let unbound = makeFixture()
        #expect(unbound.handler.handle(Self.control("\\")))
        #expect(unbound.probe.quits == 1, "nothing took it: the driver's quit")
        #expect(unbound.handler.handle(Self.control("\\", alt: true)), "Option adds only an ESC")
        #expect(unbound.handler.handle(Self.control("\\", phase: .repeat)), "a repeat is a press, as in a legacy encoding")
        #expect(unbound.probe.quits == 3)
        unbound.handler.handle(Self.control("\\", phase: .release))
        #expect(unbound.probe.quits == 3, "a release quits nothing")
        #expect(unbound.probe.appQuits == 0, "the signal, not the app's own quit")

        let shortcut = makeFixture()
        bind(shortcut, "\\", as: "⌃\\")
        #expect(shortcut.handler.handle(Self.control("\\")))
        #expect(shortcut.probe.fired == ["⌃\\"] && shortcut.probe.quits == 0, "a .keyboardShortcut takes it")

        let handler = makeFixture()
        handler.dispatcher.addHandler { event in
            handler.probe.fired.append("onKeyEvent")
            return event.key == .character("\\")
        }
        #expect(handler.handler.handle(Self.control("\\")))
        #expect(handler.probe.fired == ["onKeyEvent"] && handler.probe.quits == 0, "so does an onKeyEvent handler")
    }

    @Test("A quit key the user turned off is no quit, and one they moved quits from where they put it")
    func followsTheUsersStty() {
        let undefined = makeFixture(quitKey: nil)
        #expect(!undefined.handler.handle(Self.control("\\")), "an ordinary key nothing binds")
        #expect(undefined.probe.quits == 0)

        let moved = makeFixture(quitKey: 0x18)
        moved.handler.handle(Self.control("\\"))
        #expect(moved.probe.quits == 0)
        moved.handler.handle(Self.control("x"))
        #expect(moved.probe.quits == 1, "stty quit ^X")
        moved.handler.handle(Self.control("X", shift: true))
        #expect(moved.probe.quits == 1, "Shift makes another chord")
    }

    /// Some terminals send ⌃\'s 0x1C for ⌃4, ⌃| and ⌃⇧\ too, and the parser
    /// reads the byte as ⌃\. Where it may be one of them, a ⌃\ nothing took
    /// goes round once more as each, to the bindings declared for them — so a
    /// ⌃4 shortcut (SwiftUI's ⌘4 under `.commandKey(.control)`) fires — and
    /// only then quits.
    @Test("An unclaimed ⌃\\ that may be ⌃4, ⌃| or ⌃⇧\\ goes round as each, then quits")
    func aliasesAfterBackslash() {
        for (key, name) in [("4", "⌃4"), ("|", "⌃|")] as [(KeyEquivalent, String)] {
            let fixture = makeFixture(aliasing: .all)
            bind(fixture, key, as: name)
            #expect(fixture.handler.handle(Self.control("\\")))
            #expect(fixture.probe.fired == [name] && fixture.probe.quits == 0, "\(name)")
        }

        let optioned = makeFixture(aliasing: .all)
        optioned.shortcuts.register(KeyboardShortcut("4", modifiers: [.control, .option])) {
            optioned.probe.fired.append("⌃⌥4")
        }
        #expect(optioned.handler.handle(Self.control("\\", alt: true)))
        #expect(optioned.probe.fired == ["⌃⌥4"], "Option kept, as the ESC before the byte keeps it")

        let unbound = makeFixture(aliasing: .all)
        #expect(unbound.handler.handle(Self.control("\\")))
        #expect(unbound.probe.quits == 1, "none of the four bound: the quit")

        let apart = makeFixture(aliasing: [])
        bind(apart, "4", as: "⌃4")
        #expect(apart.handler.handle(Self.control("\\")))
        #expect(apart.probe.fired.isEmpty && apart.probe.quits == 1, "keys sent apart: ⌃\\ is ⌃\\")
    }

    /// The coordinator's ruling (round 6): the retry is offered to the
    /// bindings the app declared for ⌃4, ⌃| and ⌃⇧\ alone, not run through
    /// the whole chain again. A handler that hears every key heard the byte
    /// once, as ⌃\, and that is all it hears of it: offered it four times
    /// before, it logged ⌃\ and ⌃4 for one key, and one that took ⌃⇧\ by
    /// looking at Shift kept the user's quit key from quitting.
    @Test("The retry is the declared bindings' alone: a handler that hears every key hears one ⌃\\, once")
    func catchAllHearsTheByteOnce() {
        let fixture = makeFixture(aliasing: .all)
        let heard = Heard()
        fixture.dispatcher.addHandler { event in
            heard.events.append(event)
            return false
        }
        bind(fixture, "4", as: "⌃4")
        #expect(fixture.handler.handle(Self.control("\\")))
        #expect(heard.events == [Self.control("\\")], "once, as ⌃\\")
        #expect(fixture.probe.fired == ["⌃4"] && fixture.probe.quits == 0, "and ⌘4 fires")

        let shifted = makeFixture(aliasing: .all)
        shifted.dispatcher.addHandler { event in
            guard event.shift, event.ctrl, event.key == .character("\\") else { return false }
            shifted.probe.fired.append("⌃⇧\\")
            return true
        }
        #expect(shifted.handler.handle(Self.control("\\")))
        #expect(shifted.probe.fired.isEmpty && shifted.probe.quits == 1, "not offered ⌃⇧\\: the quit")
    }

    /// What a handler heard.
    private final class Heard {
        var events: [KeyEvent] = []
    }

    /// The bytes are identical, so one binding has to win, and it is the
    /// parser's reading, ⌃\ (the coordinator's call, decisions F2 A-F2-1).
    @Test("With both ⌃\\ and ⌃4 bound, an aliasing terminal's ⌃\\ runs ⌃\\'s")
    func backslashWinsTheAmbiguity() {
        let fixture = makeFixture(aliasing: .all)
        bind(fixture, "\\", as: "⌃\\")
        bind(fixture, "4", as: "⌃4")
        #expect(fixture.handler.handle(Self.control("\\")))
        #expect(fixture.probe.fired == ["⌃\\"] && fixture.probe.quits == 0)
        #expect(fixture.handler.handle(Self.control("4")), "⌃4 reported as itself still runs ⌃4's")
        #expect(fixture.probe.fired == ["⌃\\", "⌃4"])
    }

    /// The retry offers ⌃\ only as the chords the host may send its byte
    /// for (the owner's readings, 2026-10-06): on Apple Terminal, which sends
    /// nothing for ⌃4, an unclaimed ⌃\ is never a ⌘4 shortcut's but is a ⌃|
    /// one's; on Ghostty, which sends ⌃⇧\ apart, it is ⌘4's and never ⌃|'s.
    @Test("An unclaimed ⌃\\ goes round only as the chords the host may send its byte for")
    func aliasesFollowTheHost() {
        for (host, key, name, fires) in [
            (TerminalClient.Program.appleTerminal, "4", "⌃4", false),
            (.appleTerminal, "|", "⌃|", true),
            (.ghostty, "4", "⌃4", true),
            (.ghostty, "|", "⌃|", false),
        ] as [(TerminalClient.Program, KeyEquivalent, String, Bool)] {
            let fixture = makeFixture(aliasing: TerminalClient.quitByteAliases(host))
            bind(fixture, key, as: name)
            #expect(fixture.handler.handle(Self.control("\\")))
            #expect(fixture.probe.fired == (fires ? [name] : []), "\(name) on \(host)")
            #expect(fixture.probe.quits == (fires ? 0 : 1), "\(name) on \(host): unclaimed, the quit")
        }
    }
}
