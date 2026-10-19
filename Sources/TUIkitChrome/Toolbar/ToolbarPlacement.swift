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
        case accessory(AccessoryBarID)
    }

    /// The bar this names, as the window's chrome keys it.
    var bar: WindowChromeState.BarKey {
        switch edge {
        case .automatic, .top: .edge(.top)
        case .bottom: .edge(.bottom)
        case .accessory(let id): .accessory(id)
        }
    }

    /// The primary toolbar: in a terminal, the window's top bar.
    public static let automatic = Self(edge: .automatic)

    /// The window's toolbar: the bar above the page.
    public static let windowToolbar = Self(edge: .top)

    /// The bottom toolbar — SwiftUI's iOS spelling, here the bar below the page.
    public static let bottomBar = Self(edge: .bottom)

    /// Creates a unique accessory bar placement — mirrors SwiftUI's
    /// `ToolbarPlacement.accessoryBar(id:)`.
    ///
    /// Names to a bar modifier the accessory bar that
    /// `ToolbarItemPlacement.accessoryBar(id:)` with the same identifier places
    /// items in: `.toolbarVisibility(.hidden, for: .accessoryBar(id: …))` hides
    /// it, `.toolbarBackground(_:for:)` fills it.
    ///
    /// - Parameter id: A unique identifier for this placement.
    public static func accessoryBar<ID: Hashable>(id: ID) -> Self {
        Self(edge: .accessory(AccessoryBarID(id)))
    }
}
