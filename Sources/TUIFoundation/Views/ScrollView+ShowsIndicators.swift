//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollView+ShowsIndicators.swift
//
//  `ScrollView.showsIndicators`: what `false` does to the indicator
//  visibility this one view reads, and how its content gets the visibility
//  from above back.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The indicator visibilities a scroll view with `showsIndicators = false`
/// found above it, kept for its content.
struct IndicatorVisibilitiesAbove: Equatable {
    let vertical: ScrollIndicatorVisibility
    let horizontal: ScrollIndicatorVisibility
}

private struct IndicatorsAboveShowsIndicatorsKey: EnvironmentKey {
    static let defaultValue: IndicatorVisibilitiesAbove? = nil
}

extension EnvironmentValues {
    /// What ``_ScrollViewCore/hidingAutomaticIndicators(_:)`` replaced, for the
    /// content's context to put back; `nil` everywhere else.
    fileprivate var indicatorsAboveShowsIndicators: IndicatorVisibilitiesAbove? {
        get { self[IndicatorsAboveShowsIndicatorsKey.self] }
        set { self[IndicatorsAboveShowsIndicatorsKey.self] = newValue }
    }

    /// Puts back the visibilities a `showsIndicators = false` scroll view
    /// replaced for itself, so its content reads what was stated above it.
    mutating func restoreIndicatorsAboveShowsIndicators() {
        guard let above = indicatorsAboveShowsIndicators else { return }
        verticalScrollIndicatorVisibility = above.vertical
        horizontalScrollIndicatorVisibility = above.horizontal
        indicatorsAboveShowsIndicators = nil
    }
}

extension _ScrollViewCore {
    /// `context` as this view reads it: under ``ScrollView/showsIndicators``
    /// `false`, an ``ScrollIndicatorVisibility/automatic`` visibility on either
    /// axis reads as ``ScrollIndicatorVisibility/hidden``, while a stated one
    /// stands. That is SwiftUI's precedence (measured 2026-10-18, macOS 15):
    /// `.scrollIndicators(.visible)` around such a view shows its scroller,
    /// `.automatic` does not.
    ///
    /// What it replaced is kept in the environment, and ``contentContext(_:)``
    /// puts it back, since the property is this view's: a scroll view in the
    /// content shows its own indicators (measured likewise).
    ///
    /// Asked again with what it returned — the copy that draws content
    /// margins is asked with it — it finds nothing `.automatic` and returns
    /// it as it is, keeping what the first ask kept.
    func hidingAutomaticIndicators(_ context: RenderContext) -> RenderContext {
        guard hidesAutomaticIndicators else { return context }
        let vertical = context.environment.verticalScrollIndicatorVisibility
        let horizontal = context.environment.horizontalScrollIndicatorVisibility
        guard vertical == .automatic || horizontal == .automatic else { return context }
        var hidden = context
        hidden.environment.indicatorsAboveShowsIndicators = IndicatorVisibilitiesAbove(
            vertical: vertical, horizontal: horizontal)
        if vertical == .automatic { hidden.environment.verticalScrollIndicatorVisibility = .hidden }
        if horizontal == .automatic { hidden.environment.horizontalScrollIndicatorVisibility = .hidden }
        return hidden
    }
}
