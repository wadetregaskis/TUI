//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Two controls whose stored properties left padding — bytes the per-pass
/// memos' value hash read undefined then, and skips now — declared so their
/// common shapes have none, and are smaller (and plain words to the hash) for it. A generic field can still leave a gap
/// for other type arguments, which the value hash itself must skip.
@MainActor
@Suite("Toggle and ProgressView leave no bytes undefined in their common shapes")
struct ControlLayoutPaddingTests {
    /// 195 since `Toggle(configuration)` (2026-10-03): its one-byte proxy flags
    /// go last, after the binding, so they add a byte and no padding. 197 since
    /// `Transaction.scrollTargetAnchor` (the same day): the binding's
    /// transaction carries the anchor in two bytes, and its switches share one.
    /// 198 since `Text.textScale` (2026-10-04): a `Text` is 56 bytes, ending
    /// on a word, so the disabled flag moved from before the binding to after it.
    /// 206 since custom transaction values (2026-10-03): the binding's
    /// transaction leads with a reference to them, a word it adds without
    /// padding. 214 since `Animation.logicallyComplete(after:)` (the same
    /// day): the transaction's animation carries the completion time, a word.
    @Test("A Toggle titled with a string: no padding, 208 → 214 bytes")
    func toggle() {
        typealias Titled = Toggle<Text>
        #expect(interiorPadding(of: Titled.self).isEmpty, "\(interiorPadding(of: Titled.self))")
        #expect(MemoryLayout<Titled>.size == 214)
    }

    @Test("A ProgressView with no labels: no padding, 97 → 90 → 106 bytes")
    func progressView() {
        typealias Bare = ProgressView<EmptyView, EmptyView>
        #expect(interiorPadding(of: Bare.self).isEmpty, "\(interiorPadding(of: Bare.self))")
        #expect(MemoryLayout<Bare>.size == 106)
    }
}
