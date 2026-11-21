//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowsCOM.swift
//
//  COM, for the length of one call on the calling thread: what a Windows API
//  reached through a COM interface needs (WIC's decoders, a shortcut's
//  `IShellLinkW`).
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import WinSDK

/// COM on the calling thread, for the length of one call.
///
/// Each use joins the multithreaded apartment, which the system's COM
/// servers TUI calls (WIC, the shell's shortcuts) work in, and leaves it
/// after, where joining took: a thread already in an apartment of another
/// kind keeps it (`RPC_E_CHANGED_MODE`), and those servers work there too.
/// Nothing is kept past the call, so no thread is left in an apartment it
/// did not ask for.
package enum WindowsCOM {
    /// Runs `body` with COM initialised on this thread.
    package static func withApartment<T>(_ body: () throws -> T) rethrows -> T {
        let initialised = CoInitializeEx(nil, DWORD(COINIT_MULTITHREADED.rawValue))
        defer { if initialised >= 0 { CoUninitialize() } }
        return try body()
    }
}

#endif
