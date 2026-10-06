//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcut.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - KeyboardShortcut

/// A key a ``KeyboardShortcut`` is triggered by, mirroring SwiftUI's
/// `KeyEquivalent`.
///
/// Case matters, as it does in SwiftUI: `KeyEquivalent("A")` is not
/// `KeyEquivalent("a")`. A terminal sends a shifted printable as the shifted
/// *character* with no modifier bits (see `KeyEvent.parse`), so the case is all
/// there is of the Shift, and a ``KeyboardShortcut`` reads an uppercase key as
/// the Shift chord of its lowercase one — SwiftUI's reading of an uppercase
/// literal.
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    /// The character this equivalent stands for, as written.
    public var character: Character

    public init(_ character: Character) {
        self.character = character
    }

    /// A key literal is a single character, as in SwiftUI.
    public typealias ExtendedGraphemeClusterLiteralType = Character
    /// A key literal is a single character, as in SwiftUI.
    public typealias UnicodeScalarLiteralType = Character

    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }

    /// The space bar.
    public static let space = Self(" ")

    // The non-printable keys, spelled the way SwiftUI spells them — same names,
    // same scalars. The arrows and navigation keys are AppKit's private-use
    // function-key block (`NSUpArrowFunctionKey` = U+F700 and its neighbours),
    // which is what SwiftUI's own `KeyEquivalent` uses; the rest are their
    // control characters. A terminal sends these as escape sequences rather
    // than as these scalars, so ``KeyboardShortcut/trigger(for:)`` maps a parsed
    // ``Key`` onto them — nothing ever types one of these characters directly.
    /// The up arrow.
    public static let upArrow = Self("\u{F700}")
    /// The down arrow.
    public static let downArrow = Self("\u{F701}")
    /// The left arrow.
    public static let leftArrow = Self("\u{F702}")
    /// The right arrow.
    public static let rightArrow = Self("\u{F703}")
    /// Page Up.
    public static let pageUp = Self("\u{F72C}")
    /// Page Down.
    public static let pageDown = Self("\u{F72D}")
    /// Home.
    public static let home = Self("\u{F729}")
    /// End.
    public static let end = Self("\u{F72B}")
    /// Forward delete.
    public static let deleteForward = Self("\u{F728}")
    /// Backspace / delete-backwards.
    public static let delete = Self("\u{7F}")
    /// Return.
    public static let `return` = Self("\u{D}")
    /// Escape.
    public static let escape = Self("\u{1B}")
    /// Tab.
    public static let tab = Self("\u{9}")

    /// This key in lower case, and whether that took a Shift away: what a
    /// shortcut matches on, since a terminal says Shift only by the case of the
    /// character it sends.
    var foldingCase: (key: Self, shifted: Bool) {
        guard character.isUppercase else { return (self, false) }
        return (Self(Character(character.lowercased())), true)
    }
}

/// The modifier keys a shortcut requires.
///
/// TUI-specific reality: a terminal reports Control, Option/Alt and Shift, and
/// does **not** report Command — see `Documentation/Terminal-compatibility.md`.
/// Caps Lock and the numeric pad are reported only where the terminal speaks
/// the kitty keyboard protocol (``EnvironmentValues/keyboardReporting``).
/// A shortcut declared with ``command`` therefore can never fire here. That is
/// left deliberately literal rather than quietly rewritten to a bare key: an
/// app that says ⌘Q should not fire on a lone "q".
///
/// The raw values are SwiftUI's, so a set stored as its `rawValue` reads back
/// the same under either framework.
public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The Caps Lock key.
    ///
    /// In a ``KeyPress``'s modifiers while Caps Lock is on, where the terminal
    /// speaks the kitty keyboard protocol
    /// (``KeyboardReporting/reportsLockStates``); and seen by
    /// ``View/onModifierKeysChanged(mask:initial:_:)`` when it is toggled
    /// there. In a terminal's legacy encodings it is never reported: a letter
    /// typed under Caps Lock arrives as the uppercase character, which is to
    /// say as Shift and that letter. A keyboard shortcut ignores it, as
    /// AppKit's key equivalents do, and one that requires it can never fire.
    public static let capsLock = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let option = Self(rawValue: 1 << 3)
    /// Never reported with a key — see the type documentation. Where the
    /// terminal speaks the kitty keyboard protocol, ⌘ held on its own is
    /// reported as a modifier key, so
    /// ``View/onModifierKeysChanged(mask:initial:_:)`` can see it.
    public static let command = Self(rawValue: 1 << 4)
    /// Any key on the numeric keypad.
    ///
    /// In a ``KeyPress``'s modifiers for a keypad key, where the terminal
    /// speaks the kitty keyboard protocol
    /// (``KeyboardReporting/reportsNumericPad``). Not set on the arrow keys,
    /// which macOS also counts as the numeric pad. In a terminal's legacy
    /// encodings a keypad digit arrives as the digit, so it is never
    /// reported. A keyboard shortcut ignores it, and one that requires it can
    /// never fire.
    public static let numericPad = Self(rawValue: 1 << 5)
    public static let all: Self = [.capsLock, .shift, .control, .option, .command, .numericPad]

    /// The modifiers a terminal actually reports on `event`: Control, Option
    /// and Shift, and Caps Lock and the numeric pad where it speaks the kitty
    /// keyboard protocol.
    init(_ event: KeyEvent) {
        var result: Self = []
        if event.ctrl { result.insert(.control) }
        if event.alt { result.insert(.option) }
        if event.shift { result.insert(.shift) }
        if event.capsLock { result.insert(.capsLock) }
        if event.numericPad { result.insert(.numericPad) }
        self = result
    }

    /// The modifiers held on a key that are chords rather than states: a
    /// keyboard shortcut matches on these alone, as AppKit's key equivalents
    /// ignore Caps Lock and the keypad.
    var chordModifiers: Self {
        subtracting([.capsLock, .numericPad])
    }
}

/// A keyboard shortcut a control can adopt, mirroring SwiftUI's
/// `KeyboardShortcut`: either a key equivalent (``init(_:modifiers:)``) or one
/// of the two semantic roles.
///
/// Attach with ``View/keyboardShortcut(_:)-(KeyboardShortcut)``:
///
/// ```swift
/// Dialog("Sign in") {
///     TextField("User", text: $user)
///     SecureField("Password", text: $pass)
/// } footer: {
///     Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
///     Button("Sign in") { signIn() }.keyboardShortcut(.defaultAction)
/// }
/// ```
///
/// ``defaultAction`` makes its button the *default button*: Return/Enter
/// activates it whenever the focused control doesn't handle the key itself.
/// A multi-line ``TextEditor`` (Return inserts a newline), a list with a row
/// activation, or a focused `Button` all keep their Return — the default
/// fires only when the key falls through, macOS responder-chain style. A
/// ``TextField`` *without* an `onSubmit` handler lets Return fall through, so
/// pressing Return in a dialog's field triggers the default button.
///
/// > Note: A terminal never reports the Command key, so SwiftUI's default
/// > `modifiers: .command` is remapped at registration to whatever
/// > ``EnvironmentValues/commandKey`` says stands in for it here — see
/// > ``CommandKeyBinding``. Under the default, Control, ⌘F is Ctrl-F, which is
/// > also a text control's Emacs chord for forward a character. The shortcut
/// > wins such a chord from a focused text control; see <doc:KeyboardShortcuts>.
public struct KeyboardShortcut: Hashable, Sendable {
    /// What activates this shortcut.
    enum Trigger: Hashable, Sendable {
        case defaultAction
        case cancelAction
        case key(KeyEquivalent, EventModifiers)
    }

    /// The key the user presses, with ``modifiers``, to activate the shortcut —
    /// as written: `"A"` stays `"A"`, which the shortcut reads as Shift-A.
    public var key: KeyEquivalent

    /// The modifier keys held with ``key``, as written. A `.command` here is the
    /// Command that SwiftUI source names; what stands in for it in a terminal is
    /// decided where the shortcut registers (see ``CommandKeyBinding``).
    public var modifiers: EventModifiers

    /// How the shortcut takes part in keyboard localization. Recorded and
    /// compared; it changes nothing a terminal does — see ``Localization``.
    public var localization: Localization

    /// What activates this shortcut: ``key`` and ``modifiers`` in the one
    /// spelling an incoming event is matched against.
    var trigger: Trigger { Self.normalised(key, modifiers) }

    /// The default button: Return/Enter activates it when the focused control
    /// lets the key fall through. As in SwiftUI, it is Return with no
    /// modifiers, and equal to `KeyboardShortcut(.return, modifiers: [])`.
    public static let defaultAction = Self(.return, modifiers: [])

    /// The cancel button: Escape activates it when nothing closer to the user
    /// (an open drop-down, an app-level back binding) consumes the key first.
    /// Escape with no modifiers.
    public static let cancelAction = Self(.escape, modifiers: [])

    /// A key equivalent, à la SwiftUI's `KeyboardShortcut(_:modifiers:)`.
    ///
    /// The default is SwiftUI's `.command`, which a terminal never reports —
    /// so a TUI shortcut is almost always written with `modifiers: []`, a bare
    /// key. That is the form a terminal menu wants anyway: "press 1 for the
    /// first item".
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.init(key, modifiers: modifiers, localization: .automatic)
    }

    /// A key equivalent with a localization strategy, à la SwiftUI's
    /// `KeyboardShortcut(_:modifiers:localization:)`.
    ///
    /// - Parameters:
    ///   - key: The key, as for ``init(_:modifiers:)``.
    ///   - modifiers: The modifiers, as for ``init(_:modifiers:)``.
    ///   - localization: How the shortcut takes part in keyboard localization;
    ///     see ``Localization`` for what that means in a terminal.
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
    }

    /// What a key and modifiers trigger, in the one spelling an incoming event
    /// is matched against.
    ///
    /// - An uppercase key IS the Shift chord of its lowercase one (see
    ///   ``KeyEquivalent``): `("A", [])` and `("a", [.shift])` are one trigger.
    /// - The spelled-out forms of the two semantic roles ARE those roles —
    ///   SwiftUI defines `.defaultAction` as unmodified Return and
    ///   `.cancelAction` as unmodified Escape. An incoming bare Return/Escape
    ///   event resolves to the role before the key table
    ///   (see ``trigger(for:)``), so an un-normalised `.key(.return, [])`
    ///   could never fire: registered, listed, and permanently dead.
    private static func normalised(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> Trigger {
        let (key, shifted) = key.foldingCase
        let modifiers = shifted ? modifiers.union(.shift) : modifiers
        guard modifiers.isEmpty else { return .key(key, modifiers) }
        if key == .return { return .defaultAction }
        if key == .escape { return .cancelAction }
        return .key(key, modifiers)
    }

    /// This shortcut with ``EventModifiers/command`` replaced per `binding`,
    /// ready to register. Non-command shortcuts pass through untouched.
    func resolved(commandKey binding: CommandKeyBinding) -> Self? {
        guard modifiers.contains(.command) else { return self }
        var resolved = self
        resolved.modifiers.remove(.command)
        switch binding {
        case .unavailable: return nil
        case .control: resolved.modifiers.insert(.control)
        case .option: resolved.modifiers.insert(.option)
        // A `.bare` stand-in can strip ⌘⏎ / ⌘⎋ down to the semantic roles' own
        // keys, which `trigger` then reads as those roles.
        case .bare: break
        }
        return resolved
    }

    /// Whether every terminal can deliver this shortcut.
    ///
    /// `false` for a shortcut that needs a modifier a shortcut can never match
    /// on — ``EventModifiers/command`` (until `resolved(commandKey:)` replaces
    /// it), which no terminal reports with a key, and
    /// ``EventModifiers/capsLock`` and ``EventModifiers/numericPad``, which
    /// shortcuts ignore wherever they are reported.
    ///
    /// `false` too for the Control combinations the C0 range spends on other keys:
    /// Ctrl-H is Backspace, Ctrl-I is Tab, Ctrl-J and Ctrl-M are newline and
    /// Return, Ctrl-[ is Escape — `KeyEvent.parse` matches those *before* the
    /// Ctrl-letter range, so in a terminal's legacy encodings they never arrive
    /// as a modified letter. Where the terminal speaks the kitty keyboard
    /// protocol they do arrive, and such a shortcut fires
    /// (``KeyboardReporting/disambiguatesKeys``); this answers for every
    /// terminal, so it stays `false`. Consult it
    /// after `resolved(commandKey:)` — that is where a ⌘ shortcut becomes a
    /// Control one and can collide.
    ///
    /// Ctrl-C and Ctrl-Z are deliverable. A cooked terminal turns them into
    /// SIGINT and SIGTSTP, but TUIkit's raw mode turns both off as signal
    /// characters, so they arrive as keys like any other Control letter.
    /// Ctrl-Z is the app's undo by default (``UndoCommand/defaultShortcuts``),
    /// and a shortcut of the app's on it comes before that; layer 4 re-raises
    /// Ctrl-Z as SIGTSTP only when nothing before it claimed the key and the
    /// app's undo keys leave it out.
    ///
    /// `Ctrl-\` (`⌃\`) is deliverable, though it is the user's quit key, the
    /// one signal character raw mode leaves live, which the terminal driver
    /// turns into SIGQUIT before the app reads it — what lets it quit an app
    /// that has hung. While the app registers a shortcut on it (or a key
    /// handler declared for it) the driver's quit is masked, so the key
    /// arrives and fires; a ⌃\ nothing takes still quits, by the signal
    /// the driver would have raised (the owner's rule, 2026-10-06). Under the
    /// kitty keyboard protocol it arrives as a report, with the same result.
    /// The price: while the app binds it, a HUNG app does not quit by ⌃\\.
    ///
    /// Not so the chords some terminals send its byte, 0x1C, for: Ctrl-4 and
    /// Ctrl-| (Ctrl-Shift-\\). iTerm2 and Warp send it for both, Ghostty for
    /// Ctrl-4 and Apple Terminal for Ctrl-Shift-\\ (the owner's readings,
    /// 2026-10-06; Apple Terminal sends nothing at all for Ctrl-4), and xterm,
    /// VTE (GNOME Terminal and its kin), Konsole and the Linux console for
    /// both by their tables of the legacy encoding (not measured). There
    /// nothing in the byte says which key sent it, as nothing tells Ctrl-H
    /// from Backspace. TUIkit reads it as ⌃\\,
    /// and offers it as Ctrl-4, Ctrl-| and Ctrl-Shift-\ in turn, to the
    /// bindings declared for them, where no binding takes ⌃\\, so a ⌘4
    /// shortcut under `.commandKey(.control)`
    /// DOES fire on those terminals — unless the app binds ⌃\ too, which then
    /// wins. Under the kitty keyboard protocol, and on a terminal measured to
    /// send the chord apart (Ghostty's Ctrl-Shift-\\), it arrives as itself
    /// and fires.
    /// Since that holds only some of the time, these answer `false`.
    public var isDeliverableInTerminal: Bool {
        guard case .key(let key, let modifiers) = trigger else { return true }
        guard modifiers.isDisjoint(with: Self.unreportedModifiers) else { return false }
        guard modifiers.contains(.control) else { return true }
        // ⌃\ arrives; ⌃⇧\ is one of the chords that share its byte.
        if key.character == "\\" { return !modifiers.contains(.shift) }
        return !Self.controlCollisions.contains(key.character)
    }

    /// The keys whose Control chord a legacy encoding sends as another key's
    /// byte: H, I, J, M and `[` (Backspace, Tab, newline, Return and Escape),
    /// and `|` and `4`, which some terminals send as ⌃\\'s 0x1C.
    private static let controlCollisions: Set<Character> = ["h", "i", "j", "m", "[", "|", "4"]

    /// The modifiers a shortcut that needs one can never fire on: ⌘, which no
    /// terminal reports with a key, and the two states shortcuts ignore.
    private static let unreportedModifiers: EventModifiers = [.command, .capsLock, .numericPad]

    /// The trigger `event` would fire, or `nil` for a key no shortcut can name.
    ///
    /// The one place a `KeyEvent` becomes a shortcut key, because the Shift rule
    /// is easy to get wrong and expensive to get wrong twice: Shift comes from
    /// the CASE, not from `event.shift`. A terminal sends a shifted printable as
    /// the shifted character with no modifier bits, so trusting the flag would
    /// make `("a", [.shift])` permanently dead and let `("a", [])` fire for "A".
    static func trigger(for event: KeyEvent) -> Trigger? {
        let modifiers = EventModifiers(event).chordModifiers
        switch event.key {
        // A BARE Return or Escape is the semantic role — the default button,
        // the cancel button. Held with a modifier it is an ordinary key
        // equivalent, so `⌥⏎` can be bound without disturbing either role.
        case .enter where modifiers.isEmpty:
            return .defaultAction
        case .escape where modifiers.isEmpty:
            return .cancelAction
        case .character(let character):
            let (key, shifted) = KeyEquivalent(character).foldingCase
            var modifiers = modifiers
            modifiers.remove(.shift)
            if shifted { modifiers.insert(.shift) }
            return .key(key, modifiers)
        default:
            // The non-printable keys, via the table below. Function keys and
            // pasted text are not bindable, and map to nothing.
            return equivalents[event.key].map { .key($0, modifiers) }
        }
    }

    /// A parsed ``Key`` as the ``KeyEquivalent`` that stands for it. A terminal
    /// sends these as escape sequences, never as the scalars themselves, so this
    /// is the only way one is ever produced. Read backwards, it is how a
    /// shortcut's key is named (`Key.init(_:)`).
    static let equivalents: [Key: KeyEquivalent] = [
        .enter: .return, .escape: .escape, .tab: .tab, .space: .space,
        .up: .upArrow, .down: .downArrow, .left: .leftArrow, .right: .rightArrow,
        .pageUp: .pageUp, .pageDown: .pageDown, .home: .home, .end: .end,
        .backspace: .delete, .delete: .deleteForward,
    ]

    /// The printable form of this shortcut — what a menu row prints in its
    /// shortcut column — or `nil` for the semantic roles, which have no key to
    /// show. The status bar writes its undo and redo hints this way too, but
    /// for a letter held with nothing but Shift, which it writes in the case
    /// the key types (`u`, `U` for Shift-U), as its own items are written.
    ///
    /// Drawn as a macOS menu draws a key equivalent: the modifiers in the order
    /// ⌃ ⌥ ⇧ ⌘, then the key, a letter in upper case — `⌃S`, `⌃⇧Z` (Control-
    /// Shift-Z), `⌥_`, `⌥↑`, `⇟`, `⌘?`. An upper-case key is its Shift chord, so
    /// `KeyboardShortcut("Z", modifiers: .control)` is `⌃⇧Z` too. See
    /// `KeySymbols` for every key's symbol and how they were measured.
    ///
    /// Call it on a *resolved* shortcut (see `resolved(commandKey:)`), whose
    /// `.command` has been replaced by the key that stands in for it here: ⌘
    /// is drawn only where a shortcut still holds it.
    ///
    /// TUI-specific: SwiftUI has no printable form of a shortcut, AppKit
    /// drawing a menu item's key equivalent itself.
    public var displayString: String? {
        guard case .key(let key, let modifiers) = trigger else { return nil }
        return KeySymbols.chord(Key(key), modifiers)
    }
}

// MARK: - Command key

/// How ``EventModifiers/command`` is delivered in a terminal, which cannot
/// report the Command key itself.
///
/// The point is portability: the same `View` source should run under SwiftUI
/// and under TUIkit, and SwiftUI source says `⌘S`. Rather than making every
/// shared shortcut spell out a terminal-specific modifier, an app states once —
/// at its root — which key stands in for Command here.
///
/// ```swift
/// WindowGroup { RootView() }
///     .commandKey(.control)     // ⌘S is Ctrl-S in the terminal
/// ```
///
/// TUI-specific: SwiftUI has no equivalent, because on its platforms the
/// question does not arise.
public enum CommandKeyBinding: Sendable, Hashable {
    /// Control. The default, and the only modifier every terminal reports for
    /// letters — but it collides with the C0 range; see
    /// ``KeyboardShortcut/isDeliverableInTerminal``.
    case control

    /// Option / Alt. Reported as an ESC prefix or the high bit, and only when
    /// the terminal is configured for it (Apple Terminal composes accented
    /// characters instead unless "Use Option as Meta key" is on), so this is
    /// the less reliable choice — see `Documentation/Terminal-compatibility.md`.
    case option

    /// The bare key, no modifier. Closest to how a TUI usually binds commands,
    /// and the most collision-prone: `⌘Q` becomes plain "q".
    case bare

    /// `.command` shortcuts simply do not fire. Pick this to be certain
    /// nothing is silently rebound.
    case unavailable
}

private struct CommandKeyBindingKey: EnvironmentKey {
    static let defaultValue = CommandKeyBinding.control
}

extension EnvironmentValues {
    /// Which terminal modifier stands in for Command — see
    /// ``CommandKeyBinding``. Defaults to ``CommandKeyBinding/control``.
    public var commandKey: CommandKeyBinding {
        get { self[CommandKeyBindingKey.self] }
        set { self[CommandKeyBindingKey.self] = newValue }
    }
}

extension View {
    /// Chooses which terminal modifier stands in for Command in this subtree,
    /// so SwiftUI source written with `⌘` shortcuts works unchanged.
    ///
    /// - Parameter binding: The stand-in; see ``CommandKeyBinding``.
    /// - Returns: A view whose `.command` shortcuts bind to `binding`.
    public func commandKey(_ binding: CommandKeyBinding) -> some View {
        environment(\.commandKey, binding)
    }
}

// MARK: - Localization

extension KeyboardShortcut {
    /// How a shortcut takes part in keyboard localization — SwiftUI's
    /// `KeyboardShortcut.Localization`.
    ///
    /// On macOS, ``automatic`` remaps a shortcut whose character is hard to
    /// reach on the user's keyboard layout (`⌘[` becomes `⌘Ö` on a German one)
    /// and mirrors a directional one under a right-to-left layout;
    /// ``withoutMirroring`` remaps without mirroring, and ``custom`` does
    /// neither.
    ///
    /// A terminal does neither for any of them. It reports the CHARACTER a key
    /// typed, never the key's place on the keyboard, so a shortcut matches its
    /// character however the user's layout types it, and there is no layout to
    /// remap from; and TUIkit lays out left to right only (see
    /// ``EnvironmentValues/layoutDirection``), so nothing is mirrored. The value
    /// is recorded, compared and readable, and all three behave as ``custom``
    /// does.
    public struct Localization: Hashable, Sendable {
        /// The three strategies SwiftUI names.
        enum Style: Hashable, Sendable {
            case automatic, withoutMirroring, custom
        }

        let style: Style

        /// Remap to the layout's counterpart, and mirror under right-to-left.
        /// The default.
        public static let automatic = Self(style: .automatic)

        /// Remap, but do not mirror: for a shortcut whose direction is absolute,
        /// such as aligning text to the right.
        public static let withoutMirroring = Self(style: .withoutMirroring)

        /// Neither remap nor mirror: the app localizes the shortcut itself.
        public static let custom = Self(style: .custom)
    }
}

// MARK: - View Extension

extension View {
    /// Assigns a keyboard shortcut to the wrapped control — a semantic role,
    /// ``KeyboardShortcut/defaultAction`` (Return/Enter) or
    /// ``KeyboardShortcut/cancelAction`` (Escape), or a key equivalent. Attach
    /// it directly to a single `Button`; see ``KeyboardShortcut`` for the
    /// fall-through rules.
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        // Not `environment(\.assignedKeyboardShortcut, …)`: the carrier has to
        // know how deep in the value memos it was planted, and a subtree under
        // an uncomparable environment value can never be cached. See
        // `KeyboardShortcutModifier`.
        KeyboardShortcutModifier(content: self, assignment: KeyboardShortcutAssignment(shortcut))
    }

    /// Assigns a keyboard shortcut to the wrapped control, or — given `nil` —
    /// does nothing at all, as SwiftUI's does: a shortcut assigned further out
    /// still reaches the control.
    ///
    /// ```swift
    /// Button("Save") { save() }
    ///     .keyboardShortcut(isPrimary ? .defaultAction : nil)
    /// ```
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        KeyboardShortcutModifier(content: self, assignment: shortcut.map(KeyboardShortcutAssignment.init))
    }

    /// Assigns a key-equivalent shortcut to the wrapped control — SwiftUI's
    /// `keyboardShortcut(_:modifiers:)`.
    ///
    /// ```swift
    /// Button("Text Styles") { page = .textStyles }
    ///     .keyboardShortcut("1", modifiers: [])
    /// ```
    ///
    /// `modifiers` defaults to SwiftUI's `.command`, which a terminal never
    /// reports — pass `[]` for the bare-key form a TUI actually wants. See
    /// ``EventModifiers``.
    public func keyboardShortcut(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command
    ) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }

    /// Assigns a key-equivalent shortcut with a localization strategy to the
    /// wrapped control — SwiftUI's `keyboardShortcut(_:modifiers:localization:)`.
    ///
    /// The strategy is recorded on the shortcut; a terminal remaps and mirrors
    /// nothing under any of them (see ``KeyboardShortcut/Localization``).
    public func keyboardShortcut(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command,
        localization: KeyboardShortcut.Localization
    ) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
}
