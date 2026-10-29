//  🖥️ TUI — A Terminal UI framework for Swift
//  FatalSignalTerminalRestoreTests.swift
//
//  What the signal handler's helpers do, short of a signal: the process's own
//  handlers are never installed by a test (a scripted terminal arms its debt
//  with its transport instead), so these drive the pieces directly.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(WASILibc)

import Foundation
import Testing

@testable import TUIApp

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite("Fatal signals: paying the terminal back")
struct FatalSignalTerminalRestoreTests {

    /// A debt written to a full, non-blocking pipe
    /// that a reader starts draining a little later: one `write` took what
    /// fitted and left the rest — the input modes, the cursor — unpaid.
    @Test("The debt goes out whole through a full non-blocking descriptor that drains in time")
    func debtWaitsForRoom() throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer {
            close(ends[0])
            close(ends[1])
        }
        _ = fcntl(ends[1], F_SETFL, fcntl(ends[1], F_GETFL) | O_NONBLOCK)
        // Full: the next write reports EAGAIN.
        var filler = [UInt8](repeating: 0x2E, count: 4096)
        var filled = 0
        while true {
            let result = write(ends[1], &filler, filler.count)
            if result <= 0 { break }
            filled += result
        }
        let debt = [UInt8]((0..<20_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let reader = ends[0]
        let expected = filled + debt.count
        let drained = DrainedBytes()
        let thread = Thread {
            usleep(100_000)
            var chunk = [UInt8](repeating: 0, count: 65536)
            while drained.count < expected {
                let result = read(reader, &chunk, chunk.count)
                if result <= 0 { break }
                drained.append(chunk[0..<result])
            }
            drained.finish()
        }
        thread.start()
        debt.withUnsafeBufferPointer { buffer in
            FatalSignalTerminalRestore.writeOwed(buffer.baseAddress!, count: buffer.count, to: ends[1])
        }
        drained.waitUntilFinished()
        #expect(drained.count == expected)
        #expect(Array(drained.bytes.suffix(debt.count)) == debt, "every byte of the debt, once, in order")
    }

    /// A descriptor nothing reads: the handler must still return, so the
    /// signal can end the process.
    @Test("A descriptor that never drains is given up on, not waited on for ever")
    func debtGivesUp() throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer {
            close(ends[0])
            close(ends[1])
        }
        _ = fcntl(ends[1], F_SETFL, fcntl(ends[1], F_GETFL) | O_NONBLOCK)
        var filler = [UInt8](repeating: 0x2E, count: 4096)
        while write(ends[1], &filler, filler.count) > 0 {}
        let started = Date()
        filler.withUnsafeBufferPointer { buffer in
            FatalSignalTerminalRestore.writeOwed(buffer.baseAddress!, count: buffer.count, to: ends[1])
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

/// What the draining thread read, handed to the test under a lock.
private final class DrainedBytes: @unchecked Sendable {
    private let condition = NSCondition()
    private var storage: [UInt8] = []
    private var done = false

    var count: Int { condition.withLock { storage.count } }
    var bytes: [UInt8] { condition.withLock { storage } }

    func append(_ chunk: ArraySlice<UInt8>) { condition.withLock { storage += chunk } }

    func finish() {
        condition.withLock {
            done = true
            condition.broadcast()
        }
    }

    func waitUntilFinished() {
        condition.lock()
        defer { condition.unlock() }
        while !done { condition.wait() }
    }
}

#endif
