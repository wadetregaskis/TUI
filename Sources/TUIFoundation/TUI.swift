//  🖥️ TUI — A Terminal UI framework for Swift
//  TUI.swift
//
//  Created by LAYERED.work
//  License: MIT
//  TUI enables creating terminal applications with a declarative,
//  SwiftUI-like syntax - without ncurses or other low-level libraries.
//

import Foundation

/// True iff `TUI_DEBUG_FOCUS=1` was set in the environment at
/// process start.
///
/// Read once at module-load time; flipping the variable mid-run has
/// no effect. Used to gate the focus / mouse-dispatch / text-field
/// diagnostic logging across the framework. The cached boolean
/// means each call site costs a single branch in the hot path.
internal let isFocusDebugEnabled: Bool =
    ProcessInfo.processInfo.environment["TUI_DEBUG_FOCUS"] == "1"

/// Appends a one-line, timestamped diagnostic to the focus log when
/// `TUI_DEBUG_FOCUS=1`: the file `TUI_DIAGNOSTICS_FILE` names, else
/// ``focusDebugLogPath``.
///
/// When the flag is unset (the common case) the `message`
/// autoclosure is not evaluated and the function returns
/// immediately, so leaving call sites in place permanently is
/// effectively free.
///
/// Used to diagnose issues that only reproduce in the running
/// example app — typically "the click reached the dispatcher but no
/// region matched", "the keypress dispatched but to the wrong focus
/// handler", or "the binding wrote, but to the wrong @State".
///
/// > Note: Internal diagnostic helper, not part of the public API.
package func debugFocusLog(_ message: @autoclosure () -> String) {
    guard isFocusDebugEnabled else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    DiagnosticChannel.emit("[\(stamp)] \(message())\n", to: DiagnosticChannel.destination ?? focusDebugLogPath)
}

/// Where the focus log goes when `TUI_DIAGNOSTICS_FILE` names no file:
/// `tui-debug-<user>.log` in the temporary directory.
///
/// Never stderr, where every other diagnostic goes by default: the focus log
/// writes a line per key and click, which would land on the screen the app
/// draws. And not a fixed `/tmp/tui-debug.log`, as it once was, which on a
/// machine several people use is one file they all write and can read: the
/// temporary directory is the user's own on macOS (`$TMPDIR`), and the
/// user's name keeps two apart where it is shared, as `/tmp` is on Linux.
package let focusDebugLogPath: String =
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tui-debug-\(NSUserName()).log").path

/// The current version of TUI.
///
/// Read from `Sources/TUIStrings/VERSION` (bundled as a resource).
/// Update the `VERSION` file to change the version number.
public let tuiVersion: String = readTUIVersion(from: .current)

/// The version the `VERSION` file in `resources` names, trimmed; `"unknown"`
/// where it cannot be read.
package func readTUIVersion(from resources: ModuleResources) -> String {
    guard let url = resources.url(named: "VERSION", extension: nil),
        let content = try? String(contentsOf: url, encoding: .utf8)
    else {
        return "unknown"
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}
