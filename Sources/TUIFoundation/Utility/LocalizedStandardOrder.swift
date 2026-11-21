//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizedStandardOrder.swift
//
//  Strings in the order Finder and Explorer list names, where Foundation has
//  the comparison but not the comparator.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Compares strings as `localizedStandardCompare(_:)` does — "item2" before
/// "item10", case aside — which is what `String.StandardComparator.localizedStandard`
/// does on Apple platforms, for where Foundation has the comparison but not
/// that comparator (Windows, measured with Swift 6.3.3 on 2026-11-20, and the
/// Linux Foundations).
///
/// Foundation there has no `String.StandardComparator` of this order, nor a
/// way to make one: the only ones it has are `.lexical` and its reverse, and
/// decoding one with `.localizedStandard`'s options is refused as "an invalid
/// configuration" (Swift 6.3.3 and 6.4.2 on Windows, 2026-11-20). So this is a
/// `SortComparator` of its own, which a `KeyPathComparator` takes as readily.
package struct LocalizedStandardOrder: SortComparator {
    package var order: SortOrder

    package init(order: SortOrder = .forward) {
        self.order = order
    }

    package func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let result = lhs.localizedStandardCompare(rhs)
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
