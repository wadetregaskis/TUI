//  🖥️ TUI — A Terminal UI framework for Swift
//  MeasureMemoAddressTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// How wide a row is: held by reference, so the row's value hash reads its
/// address, and nothing else of it.
@MainActor
private final class RowWidth {
    let columns: Int

    init(_ columns: Int) {
        self.columns = columns
    }
}

/// A row as wide as the object it holds says. Not `Equatable`, so nothing but
/// the value hash tells two of them apart.
private struct WidthHeldRow: View {
    let width: RowWidth

    var body: some View {
        Text(verbatim: String(repeating: "x", count: width.columns))
    }
}

/// The pass's measure memo is keyed by the measured value's hash, which reads
/// the addresses the value holds — a class instance, a closure's context, an
/// array's buffer — and an address names a value only while that value lives.
/// A value measured and then freed during the pass could hand its address
/// straight back to the next one built at the same identity, which then had
/// the first one's key and was served its size. The memo keeps every value it
/// stored a size for alive until the pass ends, so no address in its keys can
/// name anything else meanwhile — what its sibling, the stack-children memo,
/// does too (`ChildViewsMemoAddressTests`).
@MainActor
@Suite("A measure is not served to another value at a freed address")
struct MeasureMemoAddressTests {
    /// The render loop's shape: an isolated cache and the volatile-read tracker
    /// whose presence turns the pass's measure memo on.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 80, height: 24)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }

    /// Each row's width object is made inside the loop and released at the end
    /// of its iteration, so the next asks the allocator for an object of the
    /// same size the instant after the last gave its own back: the allocator
    /// hands the same block straight back (a size class's free list is last in,
    /// first out, on Darwin's and glibc's allocators alike). That address is
    /// all that tells the rows' values apart.
    @Test("Rows measured one after another at one identity get their own widths")
    func recycledAddressesDoNotAlias() {
        let context = memoisedContext()
        let proposal = ProposedViewSize(width: nil, height: nil)
        var measured: [Int] = []
        var reusedAddresses = 0
        var previousAddress: ObjectIdentifier?
        for round in 0..<64 {
            let width = RowWidth(4 + round % 2 * 8)
            if ObjectIdentifier(width) == previousAddress { reusedAddresses += 1 }
            previousAddress = ObjectIdentifier(width)
            measured.append(measureChild(WidthHeldRow(width: width), proposal: proposal, context: context).width)
        }

        #expect(measured == (0..<64).map { 4 + $0 % 2 * 8 })
        // Nothing measured was freed during the pass, so no address came back.
        #expect(reusedAddresses == 0)
    }

    /// What rules the aliasing out: a value the memo holds a size for lives as
    /// long as the size is kept, the pass.
    ///
    /// The plain-body memo is off: it keeps a composite's value across frames
    /// in its own entry, which would hold this one past the pass by itself.
    @Test("A measured value lives until the pass ends")
    func measuredValueLivesForThePass() {
        let context = memoisedContext()
        context.renderCache?.plainMemo.isOn = false
        weak var held: RowWidth?
        do {
            let width = RowWidth(6)
            held = width
            _ = measureChild(
                WidthHeldRow(width: width), proposal: ProposedViewSize(width: nil, height: nil), context: context)
        }
        #expect(held != nil, "kept with the size it measured")
        context.renderCache?.beginRenderPass()
        #expect(held == nil, "let go of with it")
    }
}
