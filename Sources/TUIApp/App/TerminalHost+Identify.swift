//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalHost+Identify.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIChrome
import TUIFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

/// The app's startup asks the terminal what it is (``AppRunner``, before the
/// render loop is built). In the app layer, beside that one caller, because the exchange
/// needs the console ``Terminal`` and seeding the answer writes the process
/// environment: both the app layer's. What the exchange records
/// (``TerminalHost/startupIdentity``) and the verdict on its answers
/// (``TerminalHost/nameFromDeviceAttributes(_:)``) stay with the host
/// detection that reads them.
extension TerminalHost {
    /// Runs the identity exchange, records it, and seeds whatever it named.
    ///
    /// The one entry point, so that the recording and the seeding cannot drift
    /// apart: a diagnostic that reported a different host from the one actually
    /// being compensated for would be worse than no diagnostic.
    ///
    /// - Parameter terminal: the terminal to ask — it owns stdin, the termios
    ///   state the replies depend on, and the input buffer any stray keystrokes
    ///   have to be handed back to.
    /// - Returns: the name discovered, or `nil`.
    @MainActor @discardableResult
    static func identify(using terminal: Terminal) -> String? {
        let (identity, name) = terminal.queryIdentity()
        startupIdentity = identity
        if let name { seedDiscoveredHost(name) }
        return name
    }

    /// Records a host discovered at runtime, so every existing reader of
    /// ``isAppleTerminal`` and friends sees it.
    ///
    /// It goes into the process environment — the same place the answer would
    /// have come from had ssh forwarded it — rather than into a new global.
    /// That keeps exactly one source of truth for "which terminal is this",
    /// and means nothing downstream needs to know the answer arrived late.
    ///
    /// - Important: the detectors are `static let`, so each freezes on first
    ///   read. This must therefore run **before** anything reads one, which in
    ///   practice means before the render loop (and its `FrameDiffWriter`) is
    ///   constructed. `Tools/Smoke/identity_smoke.py` is what holds that
    ///   ordering: nothing in the type system can.
    ///
    /// - Parameter name: a `TERM_PROGRAM`-style name, as
    ///   ``nameFromDeviceAttributes(_:)`` returns.
    static func seedDiscoveredHost(_ name: String) {
        #if os(Windows)
            _ = unsafe _putenv_s("TUI_TERM_PROGRAM", name)
        #else
            unsafe setenv("TUI_TERM_PROGRAM", name, 1)
        #endif
    }
}
