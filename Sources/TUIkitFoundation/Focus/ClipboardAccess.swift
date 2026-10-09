//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardAccess.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Clipboard Helpers

/// The clipboard a text field reads and writes.
///
/// In a running app it is the app's ``ClipboardWriter``, which sends each copy
/// where the user will find it — the terminal by OSC 52, or this machine's
/// clipboard when the terminal is on this machine — and says in the status
/// bar when it could not.
///
/// Two closures rather than a direct call, held per handler, so a test can
/// observe what a field *would* have put on the pasteboard without touching
/// the real one. `SecureField` is why: its
/// contract is that nothing is copied at all, and asserting that against the
/// live pasteboard means racing every other test in the process over one
/// shared global — a race that fails in the direction which looks like
/// success, since a test whose sentinel was clobbered skips instead of
/// failing. It also keeps the suite from writing to the developer's
/// pasteboard as a side effect of running.
package struct ClipboardAccess: Sendable {
    /// Puts `text` on the clipboard, and answers what became of it; the flag
    /// is ``write(_:announcingSuccess:)``'s.
    var put: @Sendable (_ text: String, _ announcingSuccess: Bool) -> ClipboardWriteResult

    /// Reads the clipboard, or `nil` when there is nothing to read.
    package var read: @Sendable () -> String?

    /// The values behind the text this app last copied, where the app keeps
    /// them — see ``TypedClipboard``. Filled in by the clipboard commands from
    /// the environment; `nil` copies and pastes text alone.
    var typed: TypedClipboard?

    /// Puts `text` on the clipboard, and answers what became of it.
    ///
    /// - Parameter announcingSuccess: Whether a plain success earns a line in
    ///   the status bar (see ``ClipboardWriter/write(_:announcingSuccess:)``):
    ///   not for a text control's copy, whose success is what was expected.
    @discardableResult
    package func write(_ text: String, announcingSuccess: Bool = false) -> ClipboardWriteResult {
        put(text, announcingSuccess)
    }

    /// The access a running app hands its controls: `writer`'s routes.
    ///
    /// Copies run in event handlers, on the main actor, which is where the
    /// writer's terminal and locality questions are answered.
    init(writer: ClipboardWriter) {
        put = { text, announcing in
            MainActor.assumeIsolated { writer.write(text, announcingSuccess: announcing) }
        }
        read = { MainActor.assumeIsolated { writer.read() } }
        typed = nil
    }

    init(
        put: @escaping @Sendable (_ text: String, _ announcingSuccess: Bool) -> ClipboardWriteResult,
        read: @escaping @Sendable () -> String?, typed: TypedClipboard? = nil
    ) {
        self.put = put
        self.read = read
        self.typed = typed
    }

    /// The clipboard of an environment no context's services reached — a
    /// control a test renders without them: none. A copy reports
    /// ``ClipboardWriteResult/unavailable`` and a paste reads nothing.
    ///
    /// Every render a context drives hands its controls the context's writer
    /// (``EnvironmentValues/applyRuntimeServices(from:)``) — the run loop's,
    /// a headless run's, a snapshot's — and a test that copies hands its
    /// subtree a clipboard of its own. So this is met only where nothing could
    /// be copied to anyway: there is no terminal to send OSC 52 to, and this
    /// machine's clipboard is the app layer's to reach (``ClipboardBackend``),
    /// never a stray render's. Stateless, so it answers from any thread.
    package static let unavailable = Self(
        put: { text, _ in text.isEmpty ? .nothingToCopy : .unavailable },
        read: { nil })
}

private struct ClipboardAccessKey: EnvironmentKey {
    static let defaultValue = ClipboardAccess.unavailable
}

extension EnvironmentValues {
    /// The clipboard the copy, cut and paste commands read and write — the
    /// running app's ``ClipboardWriter``, unless a test hands its subtree
    /// another, for the reason ``ClipboardAccess`` gives. A text field or
    /// editor takes the one in its environment when it is created, and keeps
    /// it.
    package var clipboardAccess: ClipboardAccess {
        get { self[ClipboardAccessKey.self] }
        set { self[ClipboardAccessKey.self] = newValue }
    }
}
