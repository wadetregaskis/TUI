//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarRole.swift
//
//  `.toolbarRole(_:)`: what the content populating the window's top bar is
//  for, and so where the bar puts the title.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Toolbar Role

/// The purpose of content that populates the toolbar — mirrors SwiftUI's
/// `ToolbarRole`.
///
/// The role decides where the top bar puts the window's title once something
/// is placed at ``ToolbarItemPlacement/principal``:
///
/// | Role | The title |
/// |---|---|
/// | ``automatic`` | at the leading end, until a principal item takes its place (iOS's navigation bar) |
/// | ``editor`` | at the leading end always, with the principal items in the centre beside it (macOS's and iPadOS's editor) |
///
/// With nothing principal the two draw the same bar.
///
/// ```swift
/// ContentView()
///     .navigationTitle("Draft")
///     .toolbarRole(.editor)
///     .toolbar {
///         ToolbarItem(placement: .principal) { FormatPicker() }
///     }
/// ```
public struct ToolbarRole: Sendable, Equatable {
    /// Whether the title keeps its place beside principal items.
    let keepsTitleBesidePrincipal: Bool

    /// The automatic role: TUIkit's default, where a principal item stands in
    /// the title's place.
    ///
    /// SwiftUI resolves it to ``editor`` on macOS and to the navigation-stack
    /// role on iOS; TUIkit takes iOS's reading, as it does for
    /// ``ToolbarItemPlacement/principal`` itself.
    public static var automatic: Self { Self(keepsTitleBesidePrincipal: false) }

    /// The editor role: the title stays at the leading end of the top bar, and
    /// principal items sit in the centre beside it, for a toolbar that mostly
    /// shows controls for editing document-like content.
    public static var editor: Self { Self(keepsTitleBesidePrincipal: true) }
}

// MARK: - Public Modifier

extension View {
    /// Configures the semantic role for the content populating the toolbar —
    /// mirrors SwiftUI's `toolbarRole(_:)`.
    ///
    /// The role is the window's, as SwiftUI's is the toolbar's: it flows up
    /// from the page like ``toolbarVisibility(_:for:)``, the one declared
    /// closest to the content wins, and presented content states nothing. It
    /// takes effect this frame — unless it changes how many rows the top bar
    /// needs, which, like any change to a bar's rows, is adopted the frame
    /// after.
    ///
    /// - Parameter role: The role of the toolbar.
    /// - Returns: A view whose toolbar has `role`.
    public func toolbarRole(_ role: ToolbarRole) -> some View {
        _ToolbarBarStatementModifier(content: self, statement: .role(role), bars: [.windowToolbar])
    }
}
