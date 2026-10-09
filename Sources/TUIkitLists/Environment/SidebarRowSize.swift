//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SidebarRowSize.swift
//
//  The size of a sidebar's rows: always medium, because a terminal row is one
//  line of text in the terminal's one font.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// The standard sizes of sidebar rows.
///
/// On macOS, sidebar rows have three sizes, chosen by the "Sidebar icon size"
/// in the Appearance settings. A terminal's rows are lines of text in one
/// font, so TUIkit's are always ``medium`` — the size SwiftUI reports on every
/// platform but macOS.
public enum SidebarRowSize: Hashable, Sendable {
    /// The standard "small" row size.
    case small
    /// The standard "medium" row size.
    case medium
    /// The standard "large" row size.
    case large
}

extension EnvironmentValues {
    /// The current size of sidebar rows: always ``SidebarRowSize/medium``.
    ///
    /// Read-only, where SwiftUI's is settable: on macOS a write forces a
    /// sidebar's rows, and the `Label`s in them, to that size. A terminal row
    /// is one line of one font and cannot be made smaller or larger, so a
    /// write would be accepted and ignored; left out, it fails to compile
    /// instead (decisions B74). SwiftUI's own answer off macOS is the same
    /// `.medium`, and there it ignores a write.
    public var sidebarRowSize: SidebarRowSize { .medium }
}
