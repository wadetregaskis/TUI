//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarItemPlacement.swift
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
/// | ``keyboard`` | bottom bar, leading — while a text input inside the view that declared it has the focus |
/// | ``accessoryBar(id:)`` | an accessory bar: a row of the top bar under its items, one for each identifier |
///
/// ``status`` takes iOS's reading, the bottom bar, where macOS centres it in
/// the window toolbar: the bottom bar is where a terminal app's status lives.
/// ``principal`` takes iOS's reading too, the title's place, where macOS
/// centres it in the toolbar and says nothing of the title — as the A28
/// design study decided (§3.2, §3.6).
///
/// In presented content the window's bars are inert. A sheet or a full-screen
/// cover hosts its toolbar's items at its own edges, wherever in its content
/// they are declared; a popover's `.toolbar` draws them round the view it is
/// attached to. Either way, the modal actions and the bottom bar's placements
/// (``keyboard`` among them) are in a button row below (``destructiveAction``
/// leading, ``cancellationAction`` then ``confirmationAction`` trailing, the
/// confirmation button the default button and the cancellation one the cancel
/// button), every other placement in a row above.
public struct ToolbarItemPlacement: Sendable, Equatable {
    /// The roles a placement can have.
    package enum Role: Sendable, Equatable {
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
        case keyboard
        case accessoryBar(AccessoryBarID)
    }

    /// This placement's role.
    package let role: Role

    /// The system places the item automatically, depending on many factors
    /// including the platform, size class, or presence of other items: in a
    /// terminal, the top bar's trailing end.
    public static let automatic = Self(role: .automatic)

    /// The system places the item in the principal item section: the centre of
    /// the top bar, in place of the title — or beside it, under
    /// `.toolbarRole(.editor)`.
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

    /// The item is placed in the keyboard section: the bottom bar's leading
    /// end, while a text input — a `TextField`, a `SecureField`, a
    /// `TextEditor` — inside the view that declared it has the focus.
    ///
    /// SwiftUI puts these items above iOS's software keyboard, or in a Mac's
    /// Touch Bar. A terminal has neither, so they go where a person typing
    /// looks for the keys: beside the line of key hints, for as long as the
    /// typing lasts. Like any change to a bar's rows, the bar that appears or
    /// goes for them does so a frame later.
    public static let keyboard = Self(role: .keyboard)

    /// Creates a unique accessory bar placement — mirrors SwiftUI's
    /// `ToolbarItemPlacement.accessoryBar(id:)`.
    ///
    /// Each identifier is an accessory bar of its own: a row of the window's
    /// top bar under its items, in the order the page first places something
    /// in each. Its items are laid out along it as the top bar's are, from the
    /// trailing end. `ToolbarPlacement.accessoryBar(id:)` with the same
    /// identifier names the bar to `.toolbarVisibility(_:for:)` and
    /// `.toolbarBackground(_:for:)`.
    ///
    /// ```swift
    /// extension ToolbarItemPlacement {
    ///     static let favoritesBar = accessoryBar(id: "com.example.favorites")
    /// }
    /// ```
    ///
    /// - Parameter id: A unique identifier for this placement.
    public static func accessoryBar<ID: Hashable>(id: ID) -> Self {
        Self(role: .accessoryBar(AccessoryBarID(id)))
    }

    /// The window bar an item of this placement joins.
    package var bar: WindowChromeState.Edge {
        switch role {
        case .status, .bottomBar, .keyboard: .bottom
        default: .top
        }
    }

    /// The accessory bar an item of this placement is in, or `nil` for one in
    /// the top bar's own row or the bottom bar.
    package var accessoryBar: AccessoryBarID? {
        if case .accessoryBar(let id) = role { id } else { nil }
    }

    /// Where in its bar the item sits.
    package var region: Region {
        switch role {
        case .navigation, .topBarLeading, .keyboard: .leading
        case .principal: .principal
        case .secondaryAction: .secondary
        default: .trailing
        }
    }

    /// The regions of a bar, in the order they are laid out.
    package enum Region {
        case leading, principal, secondary, trailing
    }
}

// MARK: - Accessory Bars

/// The identifier of one of the window's accessory bars:
/// ``ToolbarItemPlacement/accessoryBar(id:)``'s, and the bar placement's of
/// the same name.
///
/// `@unchecked Sendable` because `AnyHashable` is not: the identifiers an app
/// names its bars with are values — a string, an enumeration case — which
/// SwiftUI's own placements, themselves `Sendable`, carry the same way.
package struct AccessoryBarID: Hashable, @unchecked Sendable {
    /// The identifier the app gave.
    let id: AnyHashable

    package init(_ id: some Hashable) {
        self.id = AnyHashable(id)
    }
}

// MARK: - Value Hash

/// Read by a `switch`, as `TrackStyle` is: since `accessoryBar(id:)` the role is
/// a payload enum, which the value hash cannot read as bytes, and every view
/// holding a placement — a `ToolbarItemGroup`, so any `.toolbar { … }` of views
/// — would go unhashed, and unmemoised, with every container around it. See
/// `_ValueHashing`.
extension ToolbarItemPlacement.Role: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .automatic: plans.mixCase(0, (), into: &hash)
        case .principal: plans.mixCase(1, (), into: &hash)
        case .navigation: plans.mixCase(2, (), into: &hash)
        case .primaryAction: plans.mixCase(3, (), into: &hash)
        case .secondaryAction: plans.mixCase(4, (), into: &hash)
        case .status: plans.mixCase(5, (), into: &hash)
        case .confirmationAction: plans.mixCase(6, (), into: &hash)
        case .cancellationAction: plans.mixCase(7, (), into: &hash)
        case .destructiveAction: plans.mixCase(8, (), into: &hash)
        case .bottomBar: plans.mixCase(9, (), into: &hash)
        case .topBarLeading: plans.mixCase(10, (), into: &hash)
        case .topBarTrailing: plans.mixCase(11, (), into: &hash)
        case .keyboard: plans.mixCase(12, (), into: &hash)
        case .accessoryBar(let id): plans.mixCase(13, id, into: &hash)
        }
    }
}

/// Read by the identifier's hash value. An `AnyHashable`'s box is the standard
/// library's to lay out, and opening it by its plan would read a `String`
/// identifier by its storage, not by its characters; the hash value is what
/// the identifier's `==` agrees with — two identifiers the bars take for one
/// hash the same, `1` and `1 as UInt8` among them.
extension AccessoryBarID: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        plans.mixValue(pointer.assumingMemoryBound(to: Self.self).pointee.id.hashValue, into: &hash)
    }
}
