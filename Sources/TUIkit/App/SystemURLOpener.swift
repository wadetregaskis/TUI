//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemURLOpener.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// This machine's URL opener — `open` on macOS, `xdg-open` on Linux — behind
/// the substrate's ``URLOpenerBackend``: what the app's run loop installs into
/// the ``TUIContext`` it creates. Nothing else does, so no other context
/// launches a browser.
///
/// Reached only where ``TerminalURLOpening/isEnabled`` lets
/// ``OpenURLAction`` defer to the system at all; see
/// ``TerminalClient/urlOpeningSupport`` for why that is off by default.
struct SystemURLOpener: URLOpenerBackend {
    /// Hands `url` to the system opener. Tries `open` (macOS) then `xdg-open`
    /// (Linux) — whichever exists — passing the URL as a single argument (no
    /// shell, so nothing in the URL is interpreted). A no-op when neither
    /// opener is present. Returns whether an opener was started.
    ///
    /// The child's output goes to `/dev/null`. It inherits this process's
    /// descriptors otherwise, and stdout/stderr here are the terminal the app
    /// is drawing on: `xdg-open`'s "no method available for opening" (or
    /// `open`'s own complaints) would land in the middle of the frame, at
    /// whatever cursor position the renderer was using, with nothing to
    /// repaint over it until the next full redraw.
    func open(_ url: URL) -> Bool {
        // Launching anything is a subprocess, which wasip1 has no way to make.
        // Nothing is lost that the user can act on: a `Link` under a host that
        // cannot open URLs shows its destination instead (``LinkDisplay``), and
        // a terminal that supports OSC 8 — including the one in the browser
        // demo — turns the text itself into something clickable, opened by the
        // terminal rather than by us.
        #if canImport(WASILibc)
            return false
        #else
        for opener in ["/usr/bin/open", "/usr/bin/xdg-open"]
        where FileManager.default.fileExists(atPath: opener) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: opener)
            process.arguments = [url.absoluteString]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            return (try? process.run()) != nil
        }
        return false
        #endif
    }
}
