//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemURLOpener.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

#if os(Windows)
    import WinSDK
#endif

/// This machine's URL opener — `open` on macOS, `xdg-open` on Linux, `ShellExecuteW` on Windows — behind
/// the substrate's ``URLOpenerBackend``: what the app's run loop installs into
/// the ``TUIContext`` it creates. Nothing else does, so no other context
/// launches a browser.
///
/// Reached only where ``TerminalURLOpening/isEnabled`` lets
/// ``OpenURLAction`` defer to the system at all; see
/// ``TerminalClient/urlOpeningSupport`` for why that is off by default.
struct SystemURLOpener: URLOpenerBackend {
    /// Hands `url` to the system opener. Tries `open` (macOS) then `xdg-open`
    /// on `PATH` (Linux) — whichever exists — passing the URL as a single argument (no
    /// shell, so nothing in the URL is interpreted). A no-op when neither
    /// opener is present. Returns whether an opener was started.
    ///
    /// The child's input and output are `/dev/null`. Inherited, they would be
    /// the terminal the app is drawing on: `xdg-open`'s "no method available
    /// for opening" (or `open`'s own complaints) would land in the middle of
    /// the frame, at whatever cursor position the renderer was using, with
    /// nothing to repaint over it until the next full redraw; and a terminal
    /// browser `xdg-open` falls back to without a desktop (`lynx`, `w3m`)
    /// would read the person's keys and set the terminal's mode under the
    /// app.
    func open(_ url: URL) -> Bool {
        // Launching anything is a subprocess, which wasip1 has no way to make.
        // Nothing is lost that the user can act on: a `Link` under a host that
        // cannot open URLs shows its destination instead (``LinkDisplay``), and
        // a terminal that supports OSC 8 — including the one in the browser
        // demo — turns the text itself into something clickable, opened by the
        // terminal rather than by us.
        #if canImport(WASILibc)
            return false
        #elseif os(Windows)
            // The shell's own opener, as `open` is macOS's: the user's
            // default program for the URL's scheme, with no console of its own
            // to write into this one. Only a URL with a scheme: without one
            // the shell takes the text for a program and looks for it in the
            // working directory, `PATH` and its App Paths, so a link to `calc`
            // started the calculator, where `open` and `xdg-open` look only for
            // a file of that name.
            guard let target = Self.shellTarget(for: url) else { return false }
            let result = target.withCString(encodedAs: UTF16.self) { target in
                "open".withCString(encodedAs: UTF16.self) { verb in
                    unsafe ShellExecuteW(nil, verb, target, nil, nil, SW_SHOWNORMAL)
                }
            }
            // Greater than 32 on success, by the function's own contract.
            return Int(bitPattern: result) > 32
        #else
        guard
            let opener = Self.opener(
                environment: ProcessInfo.processInfo.environment, exists: FileManager.default.fileExists(atPath:))
        else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: opener)
        process.arguments = [url.absoluteString]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return (try? process.run()) != nil
        #endif
    }

    /// The opener ``open(_:)`` starts on macOS and Linux: macOS's
    /// `/usr/bin/open`, else `xdg-open` found on `PATH`
    /// (``ExecutableSearchPath``), as a shell would find it; `nil` where
    /// neither `exists`. Posed on the environment and the files that exist, so
    /// a test can ask without either.
    static func opener(environment: [String: String], exists: (String) -> Bool) -> String? {
        if exists("/usr/bin/open") { return "/usr/bin/open" }
        return ExecutableSearchPath.find("xdg-open", in: environment, isExecutable: exists)
    }

    /// What the Windows shell is handed for `url`: its text, where it names a
    /// scheme, and `nil` where it does not (``open(_:)``).
    static func shellTarget(for url: URL) -> String? {
        guard let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url.absoluteString
    }
}
