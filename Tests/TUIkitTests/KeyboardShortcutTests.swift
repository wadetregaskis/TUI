//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcutTests.swift
//
//  `.keyboardShortcut(.defaultAction / .cancelAction)` — the default button
//  fires on Return/Enter ONLY when the focused control lets the key fall
//  through; Escape triggers the cancel button under the same rule. The
//  focused-control precedence cases here are the contract's heart: a
//  TextEditor keeps its newline, a list keeps its row activation, a focused
//  Button fires itself, and a TextField without onSubmit lets Return through.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Keyboard shortcuts (default / cancel actions)")
struct KeyboardShortcutTests {

    // MARK: - Harness

    /// Renders `view` with a full environment (focus manager + shortcut
    /// registry) and returns the pieces the dispatch chain uses.
    private func render(
        _ view: some View, width: Int = 40, height: Int = 12
    ) -> (focus: FocusManager, shortcuts: KeyboardShortcutRegistry) {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let focus = FocusManager()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        _ = renderToBuffer(view, context: context)
        return (focus, tui.keyboardShortcuts)
    }

    /// The focused-control-then-shortcut slice of InputHandler's chain: the
    /// focused control gets the key first; the semantic shortcut fires only
    /// if it fell through. (Layers 1/2/4 don't participate in these cases.)
    private func dispatch(
        _ event: KeyEvent, focus: FocusManager, shortcuts: KeyboardShortcutRegistry
    ) -> Bool {
        if focus.dispatchKeyEvent(event) { return true }
        return shortcuts.trigger(for: event)
    }

    // MARK: - Basic semantics

    @Test("Return fires the default button when nothing consumes it")
    func returnFiresDefault() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Sign in") { box.fired += 1 }
            .keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 1)
    }

    @Test("Escape fires the cancel button")
    func escapeFiresCancel() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Cancel") { box.fired += 1 }
            .keyboardShortcut(.cancelAction)
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .escape)))
        #expect(box.fired == 1)
    }

    @Test("Modified Return/Escape do not trigger the semantic actions")
    func modifiedKeysIgnored() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)

        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, ctrl: true)))
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, alt: true)))
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, shift: true)))
        #expect(box.fired == 0)
    }

    @Test("A disabled default button never registers")
    func disabledDoesNotRegister() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }
            .keyboardShortcut(.defaultAction)
            .disabled()
        let (_, shortcuts) = render(view)

        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 0)
    }

    @Test("The registry clears each render pass (a vanished dialog can't fire)")
    func registryClearsPerFrame() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)
        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))

        // Next frame renders WITHOUT the button (dialog dismissed).
        shortcuts.beginRenderPass()
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 1)
    }

    @Test("Overlapping registrations: the last rendered (topmost) wins")
    func lastRegistrationWins() {
        final class Box { var fired: [String] = [] }
        let box = Box()
        let view = VStack {
            Button("Page OK") { box.fired.append("page") }
                .keyboardShortcut(.defaultAction)
            Button("Dialog OK") { box.fired.append("dialog") }
                .keyboardShortcut(.defaultAction)
        }
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == ["dialog"], "the later (topmost) registration wins")
    }

    // MARK: - Focused-control precedence (the contract's heart)

    @Test("A focused TextEditor keeps Return (newline), suppressing the default")
    func textEditorKeepsReturn() {
        final class Box { var fired = 0 }
        let box = Box()
        var text = "line"
        let view = VStack {
            TextEditor(text: Binding(get: { text }, set: { text = $0 }))
                .frame(height: 4)
            Button("Send") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // The editor auto-focuses (first focusable). Return → newline, consumed.
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(text.contains("\n"), "the editor inserted a newline")
        #expect(box.fired == 0, "the default button must NOT fire")
    }

    @Test("A focused list with a row activation keeps Return, suppressing the default")
    func listActivationKeepsReturn() {
        final class Box {
            var opened: [String] = []
            var fired = 0
        }
        let box = Box()
        let view = VStack {
            List(selection: .constant(String?.none)) {
                ForEach(["a", "b"], id: \.self) { Text($0) }
            }
            .onRowActivate { box.opened.append($0) }
            .frame(height: 5)
            Button("OK") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.opened == ["a"], "the list opened its focused row")
        #expect(box.fired == 0, "the default button must NOT fire")
    }

    @Test("A focused Button fires itself on Return, not the default")
    func focusedButtonFiresItself() {
        final class Box { var fired: [String] = [] }
        let box = Box()
        let view = VStack {
            Button("First") { box.fired.append("first") }
            Button("Default") { box.fired.append("default") }
                .keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // Focus sits on the first button; Return activates IT.
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.fired == ["first"])
    }

    @Test("A focused TextField WITHOUT onSubmit lets Return trigger the default")
    func textFieldWithoutSubmitFallsThrough() {
        final class Box { var fired = 0 }
        let box = Box()
        var text = ""
        let view = VStack {
            TextField("User", text: Binding(get: { text }, set: { text = $0 }))
            Button("Sign in") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // Type something, then Return: the field has no submit handler, so
        // Return falls through and signs in — the macOS dialog behaviour.
        _ = dispatch(KeyEvent(character: "x"), focus: focus, shortcuts: shortcuts)
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.fired == 1, "Return in a submit-less field triggers the default")
        #expect(text == "x", "typing still reached the field")
    }
}

@MainActor
@Suite("keyboard shortcut key equivalents")
struct KeyEquivalentShortcutTests {

    @Test("A bare key equivalent fires on that character alone")
    func bareKeyFires() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(KeyboardShortcut("1", modifiers: [])) { fired += 1 }

        #expect(registry.trigger(for: KeyEvent(key: .character("1"))))
        #expect(fired == 1)
        #expect(!registry.trigger(for: KeyEvent(key: .character("2"))), "a different key does nothing")
        #expect(fired == 1)
    }

    @Test("Modifiers must match exactly, not merely be present")
    func modifiersMatchExactly() {
        let registry = KeyboardShortcutRegistry()
        var bare = 0
        var ctrl = 0
        registry.register(KeyboardShortcut("q", modifiers: [])) { bare += 1 }
        registry.register(KeyboardShortcut("q", modifiers: .control)) { ctrl += 1 }

        _ = registry.trigger(for: KeyEvent(key: .character("q")))
        #expect((bare, ctrl) == (1, 0))
        _ = registry.trigger(for: KeyEvent(key: .character("q"), ctrl: true, alt: false, shift: false))
        #expect((bare, ctrl) == (1, 1), "Ctrl-Q must not fire the plain-q shortcut, or vice versa")
    }

    @Test("A Command shortcut can never fire — a terminal does not report it")
    func commandNeverFires() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        // SwiftUI's default modifier set. Kept literal rather than quietly
        // rewritten to a bare key: an app that says ⌘Q must not quit on "q".
        registry.register(KeyboardShortcut("q")) { fired += 1 }

        #expect(!registry.trigger(for: KeyEvent(key: .character("q"))))
        #expect(
            !registry.trigger(
                for: KeyEvent(key: .character("q"), ctrl: true, alt: true, shift: true)))
        #expect(fired == 0)
    }

    /// SwiftUI defines `.defaultAction` AS unmodified Return and
    /// `.cancelAction` AS unmodified Escape. An incoming bare Return/Escape
    /// resolves to the semantic role before the key table, so the spelled-out
    /// forms could never fire — they normalise to the roles at construction.
    @Test("Bare .return / .escape spellings ARE the semantic roles")
    func bareReturnEscapeNormalise() {
        #expect(KeyboardShortcut(.return, modifiers: []) == .defaultAction)
        #expect(KeyboardShortcut(.escape, modifiers: []) == .cancelAction)

        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(KeyboardShortcut(.return, modifiers: [])) { fired += 1 }
        #expect(registry.trigger(for: KeyEvent(key: .enter)))
        #expect(fired == 1)
    }

    /// The `.bare` Command stand-in strips ⌘⏎ down to unmodified Return —
    /// the resolved form must normalise to the role too, not die as a key.
    @Test("A .bare command key resolves ⌘-Return to the default action")
    func bareCommandReturnResolves() {
        #expect(KeyboardShortcut(.return).resolved(commandKey: .bare) == .defaultAction)
        #expect(KeyboardShortcut(.escape).resolved(commandKey: .bare) == .cancelAction)
    }

    /// Held with a modifier, Return/Escape are ordinary key equivalents —
    /// only the BARE forms are the semantic roles.
    @Test("Modified .return stays a key equivalent")
    func modifiedReturnStaysKeyEquivalent() {
        #expect(KeyboardShortcut(.return, modifiers: .option) != .defaultAction)

        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(KeyboardShortcut(.return, modifiers: .option)) { fired += 1 }
        #expect(registry.trigger(for: KeyEvent(key: .enter, ctrl: false, alt: true, shift: false)))
        #expect(fired == 1)
        #expect(!registry.trigger(for: KeyEvent(key: .enter)), "bare Return is the role, not this key")
    }

    /// A terminal does not report Shift for a printable key — it sends the
    /// shifted CHARACTER and no modifier bits (`KeyEvent.parse`'s printable
    /// branch builds `KeyEvent(character:)` with nothing set). So Shift has to
    /// be read off the case, or `("a", [.shift])` would be permanently dead
    /// while `("a", [])` fired for "A" as well.
    @Test("Shift on a printable key comes from the case, not the event flag")
    func shiftComesFromTheCase() {
        let registry = KeyboardShortcutRegistry()
        var lower = 0
        var upper = 0
        registry.register(KeyboardShortcut("a", modifiers: [])) { lower += 1 }
        registry.register(KeyboardShortcut("a", modifiers: .shift)) { upper += 1 }

        // Exactly what the parser produces for the two keystrokes: no flags.
        _ = registry.trigger(for: KeyEvent(key: .character("a")))
        #expect((lower, upper) == (1, 0), "lower-case a fires only the unshifted binding")
        _ = registry.trigger(for: KeyEvent(key: .character("A")))
        #expect((lower, upper) == (1, 1), "…and A fires only the shifted one")
    }

    @Test("An uppercase literal IS the shifted binding")
    func uppercaseLiteralImpliesShift() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        // SwiftUI's reading of `keyboardShortcut("A")`.
        registry.register(KeyboardShortcut("A", modifiers: [])) { fired += 1 }

        #expect(!registry.trigger(for: KeyEvent(key: .character("a"))), "not the unshifted key")
        #expect(registry.trigger(for: KeyEvent(key: .character("A"))))
        #expect(fired == 1)
    }

    /// SwiftUI on macOS 15: `KeyEquivalent("A").character` is "A", and "A" is
    /// not "a". The folding to lower case and Shift belongs to the shortcut
    /// that matches it, not to the key, which a ``KeyPress`` also reports.
    @Test("A key equivalent keeps the case it is written in")
    func keyEquivalentKeepsItsCase() {
        let upper = KeyEquivalent("A")
        #expect(upper.character == "A")
        #expect(upper != KeyEquivalent("a"))
        #expect(Set([upper, KeyEquivalent("a")]).count == 2)
        var key = KeyEquivalent("x")
        key.character = "y"
        #expect(key == "y")
    }

    @Test("The semantic roles still work alongside key equivalents")
    func semanticsStillWork() {
        let registry = KeyboardShortcutRegistry()
        var accepted = 0
        var cancelled = 0
        registry.register(.defaultAction) { accepted += 1 }
        registry.register(.cancelAction) { cancelled += 1 }
        registry.register(KeyboardShortcut("x", modifiers: [])) { }

        #expect(registry.trigger(for: KeyEvent(key: .enter)))
        #expect(registry.trigger(for: KeyEvent(key: .escape)))
        #expect((accepted, cancelled) == (1, 1))
    }

    @Test("A shortcut prints itself the way a macOS menu prints a key equivalent")
    func displayString() {
        #expect(KeyboardShortcut("7", modifiers: []).displayString == "7")
        // A letter is drawn in upper case, with or without a modifier.
        #expect(KeyboardShortcut("s", modifiers: []).displayString == "S")
        #expect(KeyboardShortcut("s", modifiers: .control).displayString == "⌃S")
        #expect(KeyboardShortcut("s", modifiers: .option).displayString == "⌥S")
        // So Shift is a symbol of its own, whether written as the case or asked
        // for — the case is how a terminal says it.
        #expect(KeyboardShortcut("S", modifiers: []).displayString == "⇧S")
        #expect(KeyboardShortcut("s", modifiers: .shift).displayString == "⇧S")
        // Redo's Control-Shift-Z is not printed as Undo's Control-Z.
        #expect(KeyboardShortcut("z", modifiers: [.control, .shift]).displayString == "⌃⇧Z")
        #expect(KeyboardShortcut("Z", modifiers: .control).displayString == "⌃⇧Z")
        #expect(KeyboardShortcut("z", modifiers: .control).displayString == "⌃Z")
        // macOS's order, ⌃ ⌥ ⇧ ⌘, however the set was written.
        #expect(KeyboardShortcut("z", modifiers: [.shift, .option, .control]).displayString == "⌃⌥⇧Z")
        // The semantic roles have no key to print.
        #expect(KeyboardShortcut.defaultAction.displayString == nil)
        #expect(KeyboardShortcut.cancelAction.displayString == nil)
    }

    /// The measure pass asks for the shortcut too — it has to reserve the
    /// width the hint will occupy — so a one-shot claim would hand the
    /// shortcut to the measure and leave the render, the pass that actually
    /// registers the action, with nothing.
    @Test("One control can claim its shortcut on every pass of a frame")
    func claimIsIdempotentForOneControl() {
        let identity = ViewIdentity(path: "Root/Button")
        let other = ViewIdentity(path: "Root/OtherButton")
        let assignment = KeyboardShortcutAssignment(KeyboardShortcut("s", modifiers: []))

        #expect(assignment.claim(by: identity, isMeasuring: true) != nil, "measure pass")
        #expect(
            assignment.claim(by: identity, isMeasuring: false) != nil,
            "render pass, same control")
        #expect(
            assignment.claim(by: other, isMeasuring: false) == nil,
            "a second control gets nothing")
        #expect(
            assignment.claim(by: other, isMeasuring: true) == nil,
            "…and nothing on the measure pass either, where the first control claimed")
    }

    /// A measure and a render need not lay the control out in the same place: a
    /// menu measures its column hugging to decide whether it overflows, then
    /// draws the overflowing one inside a `ScrollView`, and every row's identity
    /// gains a component in between. With one latch the render looked like a
    /// second control and was refused — so the row lost the key equivalent the
    /// measure had just reserved space for.
    @Test("A measure's claim does not bar the render from claiming elsewhere")
    func measureClaimDoesNotBarADifferentRenderIdentity() {
        let measured = ViewIdentity(path: "Root/Column/Button")
        let drawn = ViewIdentity(path: "Root/Column/ScrollView/Button")
        let assignment = KeyboardShortcutAssignment(KeyboardShortcut("s", modifiers: []))

        #expect(assignment.claim(by: measured, isMeasuring: true) != nil, "measured here")
        #expect(assignment.claim(by: drawn, isMeasuring: false) != nil, "drawn there")
        // …and the render latch is still a latch: a genuine second control in the
        // drawn tree gets nothing.
        #expect(
            assignment.claim(by: ViewIdentity(path: "Root/Column/ScrollView/Other"),
                isMeasuring: false) == nil,
            "the render's own latch still holds")
    }
}

@MainActor
@Suite("command key substitution")
struct CommandKeySubstitutionTests {

    /// The portability point: SwiftUI source says ⌘S, and it should work here
    /// without every shared shortcut being rewritten for the terminal.
    @Test("A Command shortcut is delivered by whatever stands in for Command")
    func commandResolves() {
        let shortcut = KeyboardShortcut("s")  // SwiftUI's default: .command

        let asControl = shortcut.resolved(commandKey: .control)
        #expect(asControl != nil)
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(asControl!) { fired += 1 }
        #expect(
            registry.trigger(
                for: KeyEvent(key: .character("s"), ctrl: true, alt: false, shift: false)))
        #expect(!registry.trigger(for: KeyEvent(key: .character("s"))), "…and not the bare key")
        #expect(fired == 1)
    }

    @Test(
        "Each binding delivers Command as the modifier it names",
        arguments: [
            (CommandKeyBinding.control, (ctrl: true, alt: false)),
            (.option, (ctrl: false, alt: true)),
            (.bare, (ctrl: false, alt: false)),
        ])
    func eachBinding(binding: CommandKeyBinding, flags: (ctrl: Bool, alt: Bool)) {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        let resolved = KeyboardShortcut("s").resolved(commandKey: binding)
        registry.register(resolved!) { fired += 1 }
        #expect(
            registry.trigger(
                for: KeyEvent(
                    key: .character("s"), ctrl: flags.ctrl, alt: flags.alt, shift: false)))
        #expect(fired == 1)
    }

    @Test("`.unavailable` binds nothing rather than guessing")
    func unavailableBindsNothing() {
        #expect(KeyboardShortcut("s").resolved(commandKey: .unavailable) == nil)
        // A shortcut that never mentioned Command is untouched either way.
        let bare = KeyboardShortcut("s", modifiers: [])
        #expect(bare.resolved(commandKey: .unavailable) == bare)
    }

    @Test("A shortcut without Command is not rewritten")
    func nonCommandUntouched() {
        let ctrl = KeyboardShortcut("s", modifiers: .control)
        #expect(ctrl.resolved(commandKey: .option) == ctrl, "only .command is substituted")
    }

    /// `KeyEvent.parse` matches Tab, Return, newline and Escape BEFORE the
    /// Ctrl-letter range, so those combinations never arrive as a modified
    /// letter — no amount of remapping can deliver ⌘I as Ctrl-I. Better to be
    /// able to ask than to wonder why one menu item is dead.
    ///
    /// Ctrl-C and Ctrl-Z are not among them. They used to be reported as
    /// "taken by job control", which is what a cooked terminal does with them;
    /// raw mode clears `ISIG`, so they arrive as keys (and
    /// `InputHandlerTests` fires a ⌘C shortcut on one).
    @Test("The C0 collisions are reported, not silently dead")
    func c0CollisionsAreQueryable() {
        // Ctrl-H is Backspace: `KeyEvent.parse` reads 0x08 before the
        // Control range, so a ⌘H shortcut could never fire.
        for key: KeyEquivalent in ["h", "i", "j", "m", "["] {
            let resolved = KeyboardShortcut(key).resolved(commandKey: .control)
            #expect(
                resolved?.isDeliverableInTerminal == false,
                "Ctrl-\(key.character) is spoken for by the C0 range")
        }
        for key: KeyEquivalent in ["s", "o", "n", "1", "c", "z"] {
            let resolved = KeyboardShortcut(key).resolved(commandKey: .control)
            #expect(resolved?.isDeliverableInTerminal == true)
        }
        // Under Option there is no C0 range to collide with.
        #expect(
            KeyboardShortcut("i").resolved(commandKey: .option)?.isDeliverableInTerminal == true)
        // And an unresolved Command shortcut is honestly undeliverable.
        #expect(KeyboardShortcut("s").isDeliverableInTerminal == false)
    }

    /// SwiftUI's bits, read on macOS 15: a modifier set an app stores as its
    /// raw value must read back as the same set under either framework.
    @Test("EventModifiers has SwiftUI's raw values, Caps Lock included")
    func eventModifierRawValues() {
        #expect(EventModifiers.capsLock.rawValue == 1)
        #expect(EventModifiers.shift.rawValue == 2)
        #expect(EventModifiers.control.rawValue == 4)
        #expect(EventModifiers.option.rawValue == 8)
        #expect(EventModifiers.command.rawValue == 16)
        #expect(EventModifiers.numericPad.rawValue == 32)
        #expect(EventModifiers.all.rawValue == 63)
    }

    /// A terminal reports neither the Caps Lock state nor the numeric pad, so a
    /// chord that needs either can never arrive — and says so when asked.
    @Test("A Caps Lock or numeric-pad shortcut is undeliverable and never fires")
    func capsLockAndNumericPadNeverFire() {
        for modifiers: EventModifiers in [[.capsLock], [.numericPad], [.control, .capsLock]] {
            let shortcut = KeyboardShortcut("x", modifiers: modifiers)
            #expect(shortcut.isDeliverableInTerminal == false, "\(modifiers)")

            let registry = KeyboardShortcutRegistry()
            var fired = 0
            registry.register(shortcut) { fired += 1 }
            // Caps Lock arrives as the uppercase letter, so neither spelling of
            // the key may reach a Caps Lock chord.
            // Nor may a terminal that does report them: shortcuts ignore both.
            let events = [
                KeyEvent(key: .character("x")),
                KeyEvent(character: "X"),
                KeyEvent(key: .character("x"), ctrl: true),
                KeyEvent(key: .character("X"), capsLock: true),
                KeyEvent(key: .character("x"), ctrl: true, capsLock: true),
                KeyEvent(key: .character("x"), numericPad: true),
            ]
            for event in events {
                #expect(!registry.trigger(for: event), "\(modifiers) \(event)")
            }
            #expect(fired == 0, "\(modifiers)")
        }
    }
}

/// Caps Lock and the keypad, where the kitty keyboard protocol reports them,
/// are states a key is pressed in, not chords: a shortcut matches through
/// them, as AppKit's key equivalents do.
@MainActor
@Suite("Keyboard shortcuts under reported lock and keypad states")
struct KeyboardShortcutLockStateTests {
    @Test("Ctrl-S with Caps Lock on fires Ctrl-S, and a keypad 5 fires 5")
    func lockAndKeypadDoNotBlockAShortcut() {
        let registry = KeyboardShortcutRegistry()
        var fired: [String] = []
        registry.register(KeyboardShortcut("s", modifiers: .control)) { fired.append("^s") }
        registry.register(KeyboardShortcut("5", modifiers: [])) { fired.append("5") }
        registry.register(KeyboardShortcut("A", modifiers: [])) { fired.append("A") }
        #expect(registry.trigger(for: KeyEvent(key: .character("s"), ctrl: true, capsLock: true)))
        #expect(registry.trigger(for: KeyEvent(key: .character("5"), numericPad: true)))
        // Caps Lock typing a capital reads as that capital, as a legacy
        // terminal's uppercase byte does.
        #expect(registry.trigger(for: KeyEvent(key: .character("A"), capsLock: true)))
        #expect(fired == ["^s", "5", "A"])
    }

    @Test("Escape with Caps Lock on is still the exit command")
    func exitCommandThroughCapsLock() {
        let harness = InputChainHarness()
        var exits = 0
        harness.play([KeyEvent(key: .escape, capsLock: true)]) {
            Text("leaf").focusable().onExitCommand { exits += 1 }
        }
        #expect(exits == 1)
    }

    @Test("A press's modifiers include Caps Lock and the keypad where they are reported")
    func keyPressModifiersCarryTheStates() {
        #expect(KeyPress(KeyEvent(key: .character("A"), capsLock: true))?.modifiers == .capsLock)
        #expect(KeyPress(KeyEvent(key: .character("5"), numericPad: true))?.modifiers == .numericPad)
        #expect(
            KeyPress(KeyEvent(key: .character("s"), ctrl: true, capsLock: true))?.modifiers
                == [.control, .capsLock])
    }
}

/// SwiftUI's `KeyboardShortcut` members, read on macOS 15: the key and the
/// modifiers as written, the semantic roles as Return and Escape with none, and
/// equality over the three stored values.
@MainActor
@Suite("KeyboardShortcut's key, modifiers and localization")
struct KeyboardShortcutMemberTests {
    @Test("The key and modifiers read back as written")
    func membersReadBack() {
        let upper = KeyboardShortcut("A")
        #expect(upper.key == "A")
        #expect(upper.modifiers == .command)
        #expect(upper.localization == .automatic)
        #expect(KeyboardShortcut("s", modifiers: [.control, .option]).modifiers == [.control, .option])
        #expect(KeyboardShortcut("a", modifiers: [], localization: .custom).localization == .custom)
    }

    @Test("The semantic roles are Return and Escape with no modifiers")
    func rolesAreKeys() {
        #expect(KeyboardShortcut.defaultAction.key == .return)
        #expect(KeyboardShortcut.defaultAction.modifiers.isEmpty)
        #expect(KeyboardShortcut.cancelAction.key == .escape)
        #expect(KeyboardShortcut.cancelAction.modifiers.isEmpty)
        #expect(KeyboardShortcut(.return, modifiers: []) == .defaultAction)
        #expect(KeyboardShortcut(.escape, modifiers: []) == .cancelAction)
    }

    /// Equal shortcuts are equal values; two spellings of one chord are not,
    /// though they fire on the same key.
    @Test("Equality is over key, modifiers and localization, as SwiftUI's is")
    func equality() {
        #expect(KeyboardShortcut("A", modifiers: []) != KeyboardShortcut("a", modifiers: .shift))
        #expect(KeyboardShortcut("a", localization: .custom) != KeyboardShortcut("a"))
        #expect(KeyboardShortcut("a", localization: .automatic) == KeyboardShortcut("a"))

        let registry = KeyboardShortcutRegistry()
        var fired: [String] = []
        registry.register(KeyboardShortcut("A", modifiers: [])) { fired.append("A") }
        #expect(registry.trigger(for: KeyEvent(character: "A")))
        registry.register(KeyboardShortcut("a", modifiers: .shift)) { fired.append("shift a") }
        #expect(registry.trigger(for: KeyEvent(character: "A")))
        #expect(fired == ["A", "shift a"], "one chord: the later registration replaced the earlier")
    }

    @Test("A changed key or modifier changes what the shortcut fires on")
    func settable() {
        var shortcut = KeyboardShortcut("a", modifiers: [])
        shortcut.key = "b"
        shortcut.modifiers = .control
        shortcut.localization = .withoutMirroring
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(shortcut) { fired += 1 }
        #expect(!registry.trigger(for: KeyEvent(key: .character("a"))))
        #expect(registry.trigger(for: KeyEvent(key: .character("b"), ctrl: true)))
        #expect(fired == 1)
    }

    @Test("A localized shortcut fires on its key, and a nil one assigns nothing")
    func viewModifiers() {
        final class Log { var fired: [String] = [] }
        let log = Log()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .character("l")), KeyEvent(key: .character("n")), KeyEvent(key: .character("o"))]) {
            VStack {
                Button("Localized") { log.fired.append("localized") }
                    .keyboardShortcut("l", modifiers: [], localization: .withoutMirroring)
                Button("Nil") { log.fired.append("nil") }
                    .keyboardShortcut(nil)
                // `nil` leaves the environment as it found it: the shortcut
                // assigned outside still reaches the button.
                VStack {
                    Button("Outer") { log.fired.append("outer") }
                        .keyboardShortcut(nil)
                }
                .keyboardShortcut("o", modifiers: [])
            }
        }
        #expect(log.fired == ["localized", "outer"])
    }

    // MARK: The environment value

    @Test("\\.keyboardShortcut reads the shortcut assigned to the view or an ancestor")
    func environmentValue() {
        let harness = InputChainHarness()
        func shown(_ view: some View) -> String {
            harness.frame(view).lines.map(\.stripped).joined().trimmingCharacters(in: .whitespaces)
        }
        #expect(shown(ShortcutReader()) == "none")
        #expect(shown(ShortcutReader().keyboardShortcut(.defaultAction)) == "default")
        #expect(shown(ShortcutReader().keyboardShortcut("s", modifiers: [])) == "s")
        #expect(shown(VStack { ShortcutReader() }.keyboardShortcut(.cancelAction)) == "cancel")
        #expect(shown(ShortcutReader().keyboardShortcut(nil)) == "none")
    }

    @Test("A button style reads the button's shortcut, as SwiftUI's documentation does")
    func buttonStyleReadsIt() {
        let harness = InputChainHarness()
        let text = harness.frame(Button("Go") {}.buttonStyle(MarksShortcut()).keyboardShortcut(.defaultAction))
            .lines.map(\.stripped).joined()
        #expect(text.contains("default"), "\(text)")
    }

    /// The carrier is new every frame and compares by identity, so the memo
    /// below it would serve the old reading unless the SHORTCUT is noted.
    @Test("A memo below the modifier does not serve a reading of the old shortcut")
    func memoSeesTheChange() {
        let harness = InputChainHarness()
        func shown(_ isDefault: Bool) -> String {
            harness.frame(VStack { ShortcutReader().equatable() }.keyboardShortcut(isDefault ? .defaultAction : .cancelAction))
                .lines.map(\.stripped).joined().trimmingCharacters(in: .whitespaces)
        }
        #expect(shown(true) == "default")
        #expect(shown(true) == "default")
        #expect(shown(false) == "cancel")
        #expect(shown(false) == "cancel")
        #expect(shown(true) == "default")
    }
}

/// Prints the shortcut its environment carries; equal to any other, so it is
/// served from a memo whenever it can be.
private struct ShortcutReader: View, @MainActor Equatable {
    @Environment(\.keyboardShortcut) private var shortcut

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Text(describe(shortcut))
    }

    private func describe(_ shortcut: KeyboardShortcut?) -> String {
        guard let shortcut else { return "none" }
        if shortcut == .defaultAction { return "default" }
        if shortcut == .cancelAction { return "cancel" }
        return String(shortcut.key.character)
    }
}

/// SwiftUI's documented use: a style that reads the button's shortcut.
private struct MarksShortcut: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The label is left out: what is under test is the environment the
        // style's body renders in.
        _ = configuration
        return ShortcutReader()
    }
}
