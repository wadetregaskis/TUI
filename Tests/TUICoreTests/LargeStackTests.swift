//  🖥️ TUI — A Terminal UI framework for Swift
//  LargeStackTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

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
}
