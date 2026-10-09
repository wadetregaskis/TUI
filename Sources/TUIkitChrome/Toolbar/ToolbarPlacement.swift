//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarPlacement.swift
//
//  Which bar a bar modifier names. Where a toolbar item goes is in
//  `ToolbarItemPlacement.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Bar Placement

/// The placement of a bar a bar modifier refers to — mirrors SwiftUI's
/// `ToolbarPlacement`.
public struct ToolbarPlacement: Sendable, Equatable {
    /// The bar.
    let edge: Edge

    /// The bars a placement can name.
    enum Edge: Sendable, Equatable {
        case automatic
        case top
        case bottom
    }

    /// The primary toolbar: in a terminal, the window's top bar.
    public static let automatic = Self(edge: .automatic)

    /// The window's toolbar: the bar above the page.
    public static let windowToolbar = Self(edge: .top)

    /// The bottom toolbar — SwiftUI's iOS spelling, here the bar below the page.
    public static let bottomBar = Self(edge: .bottom)
}
