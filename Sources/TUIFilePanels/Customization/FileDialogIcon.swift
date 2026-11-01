//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialogIcon.swift
//
//  `fileDialogIcon(_:)`: an app's own icon for each item of the file panels
//  beneath it, drawn in place of TUI's glyphs (decisions A-FP2-1, the
//  owner's option 2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

private struct FileDialogIconKey: EnvironmentKey {
    static var defaultValue: FileDialogItemViews? { nil }
}

extension EnvironmentValues {
    /// The icons an app draws for the items of the file panels beneath
    /// (`fileDialogIcon(_:)`), or `nil` for TUI's own (``FilePanelIcon``).
    var fileDialogIcon: FileDialogItemViews? {
        get { self[FileDialogIconKey.self] }
        set { self[FileDialogIconKey.self] = newValue }
    }
}

extension View {
    /// Draws each item of the `fileImporter`, `fileExporter` and `fileMover`
    /// panels beneath this view with an icon the app supplies. A TUI-specific
    /// modifier: SwiftUI's panels are the system's, which draw the system's
    /// icons themselves.
    ///
    /// The closure is given each item's URL and content type and returns the
    /// view to draw before its name, in the two cells, one row high, an emoji
    /// icon takes; `nil` keeps TUI's own icon for that item — the kind's
    /// emoji, SF Symbol or none, whichever the terminal draws.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { … }
    /// .fileDialogIcon { url, type in
    ///     type.conforms(to: .image) ? thumbnail(of: url) : nil
    /// }
    /// ```
    ///
    /// It is called on the main actor as rows are drawn, so it should be
    /// quick, keeping what it makes: an `Image` made afresh from new pixels
    /// for every call is a new picture each frame. On macOS,
    /// `fileDialogSystemIcons()` in TUIFilePanelsAppKit installs one that draws each
    /// item's own icon, the Finder's, where the terminal draws pictures.
    ///
    /// - Parameter icon: The view to draw for the item at a URL, of a content
    ///   type, or `nil` for TUI's own icon.
    nonisolated public func fileDialogIcon<Icon: View>(_ icon: @escaping @MainActor (URL, UTType) -> Icon?) -> some View {
        FileDialogItemViewsModifier(content: self, keyPath: \.fileDialogIcon) { url, type in
            icon(url, type).map { AnyView($0) }
        }
    }
}
