//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageURLPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Image demo page for loading an image from a URL.
///
/// Provides a text field for entering an image URL. After pressing
/// Enter the image is downloaded and rendered. Status bar items allow
/// cycling through character set, color mode, and dithering settings.
struct ImageURLPage: View {
    @State private var imageURL: String = ""
    @State private var activeURL: String = ""
    @State private var settings = ImageDemoSettings()
    @State private var zoom: Double = 1.0
    /// Whether the picture is loaded by SwiftUI's `AsyncImage`, which hands
    /// its content the load's phase, rather than by TUIkit's `Image(.url(_:))`,
    /// which draws its own placeholder.
    @State private var usesAsyncImage = false

    var body: some View {
        ImageDemoLayout(settings: $settings) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("page.imageURL.urlLabel")
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField("page.imageURL.urlPlaceholder", text: $imageURL)
                        .onSubmit {
                            activeURL = imageURL
                        }
                        .textContentType(.url)
                    Toggle("page.imageURL.asyncImage", isOn: $usesAsyncImage)
                }
                picture
                    .imageDemoSettings(settings)
            }
        }
        .statusBarItems(
            ImageDemoStatusBar.items(settings: $settings, zoom: $zoom, back: "page.imageURL.back"))
        .navigationTitle("menu.item.imageURL")
    }

    @ViewBuilder private var picture: some View {
        if !activeURL.isEmpty, usesAsyncImage {
            // The phase is the content's to draw: a spinner while it loads, the
            // picture, or why there is none.
            AsyncImage(url: URL(string: activeURL)) { phase in
                switch phase {
                case .empty:
                    Spinner("page.imageURL.downloading")
                case .success(let image):
                    image.zoomableImageScroll(zoom: zoom)
                case .failure(let error):
                    Text("\(L("page.imageURL.failed")) \(error.localizedDescription)")
                        .foregroundStyle(.palette.error)
                }
            }
            .border(.palette.border)
        } else if !activeURL.isEmpty {
            // Loaded image fills the rest of the pane in a viewport-fitted,
            // zoomable two-axis scroll (+/- to zoom; scrollbars appear on zoom).
            Image(.url(activeURL))
                .imagePlaceholder("page.imageURL.downloading")
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
                .border(.palette.border)
        } else {
            Spacer()
            HStack {
                Spacer()
                Text("page.imageURL.pressEnter")
                    .foregroundStyle(.palette.foregroundTertiary)
                    .italic()
                Spacer()
            }
            Spacer()
        }
    }
}
