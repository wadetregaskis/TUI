//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollGranularity.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollGranularity

/// How finely a scrollable steps: TUIkit's one granularity of its own, beside
/// SwiftUI's scroll target behaviours. (TUI-specific: SwiftUI scrolls by
/// points, so the question doesn't arise there.)
///
/// - ``line``: the viewport moves one terminal *line* at a time — a tall
///   ``List`` or ``Table`` row scrolls into view gradually, and can be
///   partially clipped at the top of the viewport, exactly like a GUI list
///   mid-scroll. This is what every scrollable does with no scroll target
///   behaviour.
///
/// Scrolling by whole rows — the classic TUI behaviour, where the row a step
/// lands on is fully shown at the top — is SwiftUI's
/// `.scrollTargetBehavior(.viewAligned)`, and paging is `.paging`; see
/// ``ScrollTargetBehavior``. `.scrollGranularity(.line)` takes a subtree back
/// to line steps from either, which SwiftUI has no spelling for.
public enum ScrollGranularity: Sendable, Equatable {
    /// Scroll by terminal lines; a tall top row may be partially clipped.
    case line
}

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

// MARK: - View Modifier

extension View {
    /// Scrolls the ``List``, ``Table`` and ``ScrollView`` content in this
    /// subtree a terminal line at a time — TUIkit's default, and a way back to
    /// it beneath a ``View/scrollTargetBehavior(_:)`` stated further out.
    ///
    /// Under line steps a tall row scrolls into view gradually and may be
    /// partially clipped at the top edge. For whole-row steps, use
    /// `.scrollTargetBehavior(.viewAligned)`. Either way the viewport fills
    /// exactly, the row at the bottom edge drawn as far as it fits.
    public func scrollGranularity(_ granularity: ScrollGranularity) -> some View {
        environment(\.scrollTargetBehavior, _FreeScrollTargetBehavior())
    }
}
