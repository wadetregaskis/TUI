//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarPlacement.swift
//
//  Where a toolbar item goes, and which bar a bar modifier names.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Item Placement

/// A structure that defines the placement of a toolbar item — mirrors SwiftUI's
/// `ToolbarItemPlacement`.
///
/// The window has two toolbars: the TOP bar, above the page, and the BOTTOM
/// bar, below it. Each exists while something is placed in it. In a terminal
/// they read as follows:
///
/// | Placement | Where |
/// |---|---|
/// | ``navigation``, ``topBarLeading`` | top bar, leading |
/// | ``principal`` | top bar, centre, in place of the title |
/// | ``automatic``, ``primaryAction``, ``topBarTrailing`` | top bar, trailing |
/// | ``secondaryAction`` | top bar, trailing, before the primary items |
/// | ``confirmationAction``, ``cancellationAction``, ``destructiveAction`` | top bar, trailing (macOS's reading outside a sheet) |
/// | ``bottomBar``, ``status`` | bottom bar |
///
/// ``status`` takes iOS's reading, the bottom bar, where macOS centres it in
/// the window toolbar: the bottom bar is where a terminal app's status lives.
/// ``principal`` takes iOS's reading too, the title's place, where macOS
/// centres it in the toolbar and says nothing of the title — as the A28
/// design study decided (§3.2, §3.6).
///
/// In presented content — a sheet, a full-screen cover, a popover — the
/// window's bars are inert, and a `.toolbar` draws its items itself, round the
/// view it is attached to: the modal actions and the bottom bar's placements
/// in a button row below it (``destructiveAction`` leading,
/// ``cancellationAction`` then ``confirmationAction`` trailing, the
/// confirmation button the default button and the cancellation one the cancel
/// button), every other placement in a row above it.
public struct ToolbarItemPlacement: Sendable, Equatable {
    /// The roles a placement can have.
    enum Role: Sendable, Equatable {
        case automatic
        case principal
        case navigation
        case primaryAction
        case secondaryAction
        case status
        case confirmationAction
        case cancellationAction
        case destructiveAction
        case bottomBar
        case topBarLeading
        case topBarTrailing
    }

    /// This placement's role.
    let role: Role

    /// The system places the item automatically, depending on many factors
    /// including the platform, size class, or presence of other items: in a
    /// terminal, the top bar's trailing end.
    public static let automatic = Self(role: .automatic)

    /// The system places the item in the principal item section: the centre of
    /// the top bar, in place of the title.
    public static let principal = Self(role: .principal)

    /// The item represents a navigation action: the top bar's leading end.
    public static let navigation = Self(role: .navigation)

    /// The item represents a primary action: the top bar's trailing end.
    public static let primaryAction = Self(role: .primaryAction)

    /// The item represents a secondary action: the top bar's trailing end,
    /// before the primary items.
    public static let secondaryAction = Self(role: .secondaryAction)

    /// The item represents a change in status for the current context: the
    /// bottom bar.
    public static let status = Self(role: .status)

    /// The item represents a confirmation action for a modal interface: in a
    /// sheet, the trailing end of its button row, as its default button
    /// (Return); elsewhere, the top bar's trailing end.
    public static let confirmationAction = Self(role: .confirmationAction)

    /// The item represents a cancellation action for a modal interface: in a
    /// sheet, its button row, before the confirmation items, as its cancel
    /// button (Escape, where the sheet's own dismissal does not take it);
    /// elsewhere, the top bar's trailing end.
    public static let cancellationAction = Self(role: .cancellationAction)

    /// The item represents a destructive action for a modal interface: in a
    /// sheet, the leading end of its button row; elsewhere, the top bar's
    /// trailing end.
    public static let destructiveAction = Self(role: .destructiveAction)

    /// Places the item in the bottom bar — SwiftUI's iOS spelling, here the bar
    /// below the page. ``StatusBar``'s line of key hints goes here.
    public static let bottomBar = Self(role: .bottomBar)

    /// Places the item in the leading edge of the top bar — SwiftUI's iOS
    /// spelling of ``navigation``.
    public static let topBarLeading = Self(role: .topBarLeading)

    /// Places the item in the trailing edge of the top bar — SwiftUI's iOS
    /// spelling of ``primaryAction``.
    public static let topBarTrailing = Self(role: .topBarTrailing)

    /// The window bar an item of this placement joins.
    var bar: WindowChromeState.Edge {
        switch role {
        case .status, .bottomBar: .bottom
        default: .top
        }
    }

    /// Where in its bar the item sits.
    var region: Region {
        switch role {
        case .navigation, .topBarLeading: .leading
        case .principal: .principal
        case .secondaryAction: .secondary
        default: .trailing
        }
    }

    /// The regions of a bar, in the order they are laid out.
    enum Region {
        case leading, principal, secondary, trailing
    }
}

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
