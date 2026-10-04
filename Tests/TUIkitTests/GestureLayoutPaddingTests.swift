//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// The attachment behind `gesture(_:)` and `onTapGesture`, declared so its
/// commonest shape — a tap on a `Text` — has no padding, and so is hashed by
/// the per-pass memos as one dense run of words rather than run by run.
@MainActor
@Suite("A tap's attachment leaves no bytes undefined in its common shape")
struct GestureLayoutPaddingTests {
    /// What `Text(…).onTapGesture { … }` is.
    private typealias TextTap = GestureAttachment<Text, _EndedGesture<TapGesture>>

    @Test("A Text's tap: no padding, 88 → 85 bytes, one dense run")
    func textTap() {
        #expect(interiorPadding(of: TextTap.self).isEmpty, "\(interiorPadding(of: TextTap.self))")
        #expect(MemoryLayout<TextTap>.size == 85)
        let plans = ValueHashPlans()
        #expect(plans.plan(for: TextTap.self).pointee.shape == .dense)
    }
}
