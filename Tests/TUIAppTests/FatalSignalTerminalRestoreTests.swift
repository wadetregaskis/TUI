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

    /// An app that calls `exit()` — from a button's action, say — runs no
    /// teardown and dies of no signal: before the `atexit` handler it left
    /// the shell raw, on the alternate screen, with every mode on. In a child
    /// process, which the handlers and the `atexit` registration belong to.
    @Test("An exit() with a debt owed pays a quit's debt, and once disarmed pays nothing")
    func exitPaysTheQuitDebt() async throws {
        let owed = try #require(
            await #expect(processExitsWith: .exitCode(3), observing: [\.standardOutputContent]) {
                await MainActor.run {
                    FatalSignalTerminalRestore.arm(owing: "<crash>", onQuit: "<quit>", restoring: nil)
                }
                exit(3)
            })
        let paid = (String(bytes: owed.standardOutputContent, encoding: .utf8) ?? "")
        #expect(paid.contains("<quit>"), "the alternate screen left, as a quit leaves it")
        #expect(!paid.contains("<crash>"))

        let disarmed = try #require(
            await #expect(processExitsWith: .exitCode(3), observing: [\.standardOutputContent]) {
                await MainActor.run {
                    FatalSignalTerminalRestore.arm(owing: "<crash>", onQuit: "<quit>", restoring: nil)
                    FatalSignalTerminalRestore.disarm()
                }
                exit(3)
            })
        #expect(!(String(bytes: disarmed.standardOutputContent, encoding: .utf8) ?? "").contains("<quit>"))
    }

    /// The handler is installed with `SA_ONSTACK`, which is only as good as
    /// the thread's alternate stack: without one a stack overflow's
    /// `SIGSEGV` cannot be delivered, and the process dies with the debt
    /// unpaid. On a thread of its own, as a Linux pool thread the main actor
    /// lands on would be.
    @Test("A thread is given an alternate signal stack once, and keeps it")
    func alternateStack() {
        let seen = AlternateStacks()
        let thread = Thread {
            var before = stack_t()
            _ = sigaltstack(nil, &before)
            FatalSignalTerminalRestore.provideAlternateStack()
            var first = stack_t()
            _ = sigaltstack(nil, &first)
            FatalSignalTerminalRestore.provideAlternateStack()
            var second = stack_t()
            _ = sigaltstack(nil, &second)
            seen.record(before: before, first: first, second: second)
        }
        thread.start()
        seen.waitUntilRecorded()
        #expect(seen.enabled, "the thread has one")
        #expect(seen.kept, "and the second call kept it")
        #expect(seen.ownSize == nil || seen.ownSize == FatalSignalTerminalRestore.alternateStackSize)
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

/// What a thread saw of its alternate signal stack, handed to the test under
/// a lock.
private final class AlternateStacks: @unchecked Sendable {
    private let condition = NSCondition()
    private var recorded = false
    private(set) var enabled = false
    private(set) var kept = false
    /// The size of the stack, where this process's function made it; `nil`
    /// where the thread already had one of its own.
    private(set) var ownSize: Int?

    func record(before: stack_t, first: stack_t, second: stack_t) {
        condition.withLock {
            let disabled = Int32(SS_DISABLE)
            enabled = first.ss_flags & disabled == 0
            kept = second.ss_sp == first.ss_sp
            ownSize = before.ss_flags & disabled != 0 ? first.ss_size : nil
            recorded = true
            condition.broadcast()
        }
    }

    func waitUntilRecorded() {
        condition.lock()
        defer { condition.unlock() }
        while !recorded { condition.wait() }
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
