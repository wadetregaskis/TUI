//  🖥️ TUI — A Terminal UI framework for Swift
//  ExistentialEquality.swift
//
//  Comparing a value against one held as `any Equatable`.
//
//  Split out of `RenderCache.swift`, which is where it was written and where it
//  is no longer about anything: three callers in two modules ask this question
//  and only one of them is a cache.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Equatable {
    /// Compares against a type-erased value, `false` if it is a different type.
    ///
    /// The standard opening move for comparing two `any Equatable`s: open one
    /// existential so `Self` is concrete, then downcast the other to it.
    ///
    /// Package-wide rather than file-private because two more callers ask the
    /// same question of a value they hold as an existential:
    /// `Palette.isSamePalette(as:)` here, and `ThemeModifier.ComparableStyle` in
    /// `TUI`, of a control style.
    package func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

/// A value that is `Equatable` so that what holds it can be, but whose `==` is
/// a real comparison only for some of what it wraps.
///
/// A style chain or a text renderer wraps an existential the app supplies,
/// which need not be `Equatable`, and answers `false` for one that is not:
/// unequal is the safe answer for a value compared by what holds it. It is the
/// wrong answer for the render cache's environment slots
/// (`RenderCache.noteAppliedEnvironment`), which would read it as `.changed` on
/// every pass and clear the subtree below — its buffers and its sizes — on
/// every frame of an app that changed nothing. A wrapper that says here that it
/// cannot compare what it holds is `.incomparable` instead, as a raw value that
/// is not `Equatable` is: the memos below decline to store, and nothing is
/// cleared.
package protocol PartiallyComparable {
    /// Whether `==` can tell this value from another: `false` where it wraps a
    /// value that is not `Equatable`.
    var isComparable: Bool { get }
}
