//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUINumericControls
@testable import TUITestSupport
@testable import TUIView

/// Three controls whose stored properties left padding — bytes the per-pass
/// memos' value hash read undefined then, and skips now — declared so their
/// common shapes have none, and are smaller (and plain words to the hash) for it. A generic field can still leave a gap
/// for other type arguments, which the value hash itself must skip.
@MainActor
@Suite("Toggle, ProgressView and Button leave no bytes undefined in their common shapes")
struct ControlLayoutPaddingTests {
    /// 195 since `Toggle(configuration)` (2026-10-03): its one-byte proxy flags
    /// go last, after the binding, so they add a byte and no padding. 197 since
    /// `Transaction.scrollTargetAnchor` (the same day): the binding's
    /// transaction carries the anchor in two bytes, and its switches share one.
    /// 198 since `Text.textScale` (2026-10-04): a `Text` is 56 bytes, ending
    /// on a word, so the disabled flag moved from before the binding to after it.
    /// 206 since custom transaction values (2026-10-03): the binding's
    /// transaction leads with a reference to them, a word it adds without
    /// padding. (`Animation.logicallyComplete(after:)` the same day costs
    /// nothing: its 4-byte time sits in the gap after the animation's curve.)
    /// 214 since a text's lines carry a pattern and a colour (W11b,
    /// 2026-10-18): a `Text` is 64 bytes, eight more. 222 since a `Text` keeps
    /// the key it was read from (one word more, lane PARITYMISC, the same day).
    @Test("A Toggle titled with a string: no padding, 208 → 206 → 214 → 222 bytes")
    func toggle() {
        typealias Titled = Toggle<Text>
        #expect(interiorPadding(of: Titled.self).isEmpty, "\(interiorPadding(of: Titled.self))")
        #expect(MemoryLayout<Titled>.size == 222)
    }

    @Test("A ProgressView with no labels: no padding, 97 → 90 → 106 bytes")
    func progressView() {
        typealias Bare = ProgressView<EmptyView, EmptyView>
        #expect(interiorPadding(of: Bare.self).isEmpty, "\(interiorPadding(of: Bare.self))")
        #expect(MemoryLayout<Bare>.size == 106)
    }

    /// 144 when a menu trigger's opener was a struct of two closures
    /// (2026-10-06): its optional four words, after seven bytes of padding
    /// behind the disabled flag, and a typed step in every button's measure
    /// hash. Now a reference, ahead of the flag: one word, which a plain
    /// button's `nil` writes whole, so the hash reads it as plain bytes. (106
    /// when it was a `Bool` beside the flag, before the opener was kept.)
    @Test("A Button and its core: no padding, 144 → 113 bytes, and its menu opener hashed as bytes")
    func button() {
        func check<T>(_: T) {
            #expect(interiorPadding(of: T.self).isEmpty, "\(T.self): \(interiorPadding(of: T.self))")
            #expect(MemoryLayout<T>.size == 113, "\(T.self)")
            // The plan's runs and steps are the table's memory: it has to
            // outlive the reads, which a `let` alone does not promise.
            let plans = ValueHashPlans()
            withExtendedLifetime(plans) {
                let plan = plans.plan(for: T.self).pointee
                // A plan that bypasses has no steps at all, so the next check
                // alone would pass for a button its memo no longer hashes.
                #expect(plan.shape != .bypass, "\(T.self) bypasses: \(plan.bypassReason ?? "")")
                let steps = plan.stepDescriptions
                #expect(!steps.contains { $0.contains("OpenedPopup") }, "\(T.self): \(steps)")
            }
        }
        let button = Button("x") {}
        check(button)
        // `_ButtonCore`, which is what the memo measures: private, so reached
        // through the body that builds it.
        check(button.body)
    }
}
