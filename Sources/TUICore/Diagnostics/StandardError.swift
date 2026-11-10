//  🖥️ TUI — A Terminal UI framework for Swift
//  StandardError.swift
//
//  The process's standard error, descriptor 2, written and redirected under
//  one lock, because Darwin's dup2 is not atomic for another thread's write.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

/// Standard error (descriptor 2), for the framework's own writes to it and for
/// whatever points it elsewhere for a while.
///
/// **Why a lock.** On Darwin `dup2(_, 2)` reserves descriptor 2 while it swaps
/// what the descriptor refers to, and a `write` to descriptor 2 from another
/// thread in that window fails with `EBADF`. It is not a rare window: with one
/// thread redirecting and another writing, 73% of 2,000,000 writes failed
/// (macOS 15, 2026-11-10). `FileHandle.write(_:)` raises on a failed write, so a
/// report written while `TUIImage` had stderr pointed at `/dev/null` for a Core
/// Graphics draw ended the process: "-[_NSStdIOFileHandle writeData:]: Bad file
/// descriptor", from `DepthLimit`'s report, in a parallel test run whose image
/// tests were redirecting stderr. Linux's `dup2` is atomic, but the lock costs
/// nothing there either: a write to stderr is a diagnostic, never on a frame's
/// path.
///
/// So a redirect of descriptor 2 holds ``lock`` until it is put back, and every
/// write of the framework's own goes through ``write(_:)``, which takes it.
/// Writes from elsewhere in the process (the Swift runtime, a system library)
/// cannot be made to wait; the redirect is kept short for them.
///
/// Process-wide, as descriptor 2 is: the lock guards the descriptor table, and
/// holds no state an app or a test could tell apart (CLAUDE.md, No Singletons).
package enum StandardError {
    /// Held by whatever points descriptor 2 elsewhere, until it is put back, and
    /// by ``write(_:)``.
    package static let lock = Mutex<Void>(())

    /// Writes `text` to standard error, after any redirect of it has ended.
    package static func write(_ text: String) {
        lock.withLock { _ in FileHandle.standardError.write(Data(text.utf8)) }
    }
}
