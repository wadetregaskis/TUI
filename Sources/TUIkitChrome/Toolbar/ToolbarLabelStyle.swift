//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarLabelStyle.swift
//
//  How the window's bars draw the labels of their items: the window's label
//  style, which a scene states (`Scene.windowToolbarLabelStyle`, TUIkitApp).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Toolbar Label Style

/// The label style of a toolbar — mirrors SwiftUI's `ToolbarLabelStyle`.
///
/// Set on a scene with `windowToolbarLabelStyle(fixed:)`, or with
/// `windowToolbarLabelStyle(_:)` from a binding the app keeps (an
/// `@AppStorage` — the style is `Codable`, a TUIkit addition, so it can be
/// stored), and read back from ``EnvironmentValues/toolbarLabelStyle``. The
/// window's bars draw every ``Label`` in their items in the matching
/// ``LabelStyle``:
///
/// | Toolbar label style | The items' labels |
/// |---|---|
/// | ``automatic`` | as each item's environment says (by default the title and the icon) |
/// | ``iconOnly`` | ``IconOnlyLabelStyle`` |
/// | ``titleOnly`` | ``TitleOnlyLabelStyle`` |
/// | ``titleAndIcon`` | ``TitleAndIconLabelStyle`` |
///
/// A `.labelStyle(_:)` written inside an item, closer to its label, still
/// wins. Presented content's rows — a sheet's buttons — are not the window's
/// toolbar, and keep their own labels.
public struct ToolbarLabelStyle: Sendable, Equatable, Codable {
    /// The label styles a toolbar can ask for.
    private enum Kind: String, Codable {
        case automatic, iconOnly, titleOnly, titleAndIcon
    }

    private let kind: Kind

    /// The automatic label style: the toolbar uses the label style that best
    /// fits the scene — in a terminal, whatever each item's environment says.
    public static var automatic: Self { Self(kind: .automatic) }

    /// The icon only label style: the toolbar's items show only their icons.
    public static var iconOnly: Self { Self(kind: .iconOnly) }

    /// The title only label style: the toolbar's items show only their titles.
    public static var titleOnly: Self { Self(kind: .titleOnly) }

    /// The title and icon label style: the toolbar's items show both.
    public static var titleAndIcon: Self { Self(kind: .titleAndIcon) }

    /// Writes the matching label style into `environment`, or leaves it as it
    /// is for ``automatic``.
    func apply(to environment: inout EnvironmentValues) {
        switch kind {
        case .automatic: break
        case .iconOnly: environment.labelStyle = IconOnlyLabelStyle()
        case .titleOnly: environment.labelStyle = TitleOnlyLabelStyle()
        case .titleAndIcon: environment.labelStyle = TitleAndIconLabelStyle()
        }
    }
}

// MARK: - Environment

/// Environment key for the window's toolbar label style.
private struct ToolbarLabelStyleKey: EnvironmentKey {
    static let defaultValue: ToolbarLabelStyle? = nil
}

extension EnvironmentValues {
    /// The label style of the window's toolbar, or `nil` when the scene states
    /// none — mirrors SwiftUI's `EnvironmentValues.toolbarLabelStyle`.
    ///
    /// Read-only, as in SwiftUI: a scene sets it, with
    /// `windowToolbarLabelStyle(fixed:)` or `windowToolbarLabelStyle(_:)`.
    public package(set) var toolbarLabelStyle: ToolbarLabelStyle? {
        get { self[ToolbarLabelStyleKey.self] }
        set { self[ToolbarLabelStyleKey.self] = newValue }
    }
}
