//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialogBrowserOptions.swift
//
//  SwiftUI's `FileDialogBrowserOptions`: how a file panel presents the file
//  system.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The way that file dialogs present the file system.
///
/// Apply the options using the `fileDialogBrowserOptions(_:)` modifier. The raw
/// values are SwiftUI's (1, 2 and 4, read off macOS 15.8), so an option set
/// stored by one framework reads back the same in the other.
public struct FileDialogBrowserOptions: OptionSet, Sendable {
    /// The corresponding value of the raw type.
    public let rawValue: Int

    /// Creates a new option set from the given raw value.
    ///
    /// - Parameter rawValue: The raw value of the option set to create.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Allows enumerating packages contents in contrast to the default behavior
    /// when packages are represented flatly, similar to files.
    public static let enumeratePackages = Self(rawValue: 1 << 0)

    /// Displays the files that are hidden by default.
    public static let includeHiddenFiles = Self(rawValue: 1 << 1)

    /// On iOS, configures the `fileExporter`, `fileImporter`, or `fileMover` to
    /// show or hide file extensions. Default behavior is to hide them. On macOS,
    /// this option has no effect, and nor does it here: a TUI panel, like a
    /// macOS one, always shows a file's whole name.
    public static let displayFileExtensions = Self(rawValue: 1 << 2)
}
