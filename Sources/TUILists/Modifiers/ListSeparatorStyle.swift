//  🖥️ TUI — A Terminal UI framework for Swift
//  ListSeparatorStyle.swift
//
//  What a list's separators look like, and so what they cost: a rule line of
//  its own, or a hairline that takes no row (decisions A-D6L-2).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - The look

/// How the separators of the lists below are drawn — a TUI-only choice beside
/// SwiftUI's ``View/listRowSeparator(_:edges:)`` family, which says WHETHER a
/// separator shows and in which colour, and is untouched by this.
///
/// SwiftUI has no such choice because a window has no rows to spend: its
/// separator is a hairline between two rows and costs nothing. In a terminal a
/// line drawn with cells is a whole row, which doubles a list of one-line rows.
/// A terminal that draws Kitty graphics pictures outside its cell grid can draw
/// the hairline instead, a pixel or two thick on the boundary between two rows,
/// at no cost in rows; others cannot.
///
/// ```swift
/// List(items) { item in
///     Text(item.name)
/// }
/// .listSeparatorStyle(.line)   // a rule line of its own, on every terminal
/// ```
///
/// What `.automatic` visibility means follows from the look:
///
/// | Look | Separator `.automatic` | `.visible` |
/// |---|---|---|
/// | `.hairline` | shown, as SwiftUI's default: under `.automatic`, `.inset`, `.bordered`, `.plain` and `.surface`; hidden under `.sidebar` and `.insetGrouped` | a hairline |
/// | `.line` | hidden: no built-in style spends a row on one unasked | a rule line of its own |
///
/// So by default (`.automatic`), a list on a terminal that draws hairlines —
/// Ghostty, measured — has SwiftUI's separators and the density of one without
/// them, and a list anywhere else looks as it always has.
public enum ListSeparatorStyle: Sendable, Equatable {
    /// A hairline where the terminal draws one, a rule line elsewhere
    /// (``KittyGraphics/isHairlineSupported``). The default.
    case automatic
    /// A faint `─` rule on a line of its own, below the row it separates —
    /// what every terminal can draw, at the price of a row.
    case line
    /// A line a pixel or two thick along the top of the next row, which takes
    /// no row on any terminal and is drawn only where the terminal can draw
    /// it — on any other, the rows simply have no line between them.
    case hairline

    /// Whether this look draws hairlines on the terminal in front of the app:
    /// `.automatic` resolved by ``KittyGraphics/isHairlineSupported``, and never at
    /// ``ColorDepth/noColor``. A hairline is a picture in the border's colour, so
    /// there, like a gradient's picture, it is colour that nobody asked for.
    var drawsHairlines: Bool {
        switch self {
        case .automatic: KittyGraphics.isHairlineSupported && ColorDepth.current > .noColor
        case .line: false
        case .hairline: true
        }
    }
}

private struct ListSeparatorStyleKey: EnvironmentKey {
    static let defaultValue = ListSeparatorStyle.automatic
}

extension EnvironmentValues {
    /// How the separators of the lists in this subtree are drawn. Set via
    /// ``View/listSeparatorStyle(_:)``.
    public var listSeparatorStyle: ListSeparatorStyle {
        get { self[ListSeparatorStyleKey.self] }
        set { self[ListSeparatorStyleKey.self] = newValue }
    }

    /// Whether a separator left `.automatic` shows in the lists in this
    /// subtree: only under a hairline look, and then as SwiftUI's default
    /// does — in every style but `.sidebar` and `.insetGrouped`
    /// (``ListSeparatorStyle``).
    var listSeparatorsShowByDefault: Bool {
        guard listSeparatorStyle.drawsHairlines else { return false }
        let style = listStyle
        return !(style is SidebarListStyle || style is InsetGroupedListStyle)
    }
}

// MARK: - The modifier

extension View {
    /// Sets how the separators of the lists in this view are drawn: a
    /// hairline that takes no row, where the terminal can draw one, or a rule
    /// line of its own.
    ///
    /// A TUI-only modifier. SwiftUI's separator modifiers say whether a
    /// separator shows and in which colour; this says what one costs. See
    /// ``ListSeparatorStyle`` for what each look draws, and what `.automatic`
    /// visibility means under it.
    ///
    /// Written on a `List`, or above one, it applies to every row and section
    /// separator of the lists below.
    ///
    /// - Parameter style: The look. The default is `.automatic`.
    nonisolated public func listSeparatorStyle(_ style: ListSeparatorStyle) -> some View {
        environment(\.listSeparatorStyle, style)
    }
}
