//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagesPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUI
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The image demo page: one picture, from wherever it comes, and the knobs that
/// draw it.
///
/// A combo box at the top says which picture: type a local file's path or a web
/// URL and press Return, or pick one of the pictures the Example carries from
/// its menu, by name (Down or the `▾` opens it). The platform's mascot is shown
/// first, and `p`/`P` step through the bundled pictures. The controls pane and
/// the status bar items change the character set, colour mode, dithering and
/// the rest, for a file and a download alike.
///
/// The paths and URLs typed here that showed a picture are remembered, the last
/// eight, and offered under the bundled names the next time.
///
/// A picture pasted here (⌘V, or the terminal's paste) is shown in its place,
/// where the terminal hands pictures over: kitty's OSC 5522 paste events.
///
/// One page where there were two (a bundled file, and a URL) — the owner's
/// request of 2026-10-27: both drew the same picture with the same knobs, and
/// only where it came from differed.
struct ImagesPage: View {
    @State private var settings = ImageDemoSettings()
    @State private var zoom: Double = 1.0
    /// The bundled picture shown, and the one `p`/`P` step from.
    @State private var picture = DemoPicture.first
    /// A typed path or URL, or a pasted picture, shown in place of `picture`.
    @State private var elsewhere: PictureLocation?
    /// What the combo box holds: a bundled picture's name, a path or a URL.
    @State private var entry = DemoPicture.first.name
    /// Whether the picture is loaded by SwiftUI's `AsyncImage`, which hands
    /// its content the load's phase, rather than by TUI's `Image(_:)`, which
    /// draws its own placeholder.
    @State private var usesAsyncImage = false
    /// The paths and URLs typed into the combo box that showed a picture,
    /// most recent first, kept between runs (see ``RecentValues``).
    @AppStorage("images.recentEntries") private var recentEntriesJSON = "[]"

    /// How many typed paths and URLs the combo box remembers.
    private static let recentEntryLimit = 8

    var body: some View {
        // The image lives in a two-axis ScrollView fitted to the viewport: at zoom 1
        // the whole image shows with no scrollbars; `+`/`-` zoom in and out, and the
        // scrollbars appear automatically once it grows past the visible area.
        // The controls and status-bar shortcuts drive the same @State, so either
        // changes the rendering knobs.
        ImageDemoLayout(settings: $settings) {
            VStack(alignment: .leading, spacing: 0) {
                sourceRow
                imageContent
                    .imageDemoSettings(settings)
            }
        }
        .pastesPictures { path in
            elsewhere = .file(path)
            entry = path
        }
        .statusBarItems(statusBarItems)
        .navigationTitle("menu.item.images")
    }

    /// The combo box, and how the picture is loaded.
    private var sourceRow: some View {
        HStack(spacing: 1) {
            Text("page.images.sourceLabel")
                .foregroundStyle(.palette.foregroundSecondary)
            TextField("page.images.sourcePlaceholder", text: $entry)
                .onSubmit { show(entry) }
                .textContentType(.URL)
                // By name, not by path: where the Example keeps them is its
                // own business. Picking one shows it (a pick submits).
                .textInputSuggestions {
                    ForEach(DemoPicture.allCases, id: \.self) { Text($0.name) }
                    // What was typed before and showed a picture, under the
                    // pictures the Example carries.
                    let recents = RecentValues.list(from: recentEntriesJSON)
                    if !recents.isEmpty {
                        Divider()
                        ForEach(recents, id: \.self) { Text($0) }
                    }
                }
            Toggle("page.images.asyncImage", isOn: $usesAsyncImage)
        }
    }

    @ViewBuilder private var imageContent: some View {
        if usesAsyncImage, let url = shownURL {
            // The phase is the content's to draw: a spinner while it loads, the
            // picture, or why there is none.
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Spinner("page.images.loading")
                case .success(let image):
                    image.zoomableImageScroll(zoom: zoom)
                case .failure(let error):
                    Text("\(L("page.images.failed")) \(error.localizedDescription)")
                        .foregroundStyle(.palette.error)
                }
            }
        } else if let source = shownSource {
            Image(source)
                .imagePlaceholder("page.images.loading")
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
        } else {
            Text("\(L("page.images.resourceNotFound")): \(picture.fileName)")
                .foregroundStyle(.error)
        }
    }

    /// Where the picture shown is, for `Image`; `nil` for a bundled picture
    /// the bundle lacks.
    private var shownSource: ImageSource? {
        switch elsewhere {
        case .file(let path): .file(path)
        case .url(let url): .url(url.absoluteString)
        case nil: picture.path.map { .file($0) }
        }
    }

    /// Where the picture shown is, for `AsyncImage`, which takes a URL: a file
    /// as a file URL.
    private var shownURL: URL? {
        switch elsewhere {
        case .file(let path): URL(fileURLWithPath: path)
        case .url(let url): url
        case nil: picture.path.map { URL(fileURLWithPath: $0) }
        }
    }

    /// Shows what the combo box holds: the bundled picture of that name, else
    /// the file or URL it spells. Nothing, for an empty field.
    private func show(_ text: String) {
        if let named = DemoPicture.named(text) {
            picture = named
            elsewhere = nil
            entry = named.name
        } else if let location = PictureLocation(text) {
            elsewhere = location
            if location.isPicture {
                recentEntriesJSON = RecentValues.recording(
                    text.trimmingCharacters(in: .whitespaces), in: recentEntriesJSON,
                    keeping: Self.recentEntryLimit)
            }
        }
    }

    /// Shows the bundled picture `steps` along from the last one shown.
    private func step(by steps: Int) {
        picture = picture.cycled(by: steps)
        elsewhere = nil
        entry = picture.name
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        ImageDemoStatusBar.items(settings: $settings, zoom: $zoom, back: "page.images.back") + pictureItems
    }

    /// p|P: the next and the previous bundled picture, replacing a typed or
    /// pasted one.
    private var pictureItems: [any StatusBarItemProtocol] {
        [
            StatusBarItem(
                shortcut: "p|P", label: elsewhere == nil ? picture.label : "picture:other", key: .character("p")
            ) {
                step(by: 1)
            },
            StatusBarItem(shortcut: "P", label: "", key: .character("P"), displayInStatusBar: false) {
                step(by: -1)
            },
        ]
    }
}

// MARK: - A picture from elsewhere

/// A picture the Example does not carry: a local file, or one on the web.
private enum PictureLocation: Equatable {
    case file(String)
    case url(URL)

    /// Where `text` says: a URL with a scheme (`https://…`; a `file://` one
    /// is a file), else a path — `~` expanded, and relative to the working
    /// directory unless absolute. `nil` for blank text.
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        // A scheme of one letter is a Windows drive (`C:\…`), not a URL.
        if let url = URL(string: text), let scheme = url.scheme, scheme.count > 1 {
            self = url.isFileURL ? .file(url.path) : .url(url)
            return
        }
        let expanded = NSString(string: text).expandingTildeInPath
        self = .file(URL(fileURLWithPath: expanded).standardizedFileURL.path)
    }

    /// Whether this names a picture worth remembering: a file that exists (a
    /// folder is not one), or a web address (`http`/`https` with a host). A
    /// guess for the web, which only a download could settle — what it keeps
    /// out is the text that was never a location at all, such as `no such file`
    /// typed and submitted.
    var isPicture: Bool {
        switch self {
        case .file(let path):
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        case .url(let url):
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
        }
    }
}

// MARK: - A pasted picture

#if canImport(UniformTypeIdentifiers)
    extension ImagesPage {
        /// The pictures a paste may bring, most preferred first.
        fileprivate static let pastedTypes: [UTType] = [.png, .jpeg, .gif, .tiff, .image]

        /// Writes the first picture `providers` hold to a temporary file and
        /// hands its path to `show`: the image view loads files and URLs, not
        /// bytes in memory.
        fileprivate static func showPasted(_ providers: [NSItemProvider], with show: @escaping (String) -> Void) {
            // Crosses to the provider's queue only to come back: it is called
            // on the main actor alone.
            nonisolated(unsafe) let show = show
            for provider in providers {
                guard let type = pastedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
                else { continue }
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    let file = FileManager.default.temporaryDirectory
                        .appendingPathComponent("tuikit-pasted-\(UUID().uuidString)")
                        .appendingPathExtension(type.preferredFilenameExtension ?? "png")
                    guard (try? data.write(to: file)) != nil else { return }
                    Task { @MainActor in show(file.path) }
                }
                return
            }
        }
    }

    extension View {
        /// Shows a picture pasted here in place of the page's own, handing
        /// `show` the path of the file it was written to.
        fileprivate func pastesPictures(_ show: @escaping (String) -> Void) -> some View {
            onPasteCommand(of: ImagesPage.pastedTypes) { providers in
                ImagesPage.showPasted(providers, with: show)
            }
        }
    }
#else
    extension View {
        /// Nothing to paste a picture with: the platform has no type
        /// identifiers to name one.
        fileprivate func pastesPictures(_ show: @escaping (String) -> Void) -> some View { self }
    }
#endif
