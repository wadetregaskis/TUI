//  🖥️ TUI — A Terminal UI framework for Swift
//  StderrRedirectRaceTests.swift
//
//  A report written to stderr while an image draw has it pointed at /dev/null.
//  Here rather than beside the redirect's own tests in TUIImageTests: it writes
//  through TUICore's DiagnosticChannel, and a module's test target imports only
//  the modules that module depends on directly.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)

    import Foundation
    import Synchronization
    import Testing

    @testable import TUICore
    @testable import TUIImage

    @Suite("stderr reports during an image draw's redirect")
    struct StderrRedirectRaceTests {
        /// Darwin's `dup2` reserves descriptor 2 while it swaps it, and a write
    /// from another thread in that window fails with `EBADF`, which
    /// `FileHandle.write(_:)` raises: a report written while an image was
    /// drawn ended the process ("Bad file descriptor", `DepthLimit`'s report
    /// in a parallel run). In a process of its own, as the failure ends it.
    @Test("A report to stderr while an image draw has it redirected is written, not a crash")
    func reportDuringASuppression() async {
        await #expect(processExitsWith: .success) {
            let done = Atomic<Bool>(false)
            let redirecting = Thread {
                while !done.load(ordering: .relaxed) {
                    PlatformImageLoader.suppressingStandardError {}
                }
            }
            redirecting.start()
            for _ in 0..<20_000 { DiagnosticChannel.emit("[test] report\n", to: nil) }
            done.store(true, ordering: .relaxed)
        }
    }
    }

#endif
