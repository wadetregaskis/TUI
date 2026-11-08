//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationPlacement.swift
//
//  Where a notification is drawn: one of six places on the content area's
//  edges, each a channel stacking its own toasts.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Notification Placement

/// Where on the window's content area a notification is drawn: a corner, or
/// the middle of the top or bottom edge.
///
/// Each placement is a channel of its own: it stacks its toasts apart from
/// the others', the newest nearest the edge, so an app can use several at
/// once — progress at the bottom, errors at the top right:
///
/// ```swift
/// NotificationService.current.post("Copying 12 files…", placement: .bottom)
/// NotificationService.current.post("Disk full", style: .error, placement: .topTrailing)
/// ```
///
/// A post that names none goes to the service's
/// ``NotificationService/defaultPlacement``, ``topTrailing`` unless the app
/// sets another. Toasts sit one cell in from a side and one row in from the
/// top or bottom, in the area between the window's bars.
///
/// TUI-specific: SwiftUI has no toast. The names follow SwiftUI's
/// `Alignment`'s.
public enum NotificationPlacement: Hashable, Sendable, CaseIterable {
    /// The top-left corner (top-right in a right-to-left layout is not
    /// modelled: TUI lays out left to right).
    case topLeading
    /// The middle of the top edge.
    case top
    /// The top-right corner: where toasts go unless the app says otherwise.
    case topTrailing
    /// The bottom-left corner.
    case bottomLeading
    /// The middle of the bottom edge.
    case bottom
    /// The bottom-right corner.
    case bottomTrailing
}

extension NotificationPlacement {
    /// Whether the placement is on the top edge, where its newest toast is
    /// drawn first; on the bottom edge it is drawn last.
    var isTop: Bool {
        switch self {
        case .topLeading, .top, .topTrailing: true
        case .bottomLeading, .bottom, .bottomTrailing: false
        }
    }

    /// Where a stack `width` by `height` cells starts in an area
    /// `areaWidth` by `areaHeight`: one cell in from its side, one row in from
    /// its edge, centred for the middle placements; never before the area's
    /// origin.
    func origin(width: Int, height: Int, areaWidth: Int, areaHeight: Int) -> (x: Int, y: Int) {
        let x: Int =
            switch self {
            case .topLeading, .bottomLeading: 1
            case .top, .bottom: (areaWidth - width) / 2
            case .topTrailing, .bottomTrailing: areaWidth - width - 1
            }
        let y: Int = isTop ? 1 : areaHeight - height - 1
        return (max(0, x), max(0, y))
    }
}
