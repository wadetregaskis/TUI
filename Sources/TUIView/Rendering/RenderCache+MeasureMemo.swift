//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+MeasureMemo.swift
//
//  The per-pass measure memo's public store, which only forwards to the
//  package one beside the table in `RenderCache.swift`.
//
//  Moved out of `RenderCache.swift`, which had reached the file-length
//  ceiling, unchanged.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension RenderCache {
    /// Stores a `measureChild` result for the rest of this pass, and keeps the
    /// value `key` was made from, `value`, alive with it (see
    /// `measuredValues`).
    ///
    /// A natural answer outranks a budget-shaped one for the slot: the shaped
    /// one can only ever serve its own budget back, while the natural one still
    /// serves every budget above its height. (Both are correct; this is about
    /// which is worth keeping.)
    public func storeMeasure(
        key: MeasureKey,
        proposalWidthWasSpecified: Bool,
        proposalHeight: Int?,
        availableHeight: Int,
        size: ViewSize,
        measuring value: Any
    ) {
        storeMeasure(
            key: key, proposalWidthWasSpecified: proposalWidthWasSpecified, proposalHeight: proposalHeight,
            availableHeight: availableHeight, size: size, lease: nil, measuring: value)
    }
}
