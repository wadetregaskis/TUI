//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarPlacement.swift
//
//  Which bar a bar modifier names. Where a toolbar item goes is in
//  `ToolbarItemPlacement.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Bar Placement

/// The placement of a bar a bar modifier refers to — mirrors SwiftUI's
/// `ToolbarPlacement`.
public struct ToolbarPlacement: Equatable {
    /// The bar.
    let edge: Edge

    /// The bars a placement can name.
    enum Edge: Equatable {
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
    public static var automatic: Self { Self(edge: .automatic) }

    /// The window's toolbar: the bar above the page.
    public static var windowToolbar: Self { Self(edge: .top) }

    /// The bottom toolbar — SwiftUI's iOS spelling, here the bar below the page.
    public static var bottomBar: Self { Self(edge: .bottom) }

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

// MARK: - Value Hash

/// Read by a `switch`, as ``ToolbarItemPlacement``'s role is: since
/// `accessoryBar(id:)` the edge is a payload enum, which the value hash cannot
/// read as bytes. See `_ValueHashing`.
extension ToolbarPlacement.Edge: _ValueHashing {
    static func _mixValueHash(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .automatic: plans.mixCase(0, (), into: &hash)
        case .top: plans.mixCase(1, (), into: &hash)
        case .bottom: plans.mixCase(2, (), into: &hash)
        case .accessory(let id): plans.mixCase(3, id, into: &hash)
        }
    }
}
