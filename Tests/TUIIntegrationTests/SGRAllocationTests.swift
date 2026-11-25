//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRAllocationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITestProcess

@testable import TUICore

/// The walks that read SGR escapes allocate nothing per escape.
///
/// `SGRState.apply` runs once per escape in the row collapse, the cell diff,
/// the overlay split and the painters: 2,565 escapes in one 120×40 frame. It
/// built a parameter array for each (CORE1-10, WRITER-10), and a `String` and
/// a split for each colon-form parameter, which TUI itself writes for an
/// underline's shape and colour. Each is counted here in this test's task alone,
/// the smallest of a few tries, so a stray allocation in the runtime cannot
/// fail it and a per-escape one cannot pass.
@Suite("SGR walks: allocations", .enabled(if: AllocationCount.isAvailable))
struct SGRAllocationTests {

    /// The fewest allocations `work` made in five tries.
    private func fewest(_ work: () -> Void) -> Int {
        work()  // anything lazily set up the first time is not the walk's
        return (0..<5).map { _ in AllocationCount.during(work) }.min() ?? -1
    }

    @Test(
        "apply allocates nothing",
        arguments: [
            "\u{1B}[38;2;1;2;3;48;2;4;5;6m",  // 24-bit foreground and background
            "\u{1B}[0;1;4:3;58:2::10:20:30;38;5;196m",  // a collapsed run with TUI's own colon forms
            "\u{1B}[22;39;49;59m",
        ])
    func applyAllocatesNothing(sequence: String) {
        var state = SGRState()
        let count = fewest {
            // Not `for _ in 0..<100`: unspecialised, as a debug build leaves
            // it, a range's iterator allocates a coroutine frame per step.
            var applied = 0
            while applied < 100 {
                state.apply(sequence)
                applied += 1
            }
        }
        #expect(count == 0, "\(count) allocations for 100 applies of \(sequence.debugDescription)")
    }
}
