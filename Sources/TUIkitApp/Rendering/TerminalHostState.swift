//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostState.swift
//
//  The ledger of what the app has set on the terminal emulator itself, beyond
//  its screen — the window title — and what giving it back takes.
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
struct TerminalHostState: Equatable {
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
