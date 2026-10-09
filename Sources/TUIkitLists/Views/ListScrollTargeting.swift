//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListScrollTargeting.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Step unit

/// What one step of a `List` or `Table` moves through, as its scroll target
/// behaviour decides: terminal lines (no behaviour, or ``ScrollGranularity/line``)
/// or whole rows (`.viewAligned`).
///
/// Selection and the keyboard focus cursor are row-based either way; the unit
/// affects only how far one scroll STEP moves (wheel, trackpad, scrollbar
/// arrows) and where the top may come to rest. With single-line rows the two
/// are identical. Neither leaves part of the viewport blank: the row that
/// straddles the bottom edge is drawn as far as it fits under both, so a
/// fixed-height list never appears to truncate its own visible area. The
/// trailing row is not where the promise about whole rows lives — a step lands
/// on one.
enum ScrollStepUnit: Sendable, Equatable {
    /// Scroll by terminal lines; a tall top row may be partially clipped.
    case line

    /// Scroll by whole rows; a step lands with the top row fully visible.
    case row
}

/// How a `List` or `Table` applies the scroll target behaviour in force — what
/// its handler captures each render, for the steps it takes at event time.
struct ListScrollTargeting: Equatable, Sendable {
    /// What one step moves through.
    var unit: ScrollStepUnit = .line

    /// Whether every step is a page (`.paging`).
    var pages = false

    /// The most rows one step may move under `.viewAligned`'s limit, or `nil`
    /// for no limit beyond the step's own.
    var rowLimit: Int?

    /// Whether `.viewAligned`'s limit is a screenful, rather than a count.
    var limitsToScreenful = false

    /// The free default: line steps, no paging, no limit.
    static let free = Self()

    /// The targeting `behavior` asks of a list: `.paging` and `.viewAligned`
    /// are honoured, and a behaviour of the app's own is not consulted, as
    /// SwiftUI's `List` consults none on macOS (measured).
    init(_ behavior: any ScrollTargetBehavior, environment: EnvironmentValues) {
        if behavior is PagingScrollTargetBehavior {
            pages = true
        } else if let aligned = behavior as? ViewAlignedScrollTargetBehavior {
            unit = .row
            switch aligned.limit(compact: environment.verticalSizeClass == .compact) {
            case .views(let count): rowLimit = count
            case .screenful: limitsToScreenful = true
            case nil: break
            }
        }
    }

    init() {}
}
