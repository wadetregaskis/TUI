//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Event

/// Represents a keyboard event.
///
/// What a terminal can say about a key depends on how it encodes keys. In the
/// legacy encodings every terminal speaks, a key event is the bytes the key
/// produces: it is sent when the key goes down and again for each auto-repeat,
/// with nothing to tell the two apart, and a release sends nothing. So there
/// every event is a ``Phase/press``, ``capsLock`` is `false`, and so is
/// ``numericPad`` unless the keypad is in its application mode. Where the
/// terminal speaks the kitty keyboard protocol, which TUI
/// turns on when the terminal answers its query, the same fields carry what
/// the terminal reported: a repeat, a release, the Caps Lock state and the
/// keypad.
public struct KeyEvent: Equatable, Sendable {
    /// The key that was pressed.
    public let key: Key

    /// Whether the Ctrl modifier was held.
    public let ctrl: Bool

    /// Whether the Alt/Option modifier was held.
    public let alt: Bool

    /// Whether the Shift modifier was held.
    public let shift: Bool

    /// Whether Command (⌘) was held.
    ///
    /// Only from a terminal speaking the kitty keyboard protocol, which reports
    /// ⌘ as its Super modifier on a chord the terminal does not keep for
    /// itself. A legacy encoding never sends a ⌘ chord, so there it is always
    /// `false`. Such a chord reaches only `onKeyPress` handlers and the
    /// shortcuts that ask for a real ⌘
    /// (`View.keyboardShortcutsMatchCommand(_:)`): everything that matches a
    /// bare key — a text field's typing, type select, the status bar — never
    /// hears it, so ⌘K does not type a `k`.
    public let command: Bool

    /// Whether the key went down, repeated while held, or came up.
    ///
    /// Always ``Phase/press`` from a terminal in its legacy encoding, where a
    /// held key's repeats arrive as more presses and a release is never sent.
    /// A ``Phase/repeat`` or ``Phase/release`` comes only from a terminal
    /// speaking the kitty keyboard protocol.
    public let phase: Phase

    /// Whether Caps Lock was on. Reported only by a terminal speaking the kitty
    /// keyboard protocol; `false` everywhere else, where a Caps-Locked letter
    /// arrives as the uppercase character.
    public let capsLock: Bool

    /// Whether the key is on the numeric keypad. Reported by a terminal
    /// speaking the kitty keyboard protocol, and by one whose keypad is in its
    /// application mode (DECKPAM), which sends the keypad as `ESC O p`… —
    /// a mode TUI turns off at startup, so only a terminal that sends it
    /// anyway reports it that way. Elsewhere a keypad digit arrives as the
    /// digit.
    public let numericPad: Bool

    /// What a ``Key/paste(_:)`` carries beside its text: the clipboard's
    /// other types, a picture among them, where the terminal hands them over
    /// (OSC 5522 paste events). Empty for every other key, and for a paste a
    /// terminal could only bracket.
    package let pasteAttachments: [PasteAttachment]

    /// Creates a key event.
    public init(
        key: Key, ctrl: Bool = false, alt: Bool = false, shift: Bool = false, command: Bool = false,
        phase: Phase = .press, capsLock: Bool = false, numericPad: Bool = false
    ) {
        self.init(
            key: key, ctrl: ctrl, alt: alt, shift: shift, command: command, phase: phase, capsLock: capsLock,
            numericPad: numericPad, pasteAttachments: [])
    }

    /// Creates a key event, a paste with more than text among them.
    package init(
        key: Key, ctrl: Bool = false, alt: Bool = false, shift: Bool = false, command: Bool = false,
        phase: Phase = .press, capsLock: Bool = false, numericPad: Bool = false,
        pasteAttachments: [PasteAttachment]
    ) {
        self.key = key
        self.ctrl = ctrl
        self.alt = alt
        self.shift = shift
        self.command = command
        self.phase = phase
        self.capsLock = capsLock
        self.numericPad = numericPad
        self.pasteAttachments = pasteAttachments
    }

    /// Creates a key event from a character.
    public init(character: Character) {
        self.key = .character(character)
        self.ctrl = false
        self.alt = false
        self.shift = character.isUppercase
        self.command = false
        self.phase = .press
        self.capsLock = false
        self.numericPad = false
        self.pasteAttachments = []
    }
}

// MARK: - Phase

extension KeyEvent {
    /// What happened to a key: SwiftUI's `KeyPress.Phases`, as one event has
    /// exactly one of them.
    public enum Phase: Sendable, Hashable {
        /// The key went down. In a terminal's legacy encoding, also each
        /// auto-repeat of a held key, which arrives as another press.
        case press

        /// The key repeated while held. Only from a terminal speaking the kitty
        /// keyboard protocol.
        case `repeat`

        /// The key came up. Only from a terminal speaking the kitty keyboard
        /// protocol; every consumer but a key-press handler that asks for
        /// releases ignores one.
        case release
    }
}

// MARK: - Modifier key state

/// The modifier keys a terminal reported held, and whether Caps Lock was on,
/// when a modifier key went down or came up on its own.
///
/// Only a terminal speaking the kitty keyboard protocol, with its "report all
/// keys as escape codes" enhancement on, reports a modifier key by itself. In
/// a legacy encoding a modifier is only ever a bit on another key's event, so
/// none of these ever arrives there.
public struct ModifierKeyState: Hashable, Sendable {
    /// Whether Shift is held.
    public var shift: Bool
    /// Whether Control is held.
    public var control: Bool
    /// Whether Option (Alt) is held.
    public var option: Bool
    /// Whether Command is held: the protocol's Super modifier, which is what
    /// the macOS terminals that speak the protocol report ⌘ as.
    public var command: Bool
    /// Whether Caps Lock is on.
    public var capsLock: Bool

    /// Creates a modifier key state.
    public init(
        shift: Bool = false, control: Bool = false, option: Bool = false, command: Bool = false,
        capsLock: Bool = false
    ) {
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
        self.capsLock = capsLock
    }
}

// MARK: - Key

/// Represents a keyboard key.
public enum Key: Hashable, Sendable {
    // Special keys
    case escape
    case enter
    case tab
    case backspace
    case delete
    case space

    // Arrow keys
    case up
    case down
    case left
    case right

    // Navigation keys
    case home
    case end
    case pageUp
    case pageDown

    // Function keys
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    /// VT220's extra function keys, the legacy CSI-tilde block 25…34.
    ///
    /// Real keys on DEC and full-size PC keyboards. On a Mac they are also
    /// what Apple Terminal sends for **Shift+F5…Shift+F12**, because it has no
    /// modifier encoding for function keys at all and re-codes the chord as a
    /// different key — see ``KeyEvent/normalizingLegacyShiftedFunctionKeys()`` and
    /// `Documentation/Terminals/Terminal compatibility survey.md`.
    case f13, f14, f15, f16, f17, f18, f19, f20

    /// The PC keyboard's Menu key (also called the Application key), which
    /// opens a context menu on what has the focus, as Shift+F10 does.
    ///
    /// Reported only by a terminal speaking the kitty keyboard protocol, as
    /// its functional key 57363; the legacy encodings send nothing for it
    /// that tells it from another key, so there it never arrives. A Mac's own
    /// keyboard has no such key.
    case menu

    // Character key
    case character(Character)

    /// A bracketed paste: the text the terminal sent between `ESC [ 200 ~`
    /// and `ESC [ 201 ~`, as one event however many reads it took. It arrives
    /// whole however long it is, and nothing in it is read as a key.
    ///
    /// A terminal that stops sending in the middle of a paste for about a
    /// second has it ended there, as one whose end marker was lost: the text
    /// so far arrives as the paste, and what the terminal sends after the
    /// pause is read as typing. Nothing tells a lost marker from a long pause
    /// while it lasts, and without that timeout a lost marker would take the
    /// keyboard for good.
    case paste(String)

    /// Creates a Key from a character if it's a simple character.
    public static func from(_ char: Character) -> Self {
        .character(char)
    }
}

// MARK: - ASCII Byte Constants

/// Named constants for ASCII byte values used in terminal input parsing.
///
/// Replaces raw hex literals (e.g. `0x1B`, `0x0D`) with readable names,
/// making the key parsing logic self-documenting.
private enum ASCIIByte {
    // Control characters
    static let backspace: UInt8 = 0x08
    static let tab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let escape: UInt8 = 0x1B
    static let delete: UInt8 = 0x7F

    // Ctrl+key range (Ctrl+A = 0x01 … Ctrl+Z = 0x1A)
    static let ctrlRangeStart: UInt8 = 0x01
    static let ctrlRangeEnd: UInt8 = 0x1A
    static let ctrlToLowerOffset: UInt8 = 0x60

    // Ctrl-\: the C0 file separator, "^\", the user's quit key's byte
    // unless they moved it.
    static let fileSeparator: UInt8 = 0x1C

    // Ctrl-minus (and Ctrl-_ and Ctrl-/, which most terminals cannot tell
    // from it): the C0 unit separator, "^_".
    static let unitSeparator: UInt8 = 0x1F

    // Printable ASCII range
    static let printableStart: UInt8 = 0x20
    static let printableEnd: UInt8 = 0x7E

    // CSI introducer
    static let openBracket: UInt8 = 0x5B  // '['

    // Arrow / navigation keys (CSI final byte)
    static let arrowUp: UInt8 = 0x41  // 'A'
    static let arrowDown: UInt8 = 0x42  // 'B'
    static let arrowRight: UInt8 = 0x43  // 'C'
    static let arrowLeft: UInt8 = 0x44  // 'D'
    static let home: UInt8 = 0x48  // 'H'
    static let end: UInt8 = 0x46  // 'F'
    static let tilde: UInt8 = 0x7E  // '~' (extended key terminator)
    static let shiftTab: UInt8 = 0x5A  // 'Z' (Shift+Tab / backtab)
}

// MARK: - Key Parsing

extension KeyEvent {
    /// Parses raw terminal input into a KeyEvent.
    ///
    /// Terminal sends escape sequences for special keys:
    /// - Arrow keys: ESC [ A/B/C/D
    /// - Function keys: ESC [ 1~, ESC [ 2~, etc.
    /// - Ctrl+key: ASCII 1-26
    ///
    /// Reads the VT220 F13…F20 keys as Shift+F5…Shift+F12 instead.
    ///
    /// Apple Terminal has no modifier encoding for function keys: rather than
    /// the `ESC[21;2~` form every other terminal uses, its shipped key map
    /// re-codes **Shift+Fn** (n = 5…12) as the *F(n+8)* sequence, so Shift+F10
    /// arrives as `ESC[32~` — byte-identical to a real F18.
    ///
    /// The collision cannot be resolved from the bytes, so this picks the
    /// reading that is reachable on a Mac keyboard: F13…F20 are keys most Macs
    /// do not have, and Shift+F10 is one anybody can press. Deliberately does
    /// NOT do the same for Apple Terminal's Option aliasing (Opt+Fn → F(n+5)),
    /// which overlaps the *plain* F6…F12 that people press all the time.
    ///
    /// Pure, so it can be tested without a terminal; the host gate lives at the
    /// input edge in `Terminal.finalize`.
    public func normalizingLegacyShiftedFunctionKeys() -> KeyEvent {
        let base: Key
        switch key {
        case .f13: base = .f5
        case .f14: base = .f6
        case .f15: base = .f7
        case .f16: base = .f8
        case .f17: base = .f9
        case .f18: base = .f10
        case .f19: base = .f11
        case .f20: base = .f12
        default: return self
        }
        return KeyEvent(key: base, ctrl: ctrl, alt: alt, shift: true)
    }

    /// The key a legacy encoding delivers for this Control chord, or `nil`
    /// for any other event.
    ///
    /// A legacy encoding sends Ctrl plus a letter as the C0 control byte, and
    /// some of those bytes are other keys' too: Ctrl-H is Backspace's 0x08,
    /// Ctrl-I is Tab, Ctrl-M is Return's CR, and Ctrl-[ is Escape. Under the
    /// kitty keyboard protocol the chords arrive as themselves, and this is
    /// what each would have been without it. Ctrl-J is LF, which TUI reads as
    /// the chord on every host (Return is CR in raw mode), and which acted as
    /// Return before it did, so a Ctrl-J nothing takes is Return too. Option
    /// is kept, as the legacy encoding's ESC prefix keeps it; a chord with
    /// Shift is not one of these, its control byte having no case.
    public var legacyControlEquivalent: KeyEvent? {
        guard ctrl, !shift, case .character(let character) = key else { return nil }
        let legacy: Key
        switch character {
        case "h": legacy = .backspace
        case "i": legacy = .tab
        case "j", "m": legacy = .enter
        case "[": legacy = .escape
        default: return nil
        }
        return KeyEvent(
            key: legacy, alt: alt, phase: phase, capsLock: capsLock, numericPad: numericPad)
    }

    /// - Parameter bytes: The raw input bytes.
    /// - Returns: The parsed key event, or nil if incomplete.
    public static func parse(_ bytes: [UInt8]) -> KeyEvent? {
        guard !bytes.isEmpty else { return nil }

        // Single byte
        if bytes.count == 1 {
            return parseSingleByte(bytes[0])
        }

        // Escape sequence
        if bytes[0] == ASCIIByte.escape {
            return parseEscapeSequence(bytes)
        }

        // UTF-8 character
        if let string = String(bytes: bytes, encoding: .utf8),
            let char = string.first
        {
            return KeyEvent(character: char)
        }

        return nil
    }

    /// Parses a single byte into a key event.
    private static func parseSingleByte(_ byte: UInt8) -> KeyEvent? {
        switch byte {
        case ASCIIByte.escape:
            return KeyEvent(key: .escape)
        case ASCIIByte.carriageReturn:
            return KeyEvent(key: .enter)
        case ASCIIByte.lineFeed:
            // Ctrl-J. Return sends CR in raw mode on every host, and LF only
            // where the cooked line discipline turned it into one, which raw
            // mode does not; so LF is the chord, which a vertical field binds
            // to a newline (owner ruling B63-CTRLJ, 2026-10-26). A Ctrl-J
            // nothing takes goes round again as Return
            // (``legacyControlEquivalent``), so where nothing binds it, it is
            // the Return it always read as. Automation that means Return
            // sends CR.
            return KeyEvent(key: .character("j"), ctrl: true)
        case ASCIIByte.tab:
            return KeyEvent(key: .tab)
        case ASCIIByte.delete, ASCIIByte.backspace:
            return KeyEvent(key: .backspace)
        case 0x20:  // Space
            return KeyEvent(key: .space)
        case ASCIIByte.ctrlRangeStart...ASCIIByte.ctrlRangeEnd:
            let char = Character(UnicodeScalar(byte + ASCIIByte.ctrlToLowerOffset))
            return KeyEvent(key: .character(char), ctrl: true)
        case ASCIIByte.fileSeparator:
            // 0x1C, "^\", is Ctrl-\: the user's quit key, which the terminal
            // driver turns into SIGQUIT while TUI's raw mode leaves it live,
            // so it arrives as a byte only where the driver lets it — the
            // user turned the quit key off or moved it, or the app binds a
            // chord it could be and the run loop's line discipline (in
            // TUIApp) masked the driver's quit. Some
            // terminals send it for Ctrl-4 and Ctrl-| as well; Ctrl-\ is the
            // canonical reading, as Backspace is 0x08's, and the input chain
            // tries the others after it.
            return KeyEvent(key: .character("\\"), ctrl: true)
        case ASCIIByte.unitSeparator:
            // 0x1F, "^_", is what most terminals send for Ctrl-minus, and for
            // Ctrl-_ and Ctrl-/ as well: the legacy encodings cannot tell the
            // three apart. Read as Ctrl-minus, the key TUI binds undo to
            // (the one zsh and Emacs bind to it too); see
            // Documentation/Terminals/Terminal compatibility survey.md, "Undo and redo".
            return KeyEvent(key: .character("-"), ctrl: true)
        case (ASCIIByte.printableStart + 1)...ASCIIByte.printableEnd:  // Skip space (0x20), handled above
            let char = Character(UnicodeScalar(byte))
            return KeyEvent(character: char)
        default:
            return nil
        }
    }

    /// Parses an escape sequence into a key event.
    private static func parseEscapeSequence(_ bytes: [UInt8]) -> KeyEvent? {
        guard bytes.count >= 2 else {
            // Just ESC alone
            return KeyEvent(key: .escape)
        }

        // Meta-prefixed sequence ("option as meta key"): ESC + a full escape
        // sequence — e.g. Option-Shift-Tab arrives as ESC ESC [ Z. Parse the
        // inner sequence and mark alt.
        if bytes[1] == 0x1B {
            if bytes.count > 2, let inner = parseEscapeSequence(Array(bytes.dropFirst())) {
                return KeyEvent(
                    key: inner.key, ctrl: inner.ctrl, alt: true, shift: inner.shift,
                    numericPad: inner.numericPad)
            }
            return KeyEvent(key: .escape, alt: true)
        }

        // CSI sequences: ESC [
        if bytes[1] == ASCIIByte.openBracket {
            return parseCSISequence(Array(bytes.dropFirst(2)))
        }

        // SS3 sequences: ESC O, then any parameters, then the key's byte.
        if bytes[1] == 0x4F && bytes.count >= 3 {  // 'O'
            return parseSS3Sequence(bytes[2...])
        }

        // Alt+key: ESC followed by key
        if bytes.count == 2 {
            if let keyEvent = parseSingleByte(bytes[1]) {
                return KeyEvent(key: keyEvent.key, ctrl: keyEvent.ctrl, alt: true, shift: keyEvent.shift)
            }
        }

        // Alt + a multi-byte UTF-8 character: a meta-sending terminal
        // prefixes whatever the keyboard produced, ASCII or not (Option+ß on
        // a German layout arrives as ESC + the two bytes of ß).
        if bytes.count > 2,
            let string = String(bytes: bytes.dropFirst(), encoding: .utf8),
            string.count == 1, let character = string.first
        {
            return KeyEvent(key: .character(character), alt: true)
        }

        return KeyEvent(key: .escape)
    }

    /// Parses an SS3 (Single Shift 3) key: what follows `ESC O`.
    ///
    /// SS3 is how a terminal sends a key in its APPLICATION modes, which a
    /// program turns on and which outlive it: DECCKM (`CSI ? 1 h`) for the
    /// cursor keys, DECKPAM (`ESC =`) for the keypad. A killed `vim`, `less` or
    /// `htop`, or a shell that sends terminfo's `smkx` without its `rmkx`,
    /// leaves them on; TUI turns both off at startup
    /// (`Terminal.inheritedDefaults`), and reads these spellings anyway, for a
    /// terminal or multiplexer that sends them regardless. Read only, they
    /// lost every arrow key. The table is xterm's (ctlseqs, "PC-Style
    /// Function Keys" and the VT220 keypad):
    ///
    /// - `A` `B` `C` `D`: the arrows; `H` `F`: Home and End. Not on the
    ///   keypad: in cursor-key mode the main arrows send these.
    /// - `P` `Q` `R` `S`: F1 to F4 (PF1 to PF4), in every mode.
    /// - The keypad, carrying ``numericPad`` as the kitty keyboard protocol's
    ///   keypad keys do: `p`…`y` the digits, `j` `k` `l` `m` `n` `o` the
    ///   operators `* + , - . /`, `X` its `=`, `M` its Enter, `I` its Tab and
    ///   a space its Space.
    /// - `E`, the keypad's Begin (its 5 with Num Lock off), is consumed as a
    ///   key this framework has no `Key` for.
    ///
    /// A modifier rides between the `O` and the key's byte where a terminal
    /// sends one, as the CSI forms carry it: `ESC O 2 P` (xterm's older
    /// spelling) or `ESC O 1 ; 2 P` is Shift-F1. Only those two shapes
    /// (``SS3Modifier``): anything else between them is not a key.
    private static func parseSS3Sequence(_ body: ArraySlice<UInt8>) -> KeyEvent? {
        guard let final = body.last else { return nil }
        let modifiers: (shift: Bool, alt: Bool, ctrl: Bool)
        switch SS3Modifier(body.dropLast()) {
        case .none: modifiers = (false, false, false)
        case .code(let code): modifiers = decodeModifierCode(code)
        case .partial, .invalid: return nil
        }
        // 'E', the keypad's Begin, and anything else: a key with no `Key`.
        guard let (key, numericPad) = ss3Keys[final] else { return nil }
        return KeyEvent(
            key: key, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift,
            numericPad: numericPad)
    }

    /// Whether `byte`, after `ESC O` and any modifier, ends an SS3 key: one
    /// of ``ss3Keys``, or `E`, the keypad's Begin, consumed as a key with no
    /// `Key`. The input extractor asks, so that `ESC O` and a byte that ends
    /// none is read as Alt-Shift-O and typing, not dropped as a key no one
    /// sends.
    package static func endsSS3Key(_ byte: UInt8) -> Bool {
        ss3Keys[byte] != nil || byte == 0x45
    }

    /// The key each SS3 byte stands for, and whether it is on the keypad: see
    /// ``parseSS3Sequence(_:)``.
    private static let ss3Keys: [UInt8: (key: Key, numericPad: Bool)] = {
        var keys: [UInt8: (key: Key, numericPad: Bool)] = [
            ASCIIByte.arrowUp: (.up, false), ASCIIByte.arrowDown: (.down, false),
            ASCIIByte.arrowRight: (.right, false), ASCIIByte.arrowLeft: (.left, false),
            ASCIIByte.home: (.home, false), ASCIIByte.end: (.end, false),
            0x50: (.f1, false), 0x51: (.f2, false), 0x52: (.f3, false), 0x53: (.f4, false),  // P Q R S
            0x4D: (.enter, true), 0x49: (.tab, true), 0x20: (.space, true),  // M I space
            0x58: (.character("="), true),  // X
        ]
        // 'j'…'y': the keypad's * + , - . / and then its digits.
        for (offset, character) in "*+,-./0123456789".enumerated() {
            keys[0x6A + UInt8(offset)] = (.character(character), true)
        }
        return keys
    }()

    /// Parses a CSI (Control Sequence Introducer) sequence.
    ///
    /// CSI format: `ESC [ <params> <final-byte>`.
    /// The final byte identifies the key (e.g. `A` = up arrow).
    /// Numeric parameters before the final byte encode extended keys
    /// like Page Up/Down (`ESC [ 5 ~`).
    ///
    /// Modifier keys are encoded as `ESC [ 1 ; <modifier> <key>`:
    /// - 2 = Shift
    /// - 3 = Alt
    /// - 4 = Shift+Alt
    /// - 5 = Ctrl
    /// - 6 = Shift+Ctrl
    /// - 7 = Alt+Ctrl
    /// - 8 = Shift+Alt+Ctrl
    private static func parseCSISequence(_ params: [UInt8]) -> KeyEvent? {
        guard !params.isEmpty else { return nil }

        // Extract modifier from params if present (format: "1;2A" for Shift+Up)
        let modifiers = extractModifiers(from: params)

        // The last byte is the CSI function identifier
        switch params.last {
        case ASCIIByte.arrowUp:
            return KeyEvent(key: .up, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowDown:
            return KeyEvent(key: .down, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowRight:
            return KeyEvent(key: .right, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowLeft:
            return KeyEvent(key: .left, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.home:
            return KeyEvent(key: .home, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.end:
            return KeyEvent(key: .end, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.tilde:
            return parseExtendedKey(params, modifiers: modifiers)
        case ASCIIByte.shiftTab:
            // Shift+Tab: ESC [ Z (CSI Z / backtab)
            return KeyEvent(key: .tab, shift: true)
        case .some(0x50...0x53):  // 'P' 'Q' 'R' 'S'
            return parseModifiedFunctionKey(params, modifiers: modifiers)
        default:
            return nil
        }
    }

    /// F1 to F4 with a modifier, as xterm sends them: `CSI 1 ; m P` to
    /// `CSI 1 ; m S`, so Shift-F3 is `CSI 1;2 R`. Unmodified they come as SS3
    /// (`ESC O P`…, ``parseSS3Sequence(_:)``). Only that shape: the first
    /// parameter 1 and a modifier code from 1 to 16.
    ///
    /// `CSI 1;m R` is also a cursor-position report's shape, for row 1 and
    /// column m. It is read as F3 because TUI asks for no cursor report: its
    /// startup exchanges have been fenced by the status report, `CSI 5 n`,
    /// since 2026-10-05, for exactly this collision
    /// (`Documentation/Terminals/Terminal compatibility survey.md`, "Asking the terminal —
    /// Device Attributes"). Anything that sends `CSI 6 n` again has to take
    /// F3 out of here first, or its report arrives as a keystroke;
    /// `CursorReportRequestScanTests` fails if any code under `Sources/`
    /// spells the request.
    private static func parseModifiedFunctionKey(
        _ params: [UInt8], modifiers: (shift: Bool, alt: Bool, ctrl: Bool)
    ) -> KeyEvent? {
        let fields = params.dropLast().split(separator: 0x3B, omittingEmptySubsequences: false)
        guard fields.count == 2, ASCIIDecimal.value(of: fields[0]) == 1,
            let code = ASCIIDecimal.value(of: fields[1]), (1...16).contains(code)
        else { return nil }
        let keys: [Key] = [.f1, .f2, .f3, .f4]
        guard let final = params.last, (0x50...0x53).contains(final) else { return nil }
        return KeyEvent(
            key: keys[Int(final - 0x50)], ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
    }

    /// Extracts modifier flags from CSI parameters.
    ///
    /// Format: `1;2` where 2 is the modifier code.
    /// Modifier codes (xterm standard):
    /// - 2 = Shift
    /// - 3 = Alt
    /// - 4 = Shift+Alt
    /// - 5 = Ctrl
    /// - 6 = Shift+Ctrl
    /// - 7 = Alt+Ctrl
    /// - 8 = Shift+Alt+Ctrl
    /// - 9 = Meta — and 10…16, Meta combined with the three above
    ///
    /// The code is `1 +` a bitfield, and xterm's fourth bit is **Meta**, a
    /// modifier this framework does not have. It is not a fourth key on a Mac
    /// keyboard: it is what a terminal configured to "use Option as Meta"
    /// reports Option AS, so ⌥→ arrives as `ESC[1;9C` rather than `ESC[1;3C`.
    /// Folding Meta onto `alt` is therefore not an approximation, it is the
    /// same key by its other name — and it is what the ESC-prefixed spelling of
    /// the very same convention (`ESC ESC [ C`, see ``parseEscapeSequence``)
    /// has always decoded to. Without it a ⌥-chord silently arrived as the
    /// bare key, which reads as the modifier being ignored rather than
    /// undelivered.
    private static func extractModifiers(from params: [UInt8]) -> (shift: Bool, alt: Bool, ctrl: Bool) {
        // Look for semicolon separator
        guard let semicolonIndex = params.firstIndex(of: 0x3B) else {  // ';' = 0x3B
            return (shift: false, alt: false, ctrl: false)
        }

        // Extract modifier number after semicolon (before final byte). When
        // the `;` IS the last byte — `ESC [ ;`, a truncated or malformed
        // sequence — the range below would be inverted, and an inverted
        // `Range` traps. Nothing follows the separator, so there is no
        // modifier to read.
        guard semicolonIndex < params.count - 1 else {
            return (shift: false, alt: false, ctrl: false)
        }
        let modifierBytes = params[(semicolonIndex + 1)..<(params.count - 1)]
        // `ASCIIDecimal`, not `Int(_: String)`, which accepts a SIGN — so
        // `ESC [ 1 ; -9223372036854775808 A` parsed, and `modifier - 1` below
        // overflowed and trapped, killing the app from inside the key parser
        // with the terminal still in raw mode. The bytes come from anything
        // that can write to the tty.
        guard let modifier = ASCIIDecimal.value(of: modifierBytes) else {
            return (shift: false, alt: false, ctrl: false)
        }
        return decodeModifierCode(modifier)
    }

    /// The modifiers an xterm modifier code stands for: the code is `1 +` a
    /// bitfield, see ``extractModifiers(from:)``.
    private static func decodeModifierCode(_ modifier: Int) -> (shift: Bool, alt: Bool, ctrl: Bool) {
        // Decode modifier bits (modifier - 1 gives the bit flags)
        // Bit 0 = Shift, Bit 1 = Alt, Bit 2 = Ctrl, Bit 3 = Meta (read as Alt)
        let bits = modifier - 1
        let shift = (bits & 1) != 0
        let alt = (bits & 2) != 0 || (bits & 8) != 0
        let ctrl = (bits & 4) != 0

        return (shift: shift, alt: alt, ctrl: ctrl)
    }

    // The complexity is the VT-key switch itself; splitting it into
    // per-group helpers fragments the table without simplifying. The
    // suppression is in block form so the doc comment stays adjacent to
    // the function (the `:next` form would orphan it).
    // swiftlint:disable cyclomatic_complexity
    /// Parses extended key sequences (`ESC [ n ~` or `ESC [ n ; m ~`).
    ///
    /// These are VT-style sequences where `n` is a numeric key identifier:
    /// - 1=Home, 2=Insert, 3=Delete, 4=End, 5=PageUp, 6=PageDown
    /// - 11-15=F1-F5, 17-21=F6-F10, 23-24=F11-F12, 25-34=F13-F20
    ///
    /// The gaps are historical: 16, 22, 27 and 30 were never assigned.
    ///
    /// With modifiers: `ESC [ 3 ; 2 ~` = Shift+Delete
    private static func parseExtendedKey(
        _ params: [UInt8],
        modifiers: (shift: Bool, alt: Bool, ctrl: Bool) = (false, false, false)
    ) -> KeyEvent? {
        // Extract the numeric identifier before the '~' terminator or ';'
        let numberBytes: ArraySlice<UInt8>
        if let semicolonIndex = params.firstIndex(of: 0x3B) {
            numberBytes = params[..<semicolonIndex]
        } else {
            numberBytes = params.dropLast()
        }

        // `ASCIIDecimal`, the reader `extractModifiers` uses above and for the
        // same reason: `Int(_: String)` accepts a SIGN. Here it cannot trap —
        // nothing is computed from `number`, and `-3` falls to `default` — but
        // a LEADING `+` read as the bare digits, so `ESC [ + 3 ~` arrived as a
        // Delete keypress: a character gone from a focused TextField, a row
        // gone from a List with `.onDelete`. No terminal signs a key number;
        // like every other malformed shape, it is dropped.
        guard let number = ASCIIDecimal.value(of: numberBytes) else {
            return nil
        }

        let shift = modifiers.shift
        let alt = modifiers.alt
        let ctrl = modifiers.ctrl

        switch number {
        // Navigation keys
        case 1: return KeyEvent(key: .home, ctrl: ctrl, alt: alt, shift: shift)
        case 2: return nil  // Insert - not commonly used in TUI apps
        case 3: return KeyEvent(key: .delete, ctrl: ctrl, alt: alt, shift: shift)
        case 4: return KeyEvent(key: .end, ctrl: ctrl, alt: alt, shift: shift)
        case 5: return KeyEvent(key: .pageUp, ctrl: ctrl, alt: alt, shift: shift)
        case 6: return KeyEvent(key: .pageDown, ctrl: ctrl, alt: alt, shift: shift)

        // Function keys (VT-style)
        case 11: return KeyEvent(key: .f1, ctrl: ctrl, alt: alt, shift: shift)
        case 12: return KeyEvent(key: .f2, ctrl: ctrl, alt: alt, shift: shift)
        case 13: return KeyEvent(key: .f3, ctrl: ctrl, alt: alt, shift: shift)
        case 14: return KeyEvent(key: .f4, ctrl: ctrl, alt: alt, shift: shift)
        case 15: return KeyEvent(key: .f5, ctrl: ctrl, alt: alt, shift: shift)
        case 17: return KeyEvent(key: .f6, ctrl: ctrl, alt: alt, shift: shift)
        case 18: return KeyEvent(key: .f7, ctrl: ctrl, alt: alt, shift: shift)
        case 19: return KeyEvent(key: .f8, ctrl: ctrl, alt: alt, shift: shift)
        case 20: return KeyEvent(key: .f9, ctrl: ctrl, alt: alt, shift: shift)
        case 21: return KeyEvent(key: .f10, ctrl: ctrl, alt: alt, shift: shift)
        case 23: return KeyEvent(key: .f11, ctrl: ctrl, alt: alt, shift: shift)
        case 24: return KeyEvent(key: .f12, ctrl: ctrl, alt: alt, shift: shift)

        // VT220 F13–F20. Modifiers still apply where a terminal sends them:
        // `ESC[32;2~` means Shift+F18, distinct from the bare `ESC[32~` that
        // Apple Terminal uses to mean Shift+F10.
        case 25: return KeyEvent(key: .f13, ctrl: ctrl, alt: alt, shift: shift)
        case 26: return KeyEvent(key: .f14, ctrl: ctrl, alt: alt, shift: shift)
        case 28: return KeyEvent(key: .f15, ctrl: ctrl, alt: alt, shift: shift)
        case 29: return KeyEvent(key: .f16, ctrl: ctrl, alt: alt, shift: shift)
        case 31: return KeyEvent(key: .f17, ctrl: ctrl, alt: alt, shift: shift)
        case 32: return KeyEvent(key: .f18, ctrl: ctrl, alt: alt, shift: shift)
        case 33: return KeyEvent(key: .f19, ctrl: ctrl, alt: alt, shift: shift)
        case 34: return KeyEvent(key: .f20, ctrl: ctrl, alt: alt, shift: shift)

        default: return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity
}

// MARK: - What a paste carries beside its text

/// One of the clipboard's types handed over with a paste: its MIME type and
/// its bytes — `image/png` and a picture's file, say.
package struct PasteAttachment: Equatable, Sendable {
    /// The MIME type, as the terminal named it.
    package let type: String
    /// The bytes.
    package let bytes: [UInt8]

    package init(type: String, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }
}
