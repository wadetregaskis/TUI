//  🖥️ TUI — A Terminal UI framework for Swift
//  ChildViewsMemoAddressTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What a closure in a stack's content holds: freed with the content.
@MainActor
private final class Witness {
    let label: String

    init(_ label: String) {
        self.label = label
    }
}

/// A row's data. Not `Equatable`, so its row is not memoised by its element
/// (`_MemoizedRow`), which a closure's captures do not reach.
private struct Cell: Identifiable {
    let id: Int

    /// Sixteen: a `ForEach` of fewer has its children resolved afresh each
    /// time, as not worth a memo entry (`childViewsAreWorthMemoising`).
    static let sixteen = (0..<16).map(Self.init)
}

/// A stack's children are resolved once a pass, keyed by the content value's
/// hash, which reads the addresses the value holds: a `ForEach`'s array buffer
/// and closure context among them. An address names a value only while that
/// value lives, so the memo keeps the content it resolved alive with the
/// children. Without that, a content value freed during the pass could hand
/// its addresses to the next one built at the same identity, which was then
/// served the first one's children: a grouped `Form` builds its column for its
/// measure and again for its render, each a `ForEach` over a fresh array, and
/// now and then drew its sections at their ideal width (Stress
/// `app-shapes/grouped-form`, a frame or two in sixty differing between two
/// runs of one binary).
@MainActor
@Suite("A stack's children are not served to another content value at a freed address")
struct ChildViewsMemoAddressTests {
    /// The render loop's shape: an isolated cache and the volatile-read tracker
    /// whose presence turns the pass's memos on.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 80, height: 24)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }

    /// Each stack is built inside the loop and released at the end of its
    /// iteration, so the next asks the allocator for an array buffer and a
    /// closure context of the same sizes the instant after the last gave its
    /// own back. Those two addresses are all that tells the stacks' values
    /// apart.
    @Test("Stacks built one after another at one identity draw their own rows")
    func recycledAddressesDoNotAlias() {
        let context = memoisedContext()
        var drawn: [Int] = []
        for round in 0..<64 {
            let width = 4 + round % 2 * 8
            // A fresh buffer each round (`Array(Cell.sixteen)` would share
            // the static's).
            let cells = (0..<16).map(Cell.init)
            let stack = VStack(alignment: .leading, spacing: 0) {
                ForEach(cells) { _ in Text(String(repeating: "x", count: width)) }
            }
            let lines = renderToBuffer(stack, context: context).lines.map(\.stripped)
            drawn.append(lines.first?.count { $0 == "x" } ?? 0)
        }

        #expect(drawn == (0..<64).map { 4 + $0 % 2 * 8 })
    }

    /// What rules the aliasing out: the content a stack's children were
    /// resolved from lives as long as they are kept, the pass, so no address
    /// in its key can name anything else meanwhile.
    @Test("The content a stack's children were resolved from lives until the pass ends")
    func resolvedContentLivesForThePass() {
        let context = memoisedContext()
        weak var held: Witness?
        do {
            let witness = Witness("held")
            held = witness
            _ = renderToBuffer(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Cell.sixteen) { _ in Text(witness.label) }
                },
                context: context)
        }
        #expect(held != nil, "kept with the children it resolved to")
        context.renderCache?.beginRenderPass()
        #expect(held == nil, "let go of with them")
    }
}
