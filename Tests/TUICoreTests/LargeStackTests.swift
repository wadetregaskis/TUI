//  🖥️ TUI — A Terminal UI framework for Swift
//  LargeStackTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

#if os(Windows)
    import WinSDK
#endif

@testable import TUICore

/// A walk runs on a stack of at least ``LargeStack/bytes`` wherever the thread's
/// own is smaller: on Windows, a fiber's.
@MainActor
@Suite("A walk's large stack")
struct LargeStackTests {

    /// The bytes the stack the caller is on spans, as the stack guard reads it,
    /// or `nil` where it reads none.
    private func stackBytes() -> UInt? {
        let stackPointer = StackGuard.currentStackPointer()
        guard let extent = StackGuard.currentThreadExtent(stackPointer: stackPointer) else { return nil }
        return extent.high - extent.low
    }

    @Test("It hands back what the body returns")
    func returnsTheBody() {
        #expect(LargeStack.run { 6 * 7 } == 42)
        #expect(LargeStack.run { "a" + "b" } == "ab")
    }

    @Test("The body runs on a stack of at least the large size, and the caller's is its own again after")
    func bodyHasTheLargeStack() throws {
        let outside = try #require(stackBytes(), "no bounds here")
        let inside = try #require(LargeStack.run { stackBytes() }, "no bounds inside")
        let after = try #require(stackBytes())
        #expect(after == outside)
        #if os(Windows)
            // A test thread on Windows has 1 MiB, so this is the fiber's.
            #expect(outside < UInt(LargeStack.bytes), "the test thread has \(outside) bytes")
            #expect(inside >= UInt(LargeStack.bytes), "\(inside) bytes")
        #else
            // Elsewhere the body runs where it is.
            #expect(inside == outside)
        #endif
    }

    @Test("Asked again inside, it stays on the stack it is on")
    func nests() {
        let (outer, inner, value) = LargeStack.run {
            let outer = StackGuard.currentStackPointer()
            let (inner, value) = LargeStack.run { (StackGuard.currentStackPointer(), 7) }
            return (outer, inner, value)
        }
        #expect(value == 7)
        // The inner body ran deeper on the same stack, not on another.
        #expect(inner < outer && outer - inner < 64 * 1024, "outer \(outer), inner \(inner)")
    }

    @Test("The next walk finds the same large stack")
    func reuses() {
        let first = LargeStack.run { StackGuard.currentStackPointer() }
        let second = LargeStack.run { StackGuard.currentStackPointer() }
        // The same stack, entered from the same depth, at nearly the same place.
        let distance = first > second ? first - second : second - first
        #expect(distance < 4096, "first \(first), second \(second)")
    }

    #if os(Windows)
        @Test("A thread's large stack is let go when the thread ends")
        func releasedWithItsThread() throws {
            let seen = Seen()
            // A thread of 1 MiB, as an app's main thread is, so its walk is on
            // the fiber.
            let opaque = unsafe Unmanaged.passRetained(seen).toOpaque()
            let bits = unsafe UInt(
                bitPattern: CreateThread(nil, 1 << 20, Self.walkOnce, opaque, DWORD(STACK_SIZE_PARAM_IS_A_RESERVATION), nil))
            try #require(bits != 0, "no thread")
            _ = unsafe WaitForSingleObject(HANDLE(bitPattern: bits), INFINITE)
            _ = unsafe CloseHandle(HANDLE(bitPattern: bits))
            unsafe Unmanaged<Seen>.fromOpaque(opaque).release()
            let base = try #require(seen.allocationBase, "the walk saw no stack of its own")
            // Its reservation is gone, or another allocation now begins there.
            let after = Self.allocation(containing: base)
            #expect(after.state == DWORD(MEM_FREE) || after.base != base, "still reserved: \(after)")
        }

        /// What the thread's walk saw: the reservation its stack was in.
        private final class Seen: @unchecked Sendable {
            var allocationBase: UInt?
        }

        /// The thread: one walk, which notes the reservation it ran in, as a
        /// large one, then the thread ends.
        nonisolated private static let walkOnce: LPTHREAD_START_ROUTINE = { parameter in
            guard let parameter = unsafe parameter else { return 1 }
            let seen = unsafe Unmanaged<Seen>.fromOpaque(parameter).takeUnretainedValue()
            seen.allocationBase = LargeStack.run {
                let here = StackGuard.currentStackPointer()
                let allocation = allocation(containing: here)
                return allocation.size >= UInt(LargeStack.bytes) ? allocation.base : nil
            }
            return 0
        }

        /// The reservation `address` is in: where it begins, how much of it
        /// lies from there on, and its state.
        nonisolated private static func allocation(containing address: UInt) -> (base: UInt, size: UInt, state: DWORD) {
            let first = region(at: address)
            // The reservation's extent: each of its regions in turn.
            var size: UInt = 0
            var next = first.base
            while first.base != 0 {
                let part = region(at: next)
                guard part.base == first.base, part.size > 0 else { break }
                size += part.size
                next += part.size
            }
            return (first.base, size, first.state)
        }

        /// The region of pages `address` is in: its reservation's start, the
        /// region's bytes from `address` on, and its state.
        nonisolated private static func region(at address: UInt) -> (base: UInt, size: UInt, state: DWORD) {
            var info = unsafe MEMORY_BASIC_INFORMATION()
            let found = unsafe VirtualQuery(
                UnsafeRawPointer(bitPattern: address), &info, SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size))
            guard found != 0 else { return (0, 0, DWORD(MEM_FREE)) }
            let base = unsafe UInt(bitPattern: info.AllocationBase)
            let size = unsafe UInt(info.RegionSize)
            let state = unsafe info.State
            return (base, size, state)
        }
    #endif
}
