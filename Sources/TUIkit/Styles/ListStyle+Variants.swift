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

// MARK: - Default

/// The list style that describes a platform's default behavior and appearance
/// for a list: in TUIkit, a bordered box — the look a list has always had
/// here, where SwiftUI's macOS default draws no border (decisions A-W08b-1).
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct DefaultListStyle: ListStyle, Equatable {
    /// Creates a default list style.
    public init() {}

    public var showsBorder: Bool { true }
    public var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    public var alternatingRowColors: Bool { false }
}

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

extension ListStyle where Self == SidebarListStyle {
    /// The list style that describes the behavior and appearance of a sidebar
    /// list.
    public static var sidebar: SidebarListStyle { SidebarListStyle() }
}
