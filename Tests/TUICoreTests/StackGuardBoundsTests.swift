//  🖥️ TUI — A Terminal UI framework for Swift
//  StackGuardBoundsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

// Windows has no arm yet (its port is in progress): there the guard is off,
// and says so by finding no bounds.
#if !os(Windows)
    /// The guard is only as good as the bounds it measures against: where it
    /// finds none it is off, and a tree too deep for the stack is no longer
    /// cut short. On WebAssembly that is worse than a crash: the stack is a
    /// region of linear memory with no guard page below it, so a stack that
    /// runs out writes over the program's data.
    @MainActor
    @Suite("Stack guard: this platform's bounds")
    struct StackGuardBoundsTests {

        @Test("The running stack's bounds are found, and hold the stack pointer")
        func boundsAreFound() throws {
            let stackPointer = StackGuard.currentStackPointer()
            let extent = try #require(
                StackGuard.currentThreadExtent(stackPointer: stackPointer),
                "no bounds found here, so the guard is off")
            #expect(extent.low < stackPointer && stackPointer < extent.high, "\(extent), at \(stackPointer)")
        }

        @Test("The floor leaves this shallow a stack room to go deeper")
        func floorLeavesRoom() throws {
            // A floor at or above the stack pointer would stop every descent:
            // a reserve larger than the stack itself draws a blank page.
            let stackPointer = StackGuard.currentStackPointer()
            let extent = try #require(StackGuard.currentThreadExtent(stackPointer: stackPointer))
            #expect(extent.low < extent.floor && extent.floor < stackPointer, "\(extent), at \(stackPointer)")
            #expect(StackGuard.hasHeadroomUncounted())
        }
    }
#endif

/// WebAssembly's extent, from the linker's bounds: the arithmetic, which runs
/// anywhere, so it is tested on every platform.
@Suite("Stack guard: WebAssembly's extent")
struct StackGuardWASMExtentTests {

    @Test("wasm-ld's default 64 KiB stack keeps a quarter of itself in reserve, not more than the stack")
    func defaultStackKeepsAQuarter() throws {
        let extent = try #require(StackGuard.wasmStackExtent(low: 0x10_0000, high: 0x11_0000))
        #expect(extent == StackGuard.StackExtent(low: 0x10_0000, floor: 0x10_4000, high: 0x11_0000))
    }

    @Test("A stack raised at link time keeps the native reserve")
    func raisedStackKeepsTheNativeReserve() throws {
        // The browser demo's 16 MiB.
        let extent = try #require(StackGuard.wasmStackExtent(low: 0x10_0000, high: 0x110_0000))
        #expect(extent.floor == 0x10_0000 + StackGuard.reserveBytes)
    }

    @Test("No stack, or bounds the wrong way round, find no extent: the guard is off rather than wrong")
    func emptyStackHasNoExtent() {
        #expect(StackGuard.wasmStackExtent(low: 0x10_0000, high: 0x10_0000) == nil)
        #expect(StackGuard.wasmStackExtent(low: 0x11_0000, high: 0x10_0000) == nil)
    }
}
