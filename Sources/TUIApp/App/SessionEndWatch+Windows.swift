//  🖥️ TUI — A Terminal UI framework for Swift
//  SessionEndWatch+Windows.swift
//
//  A logoff or a shutdown, told to a Windows app the way the system tells a
//  process with windows: through a hidden window's messages, as the console's
//  handler is never told of either once `user32.dll` is loaded.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import Synchronization
import WinSDK

/// A hidden window whose only work is to hear that the session is ending — a
/// logoff, a shutdown, a restart — and shut the app down in order, as
/// `SIGTERM` does on POSIX (`SignalManager`).
///
/// The console sends `CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT` only to a
/// process without `user32.dll` or `gdi32.dll` loaded (`SetConsoleCtrlHandler`'s
/// documentation), and a TUI app has: the clipboard, the shell's opener and
/// the console font's probe load them (the Example had, 2026-11-18). Such a
/// process is told by `WM_QUERYENDSESSION` and `WM_ENDSESSION`, which the
/// system sends to each top-level window, hidden ones included — not to a
/// message-only window, which gets no broadcast — so this is one, never shown,
/// with a thread of its own to take its messages.
///
/// - `WM_QUERYENDSESSION` is answered yes: a terminal app has nothing to save
///   that its teardown does not.
/// - `WM_ENDSESSION`, where the session is ending, sends the installed
///   manager's shutdown (``SignalManager/routeSessionEnd()``) and waits up to
///   five seconds for the teardown, which ends the process itself: the system
///   may end it any time after the window has answered.
///
/// One window for the process, made the first time a manager is installed and
/// kept for the process's life, as the route it sends through is the
/// process's: with no manager installed, a session's end does nothing here.
enum SessionEndWatch {
    /// The window's handle's bits, once it is made; 0 before, or where it
    /// could not be.
    static var window: UInt { windowBits.load(ordering: .sequentiallyConsistent) }

    private static let windowBits = Atomic<UInt>(0)

    /// Makes the window, on a thread of its own, the first time it is asked.
    static func start() {
        _ = started
    }

    /// The thread, started once.
    private static let started: Void = {
        let thread = Thread { run() }
        thread.name = "TUI session end"
        thread.start()
    }()

    /// The window's thread: makes the window, then takes its messages for
    /// the process's life.
    private static func run() {
        guard unsafe className.withCString(encodedAs: UTF16.self, create) != 0 else { return }
        var message = unsafe MSG()
        while unsafe GetMessageW(&message, nil, 0, 0) {
            _ = unsafe TranslateMessage(&message)
            _ = unsafe DispatchMessageW(&message)
        }
    }

    /// The window's class name, and its title.
    private static let className = "TUISessionEnd"

    /// Registers the window's class, named `name`, and makes the window, which
    /// is never shown: its handle's bits, or 0.
    private static func create(_ name: UnsafePointer<UInt16>) -> UInt {
        var windowClass = unsafe WNDCLASSEXW()
        unsafe windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        unsafe windowClass.lpfnWndProc = procedure
        unsafe windowClass.hInstance = GetModuleHandleW(nil)
        unsafe windowClass.lpszClassName = name
        _ = unsafe RegisterClassExW(&windowClass)
        let handle = unsafe CreateWindowExW(0, name, name, 0, 0, 0, 0, 0, nil, nil, GetModuleHandleW(nil), nil)
        let bits = UInt(bitPattern: handle)
        windowBits.store(bits, ordering: .sequentiallyConsistent)
        return bits
    }

    /// The window's procedure: the two messages above, and the system's own
    /// handling of the rest.
    private static let procedure: WNDPROC = { window, message, wParam, lParam in
        switch Int32(message) {
        case WM_QUERYENDSESSION:
            return 1
        case WM_ENDSESSION:
            // `wParam` is whether the session is ending: false where another
            // program refused it.
            if wParam != 0, SignalManager.routeSessionEnd() { Sleep(5_000) }
            return 0
        default:
            return unsafe DefWindowProcW(window, message, wParam, lParam)
        }
    }
}

#endif
