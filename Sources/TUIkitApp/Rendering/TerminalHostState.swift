//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostState.swift
//
//  The ledger of what the app has set on the terminal emulator itself, beyond
//  its screen — the window title, the pointer's shape — and what giving it
//  back takes.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Ledger

/// What the app has set on the terminal emulator beyond the screen, and how to
/// give it back: the window's title, for now (refusal review P15; Ghostty
/// adoption study, C2, "build once, on the ledger" — progress, pointer shapes
/// and attention are to join it).
///
/// The title is the window in front's: its scene's title, or a root
/// `.navigationTitle` no top bar shows (`RenderLoop+HostState.swift`). It is
/// written as `OSC 2`, on a change only. The first time, the terminal's own
/// title is saved first, on its title stack (XTWINOPS 22); when the app has
/// no title to show, on suspend and on exit, it is restored (XTWINOPS 23), so
/// the shell gets its title back. A host without the stack ignores both, and
/// keeps the app's title until the shell's next prompt sets one — which
/// shell integration does on every measured host that has it.
///
/// A value: the run loop owns one (``RenderLoop``), and nothing here writes —
/// each change returns the bytes it takes, for the caller to send with the
/// frame or the hand-back.
///
/// Two lanes built this ledger at once, and both halves are here: the window
/// title (lane O9), kept by the run loop's instance, and the pointer's shape
/// (lane O12, ``pointerShape``), kept by the ``Terminal``'s, which changes the
/// mouse modes that reset it on Ghostty. One owner for every value is queued
/// (HOSTLEDGER); until then each instance uses its own half.
struct TerminalHostState: Equatable {
    /// The pointer's shape (OSC 22), where the terminal takes one by name;
    /// `nil` where it is left alone. The ``Terminal``'s instance keeps it.
    var pointerShape: TerminalHostSetting?

    /// The title the terminal was last given, or `nil` while it shows its own.
    private(set) var writtenTitle: String?

    /// Whether the terminal's own title is saved on its title stack, owed a
    /// restore.
    private(set) var savedHostTitle = false

    /// The title last asked for, as asked — unsanitised — or `.none` since
    /// the last restore: a frame asking for the same is answered with one
    /// comparison, every frame asking.
    private var askedTitle: String??

    /// The bytes that make the terminal show `title`, or give it its own back
    /// for `nil` (``restore()``): nothing where it shows that already. The
    /// title is sanitised (``sanitizedTitle(_:)``), and one that sanitises to
    /// nothing is no title.
    mutating func show(title asked: String?) -> String {
        guard askedTitle != .some(asked) else { return "" }
        defer { askedTitle = .some(asked) }
        let title = asked.map(Self.sanitizedTitle(_:)).flatMap { $0.isEmpty ? nil : $0 }
        guard title != writtenTitle else { return "" }
        guard let title else { return restore() }
        var bytes = ""
        if !savedHostTitle {
            bytes += Self.saveTitle
            savedHostTitle = true
        }
        writtenTitle = title
        return bytes + Self.setTitle(title)
    }

    /// The bytes that give the terminal its own title back — a restore, where
    /// one was saved — and forgets the app's, so the next ``show(title:)``
    /// saves and sets again: for suspend, exit, and a frame with no title.
    mutating func restore() -> String {
        writtenTitle = nil
        askedTitle = .none
        guard savedHostTitle else { return "" }
        savedHostTitle = false
        return Self.restoreTitle
    }

    /// What the terminal is owed should the process die now: the restore,
    /// where a title was saved (`Terminal.signalDebt`).
    var debt: String {
        savedHostTitle ? Self.restoreTitle : ""
    }

    // MARK: The Sequences

    /// `CSI 22 ; 2 t`: push the window title onto the title stack (XTWINOPS).
    static let saveTitle = "\u{1B}[22;2t"

    /// `CSI 23 ; 2 t`: pop the window title from the title stack (XTWINOPS).
    static let restoreTitle = "\u{1B}[23;2t"

    /// `OSC 2 ; title ST`: the window title, in UTF-8, ended by `ESC \`.
    /// `OSC 2` rather than `OSC 0`, which sets the icon name too, as the
    /// Ghostty adoption study recommends (C2).
    static func setTitle(_ title: String) -> String {
        "\u{1B}]2;\(title)\u{1B}\\"
    }

    /// `title`, safe inside an OSC: a line break or a tab is a space, and
    /// every other control character — C0, DEL, C1 — is dropped. A `BEL` or
    /// an `ESC` would end the OSC early, and what followed would be printed
    /// or obeyed; `sanitizedForTerminal` keeps C0, for text drawn on the
    /// screen, so the title has its own.
    static func sanitizedTitle(_ title: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(title.utf8.count)
        for character in title {
            if character.isNewline || character == "\t" {
                sanitized.append(" ")
            } else if !character.unicodeScalars.contains(where: isControl(_:)) {
                sanitized.append(character)
            }
        }
        return sanitized
    }

    /// Whether `scalar` is a C0 control, DEL or a C1 control.
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }
}

// MARK: - One value outside the grid

/// One thing the app sets on the terminal outside its grid of cells: what it
/// wants now, what it last sent, how to put the terminal's own back mid-run,
/// and what is owed as the app leaves.
///
/// The Ghostty study's "one mechanism for state outside the grid" (§1.2): a
/// pointer shape, a window title and a progress bar each need the value the
/// frame wants, the value last sent, a write when they differ, and a reset on
/// suspend, exit and fatal signal, sent again on resume — so each is one of
/// these, held by ``TerminalHostState``, rather than a copy of that logic of
/// its own. Bytes in, bytes out: what a value means, and how a host spells
/// it, is the caller's.
struct TerminalHostSetting: Equatable {
    /// The bytes that put back the terminal's own value while the app runs.
    let unset: String

    /// The bytes that put back the terminal's own value as the app leaves —
    /// a quit, a suspend, the debt a signal pays — once they are owed
    /// (``isOwed``).
    let reset: String

    /// What the terminal was last sent: `.some(nil)` its own value, `nil`
    /// unknown, which the next ``update(to:)`` settles by sending.
    private var sent: String?? = .some(nil)

    /// Whether anything has been sent since the last ``reset`` went out, so
    /// that one is owed.
    ///
    /// Not from the start: the Ghostty study's rule is that a reset joins
    /// the debt a signal pays only once it is measured harmless where nothing
    /// was set, and no host's is yet (`pointer_shape_card.py`). An app that
    /// never sets the value sends the terminal nothing, as it leaves either;
    /// one that set it owes the reset, which beats leaving its value behind.
    private(set) var isOwed = false

    init(unset: String, reset: String) {
        self.unset = unset
        self.reset = reset
    }

    /// The bytes that set `wanted` (`nil`: the terminal's own), or `nil` when
    /// the terminal already shows it. The write is the caller's.
    mutating func update(to wanted: String?) -> String? {
        if case .some(let last) = sent, last == wanted { return nil }
        sent = .some(wanted)
        isOwed = true
        return wanted ?? unset
    }

    /// Forgets what was sent: the terminal may have changed it itself.
    mutating func forgetSent() {
        if case .some(.some) = sent { sent = nil }
    }

    /// Takes note that ``reset`` went out: the terminal shows its own again,
    /// so a resume sends the wanted value afresh, and nothing is owed until
    /// it does.
    mutating func noteReset() {
        sent = .some(nil)
        isOwed = false
    }
}

// MARK: - The values set by name

/// The ledger's values kept as ``TerminalHostSetting``s — the pointer's shape
/// — which the ``Terminal``'s instance holds: the terminal writes each
/// change, owes each reset and pays it as the app leaves, because it is what
/// the bytes go to, what composes the debt a signal pays
/// (`Terminal.signalDebt`), and what changes the mouse modes, which on
/// Ghostty change the pointer's shape themselves.
extension TerminalHostState {
    /// What every value owes as the app leaves, in one string: written before
    /// the input modes go off (`Terminal.inputModesOwed`). Empty until a
    /// value has been sent (``TerminalHostSetting/isOwed``).
    var resets: String {
        guard let pointerShape, pointerShape.isOwed else { return "" }
        return pointerShape.reset
    }

    /// Takes note that ``resets`` went out.
    mutating func noteResets() {
        pointerShape?.noteReset()
    }
}
