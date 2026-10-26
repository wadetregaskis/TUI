//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageFilePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUI
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Image demo page for loading an image from the local filesystem.
///
/// Displays a bundled demo image and provides status bar items to
/// cycle through character set, color mode, and dithering settings.
///
/// A picture pasted here (⌘V, or the terminal's paste) is shown in its place,
/// where the terminal hands pictures over: kitty's OSC 5522 paste events.
struct ImageFilePage: View {
    @State private var settings = ImageDemoSettings()
    @State private var zoom: Double = 1.0
    /// Where a pasted picture was written, to be shown as a file is.
    @State private var pastedPath: String?

    var body: some View {
        // The image lives in a two-axis ScrollView fitted to the viewport: at zoom 1
        // the whole image shows with no scrollbars; `+`/`-` zoom in and out, and the
        // scrollbars appear automatically once it grows past the visible area.
        // The controls and status-bar shortcuts drive the same @State, so either
        // changes the rendering knobs.
        ImageDemoLayout(settings: $settings) {
            imageContent
                .imageDemoSettings(settings)
        }
        .pastesPictures(into: $pastedPath)
        .statusBarItems(statusBarItems)
        .navigationTitle("menu.item.imageFile")
    }

    @ViewBuilder private var imageContent: some View {
        if let path = pastedPath
            ?? Bundle.module.path(forResource: "demo-image", ofType: "jpg", inDirectory: "Resources")
        {
            Image(.file(path))
                .imagePlaceholder("page.imageFile.loading")
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
        } else {
            Text("\(L("page.imageFile.resourceNotFound")): demo-image.jpg")
                .foregroundStyle(.error)
        }
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        ImageDemoStatusBar.items(settings: $settings, zoom: $zoom, back: "page.imageFile.back")
    }
}

// MARK: - A pasted picture

#if canImport(UniformTypeIdentifiers)
    extension ImageFilePage {
        /// The pictures a paste may bring, most preferred first.
        fileprivate static let pastedTypes: [UTType] = [.png, .jpeg, .gif, .tiff, .image]

        /// Writes the first picture `providers` hold to a temporary file and
        /// shows it: the image view loads files and URLs, not bytes in memory.
        fileprivate static func showPasted(_ providers: [NSItemProvider], at path: Binding<String?>) {
            // Crosses to the provider's queue only to come back: it is read and
            // written on the main actor alone.
            nonisolated(unsafe) let path = path
            for provider in providers {
                guard let type = pastedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
                else { continue }
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    let file = FileManager.default.temporaryDirectory
                        .appendingPathComponent("tuikit-pasted-\(UUID().uuidString)")
                        .appendingPathExtension(type.preferredFilenameExtension ?? "png")
                    guard (try? data.write(to: file)) != nil else { return }
                    Task { @MainActor in path.wrappedValue = file.path }
                }
                return
            }
        }
    }

    extension View {
        /// Shows a picture pasted here in place of the page's own.
        fileprivate func pastesPictures(into path: Binding<String?>) -> some View {
            onPasteCommand(of: ImageFilePage.pastedTypes) { providers in
                ImageFilePage.showPasted(providers, at: path)
            }
        }
    }
#else
    extension View {
        /// Nothing to paste a picture with: the platform has no type
        /// identifiers to name one.
        fileprivate func pastesPictures(into path: Binding<String?>) -> some View { self }
    }
#endif
