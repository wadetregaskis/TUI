//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowHeightEnvironment.swift
//
//  The least height a list gives its rows and its section headers.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

private struct DefaultMinListRowHeightKey: EnvironmentKey {
    static let defaultValue = 1
}

private struct DefaultMinListHeaderHeightKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The default minimum height of rows in a list, in lines.
    ///
    /// The height of list rows is bounded below by this value, and is
    /// otherwise determined by the height of the row's content and the row
    /// insets. A row shorter than it is drawn with its content centred in the
    /// lines it is given, as a macOS list centres a row's content in a taller
    /// row. Defaults to one line, which every row has anyway.
    ///
    /// ```swift
    /// List(items) { Text($0.name) }
    ///     .environment(\.defaultMinListRowHeight, 3)
    /// ```
    public var defaultMinListRowHeight: Int {
        get { self[DefaultMinListRowHeightKey.self] }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }

    /// The default minimum height of a header in a list, in lines.
    ///
    /// When this value is `nil`, the system chooses the appropriate height: a
    /// header's own. The default is `nil`.
    public var defaultMinListHeaderHeight: Int? {
        get { self[DefaultMinListHeaderHeightKey.self] }
        set { self[DefaultMinListHeaderHeightKey.self] = newValue }
    }
}
