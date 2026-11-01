//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialog+PicturePreviews.swift
//
//  `fileDialogPicturePreviews()`: the file panels' column view previewing a
//  selected picture, as the Finder's does — here, in a module on both the
//  file panels and the image decoders, so that neither pays for the other
//  (`Exports.swift` in this module).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIBitmaps
import TUIFilePanels
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

extension View {
    /// Previews a picture selected in the column view of the `fileImporter`,
    /// `fileExporter` and `fileMover` panels beneath this view, fitted to the
    /// top of the preview column, as the Finder's column view does. A
    /// TUI-specific modifier, built on `fileDialogPreview(_:)`: SwiftUI's
    /// panels are the system's, which preview with Quick Look.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { … }
    /// .fileDialogPicturePreviews()
    /// ```
    ///
    /// A picture is drawn as any `Image` is: with the terminal's graphics
    /// where it has them and `terminalGraphics(_:)` has not turned them off,
    /// and in glyphs elsewhere, which at a preview's size still shows what
    /// the picture is. Any other file keeps TUI's own preview, the opening
    /// lines of a text file. Like any `fileDialogPreview(_:)`, the innermost
    /// one wins: an app's own written inside this replaces it.
    nonisolated public func fileDialogPicturePreviews() -> some View {
        fileDialogPreview { url, type in
            FileDialogPicturePreviews.isPicture(type)
                ? Image(.file(url.path)).resizable().scaledToFit() : nil
        }
    }
}

/// What `fileDialogPicturePreviews()` previews.
enum FileDialogPicturePreviews {
    /// Whether a file of `type` is a picture the image decoders read: any
    /// image where the system's decoders are (ImageIO reads every raster
    /// format the host does, and a PDF's first page), and elsewhere the formats
    /// the bundled decoder reads (`PlatformImageLoader`).
    static func isPicture(_ type: UTType) -> Bool {
        #if canImport(ImageIO)
            type.conforms(to: .image) || type.conforms(to: .pdf)
        #else
            [UTType.png, .jpeg, .gif, .bmp].contains { type.conforms(to: $0) }
        #endif
    }
}
