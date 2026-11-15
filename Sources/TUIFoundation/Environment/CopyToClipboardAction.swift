//  🖥️ TUI — A Terminal UI framework for Swift
//  CopyToClipboardAction.swift
//
//  The clipboard as an app's own command writes it: an action in the
//  environment, as `openURL` is.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Copy To Clipboard Action

/// An action that puts text on the clipboard, for a command of the app's own:
/// a menu's Copy Path, a button that copies a result.
///
/// Read it from the environment with `@Environment(\.copyToClipboard)` and
/// call it like a function:
///
/// ```swift
/// struct CopyPathCommands: Commands {
///     @Environment(\.copyToClipboard) private var copyToClipboard
///     @FocusedValue(\.selectedPath) private var path
///
///     var body: some Commands {
///         CommandMenu("Node") {
///             Button("Copy Path") { if let path { copyToClipboard(path) } }
///                 .disabled(path == nil)
///         }
///     }
/// }
/// ```
///
/// The text goes where every copy in the app goes, as `.copyable`'s ⌃C does:
/// to the terminal's clipboard by OSC 52, which is the clipboard of the
/// machine the user is at, over ssh too; to this machine's clipboard where the
/// terminal is on this machine and does not take OSC 52; and otherwise
/// nowhere. The status bar says which, as it does for a link's Copy Link. The
/// app's own paste chords and `PasteButton`s read it back wherever this
/// machine's clipboard is not the user's.
///
/// TUI-specific: SwiftUI has no such action. A SwiftUI app writes
/// `NSPasteboard.general` or `UIPasteboard.general`, which in a terminal app
/// is the clipboard of the machine the app runs on — the wrong one over ssh —
/// and on Linux does not exist.
///
/// A `TestApp` keeps what was copied, for a test to read as its `clipboard`.
public struct CopyToClipboardAction: Sendable {
    /// The clipboard's write: the one the environment carried where this was
    /// read.
    private let write: @Sendable (_ text: String, _ announcingSuccess: Bool) -> ClipboardWriteResult

    init(clipboard: ClipboardAccess) {
        write = clipboard.put
    }

    /// Puts `text` on the clipboard.
    ///
    /// - Parameter text: The text to copy. Empty text copies nothing.
    public func callAsFunction(_ text: String) {
        // Announced, as Copy Link's is: nothing else on screen says a
        // command's copy happened.
        _ = write(text, true)
    }
}

extension EnvironmentValues {
    /// An action that puts text on the clipboard, for a command of the app's
    /// own (see ``CopyToClipboardAction``).
    ///
    /// TUI-specific: SwiftUI has no such action.
    public var copyToClipboard: CopyToClipboardAction {
        CopyToClipboardAction(clipboard: clipboardAccess)
    }
}
