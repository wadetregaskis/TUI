//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizedStandardNameOrder.swift
//
//  Names in the order Explorer and Finder list them, where Foundation has the
//  comparison but not the comparator.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Compares names as `localizedStandardCompare(_:)` does — "item2" before
/// "item10", case aside — for a panel's name order where Foundation has that
/// comparison but no `String.StandardComparator.localizedStandard` (Windows,
/// Swift 6.3.3, measured 2026-11-20).
struct LocalizedStandardNameOrder: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let result = lhs.localizedStandardCompare(rhs)
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
