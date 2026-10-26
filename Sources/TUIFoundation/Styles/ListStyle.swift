//  🖥️ TUI — A Terminal UI framework for Swift
//  ListStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A style that customizes the appearance of lists.
///
/// List styles control how lists render: whether the list draws a border, the
/// padding around its rows, and whether rows alternate backgrounds. The
/// built-in styles:
/// - ``DefaultListStyle`` (`.automatic`): the default — a bordered box in
///   TUI, where SwiftUI's macOS default has no border.
/// - ``BorderedListStyle`` (`.bordered`): a box around full-width rows.
/// - ``InsetListStyle`` (`.inset`): no border, the rows inset a cell from the
///   edges.
/// - ``PlainListStyle`` (`.plain`): no border, full-width rows.
/// - ``SidebarListStyle`` (`.sidebar`): no border, and the rows' `Label` icons
///   in the list item tint.
/// - ``InsetGroupedListStyle`` (`.insetGrouped`): bordered, as `.bordered` is
///   (iOS's name; SwiftUI does not offer it on macOS).
/// - ``SurfaceListStyle`` (`.surface`): TUI's own, a prototype — `.inset`
///   on a surface of its own, the title and section headers a step stronger.
///
/// # Usage
///
/// ```swift
/// List {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// .listStyle(.plain)
///
/// List {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// .listStyle(.insetGrouped)
/// ```
///
/// ## Styles and the render cache
///
/// ``View/listStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// Both built-in styles are therefore `Equatable`. Without that, a single
/// `.listStyle(...)` turned the cache off for the whole list below it — every
/// row of it, and the list's own hug-width measurement with them. Neither style
/// holds anything, and all three of what a style says about a list are literal
/// constants on both, so the conformance is a formality here: every instance of
/// one styles a list identically. A custom style need not conform: one that does
/// not simply turns memoization off below itself, which costs render time rather
/// than correctness.
///
/// - Note: SwiftUI's list styles declare no such conformance, and this is one of
///   the places a terminal renderer has to differ. SwiftUI diffs the view graph
///   the compiler builds for it and never has to ask whether an environment
///   value changed; TUI re-runs `body` and compares values, so here the
///   question must be answerable.
public protocol ListStyle: Sendable {
    /// Whether the list should display borders around the container.
    var showsBorder: Bool { get }

    /// The padding applied to list rows.
    var rowPadding: EdgeInsets { get }

    /// Whether rows alternate backgrounds.
    ///
    /// The style says *whether*, and the palette says *which*: when this is
    /// true, `_ListCore` tints every odd-indexed row within a section — the
    /// second, the fourth and so on, the phase a macOS list draws (measured;
    /// see `_ListCore.alternatingBackgroundIfAny`) — with the palette's accent
    /// at low opacity and leaves the even rows untinted, so an app's theme
    /// keeps control of the colour. The index belongs to
    /// the row, not to where it happens to be drawn: it counts from the
    /// section's first row however far the list has scrolled, so the stripes
    /// stay on their rows. A focused or selected row keeps its own highlight
    /// either way. Both built-in styles return
    /// false, so this is a hook for a conforming style rather than something
    /// TUI's own styles turn on.
    var alternatingRowColors: Bool { get }
}
