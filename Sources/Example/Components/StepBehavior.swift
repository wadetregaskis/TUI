//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StepBehavior.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// A scroll target behaviour that leaves every step where it lands — the
/// line-by-line scrolling a scrollable does with no behaviour at all, as a
/// value a toggle can choose against `.viewAligned`.
///
/// `Equatable`, so a memo below the scrollable can tell two of them apart from
/// a change (an environment value that cannot be compared turns the memos off).
struct LineSteps: ScrollTargetBehavior, Equatable {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {}
}

extension View {
    /// Scrolls a line at a time when `byLine`, and a whole row at a time —
    /// `.viewAligned` — when not: the two behaviours the List and Table pages'
    /// "Scroll by line" toggles compare.
    func scrollsByLine(_ byLine: Bool) -> some View {
        scrollTargetBehavior(
            byLine ? AnyScrollTargetBehavior(LineSteps()) : AnyScrollTargetBehavior(.viewAligned))
    }
}
