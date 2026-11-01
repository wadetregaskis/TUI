//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialogPreview.swift
//
//  `fileDialogPreview(_:)`: an app's own preview of the item selected in the
//  column view of the file panels beneath it, drawn at the top of the preview
//  column (`FilePanelPreview`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

private struct FileDialogPreviewKey: EnvironmentKey {
    static var defaultValue: FileDialogItemViews? { nil }
}

extension EnvironmentValues {
    /// The previews an app draws for the items of the file panels beneath
    /// (`fileDialogPreview(_:)`), or `nil` for TUI's own.
    var fileDialogPreview: FileDialogItemViews? {
        get { self[FileDialogPreviewKey.self] }
        set { self[FileDialogPreviewKey.self] = newValue }
    }
}

extension View {
    /// Draws a preview the app supplies for the item selected in the column
    /// view of the `fileImporter`, `fileExporter` and `fileMover` panels
    /// beneath this view. A TUI-specific modifier: SwiftUI's panels are the
    /// system's, whose column view previews a file with Quick Look.
    ///
    /// The closure is given the item's URL and content type and returns the
    /// view to draw at the top of the preview column, above the item's name,
    /// kind, size and date, in the room they leave; `nil` keeps TUI's own
    /// preview for that item — the opening lines of a text file, and nothing
    /// for anything else.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { … }
    /// .fileDialogPreview { url, type in
    ///     type.conforms(to: .image) ? Image(.file(url.path)).resizable().scaledToFit() : nil
    /// }
    /// ```
    ///
    /// It is called on the main actor as the column draws, so it should be
    /// quick, as ``fileDialogIcon(_:)``'s is.
    ///
    /// - Parameter preview: The view to draw for the item at a URL, of a
    ///   content type, or `nil` for TUI's own preview.
    public func fileDialogPreview<Preview: View>(
        _ preview: @escaping @MainActor (URL, UTType) -> Preview?
    ) -> some View {
        FileDialogItemViewsModifier(content: self, keyPath: \.fileDialogPreview) { url, type in
            preview(url, type).map { AnyView($0) }
        }
    }
}
