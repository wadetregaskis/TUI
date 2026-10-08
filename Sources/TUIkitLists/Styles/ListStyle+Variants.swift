//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStyle+Variants.swift
//
//  SwiftUI's macOS list styles beyond `.plain`: `.automatic`, `.bordered`,
//  `.inset` and `.sidebar`.
//
//  Measured on macOS 15.8, each is an `NSTableView` in a scroll view: the
//  default and `.inset` of table style `.inset` with no border, `.bordered` of
//  style `.fullWidth` in a line-bordered scroll view, `.sidebar` of style
//  `.sourceList`, and `.plain` of style `.plain`. None stripes its rows.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Bordered

/// The list style that describes the behavior and appearance of a list with
/// standard border: a box around the rows, which run its full width.
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct BorderedListStyle: ListStyle, Equatable {
    /// Creates a bordered list style.
    public init() {}

    public var showsBorder: Bool { true }
    public var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    public var alternatingRowColors: Bool { false }
}

// MARK: - Inset

/// The list style that describes the behavior and appearance of an inset
/// list: no border, and the rows — their highlight with them — inset a cell
/// from the list's edges, as a macOS inset list rounds its highlight inside
/// the row.
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct InsetListStyle: ListStyle, Equatable {
    /// Creates an inset list style.
    public init() {}

    public var showsBorder: Bool { false }
    public var rowPadding: EdgeInsets { EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1) }
    public var alternatingRowColors: Bool { false }
}

// MARK: - Sidebar

/// The list style that describes the behavior and appearance of a sidebar
/// list: no border, and each row's `Label` icon in the list item tint — the
/// accent unless ``View/listItemTint(_:)-(ListItemTint?)`` says otherwise — as
/// a macOS sidebar draws it.
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct SidebarListStyle: ListStyle, Equatable {
    /// Creates a sidebar list style.
    public init() {}

    public var showsBorder: Bool { false }
    public var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    public var alternatingRowColors: Bool { false }
}

// MARK: - Surface

/// TUIkit's own list style, and a PROTOTYPE to try: the list told from the
/// text around it by a surface of its own rather than by a border. The rows
/// inset a cell from the edges, as under ``InsetListStyle``, on the surface a
/// `TabView`'s body is drawn on — one plane's step off what the list sits on —
/// and its title and section headers on a step stronger still.
///
/// SwiftUI has no such style: a macOS list needs none, its window drawing a
/// list's rows on a field of their own. Whether TUIkit's default should look
/// like this is the owner's open question (decisions A46, and A-D6L-1 in the
/// D6L decisions); the name may change, or go, when it is answered.
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct SurfaceListStyle: ListStyle, Equatable {
    /// Creates a surface list style.
    public init() {}

    public var showsBorder: Bool { false }
    public var rowPadding: EdgeInsets { EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1) }
    public var alternatingRowColors: Bool { false }
}

// MARK: - Leading-dot spellings

extension ListStyle where Self == DefaultListStyle {
    /// The list style that describes a platform's default behavior and
    /// appearance for a list: bordered, in TUIkit.
    public static var automatic: DefaultListStyle { DefaultListStyle() }
}

extension ListStyle where Self == BorderedListStyle {
    /// The list style that describes the behavior and appearance of a list
    /// with standard border.
    public static var bordered: BorderedListStyle { BorderedListStyle() }
}

extension ListStyle where Self == InsetListStyle {
    /// The list style that describes the behavior and appearance of an inset
    /// list.
    public static var inset: InsetListStyle { InsetListStyle() }
}

extension ListStyle where Self == SurfaceListStyle {
    /// TUIkit's own: an inset list on a surface of its own, its headers a step
    /// stronger — a prototype (see ``SurfaceListStyle``).
    public static var surface: SurfaceListStyle { SurfaceListStyle() }
}

extension ListStyle where Self == SidebarListStyle {
    /// The list style that describes the behavior and appearance of a sidebar
    /// list.
    public static var sidebar: SidebarListStyle { SidebarListStyle() }
}
