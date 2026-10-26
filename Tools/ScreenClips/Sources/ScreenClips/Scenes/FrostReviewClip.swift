//  🖥️ TUI — A Terminal UI framework for Swift
//  FrostReviewClip.swift
//
//  `frostreview`: not a README clip — a still scene for the owner to review
//  glass over pictures the terminal draws (Kitty graphics), before any clip
//  uses it (`Terminal graphics protocols.md` §14). Run it live:
//
//      swift run --package-path Tools/ScreenClips ScreenClips --child frostreview
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let frostReviewClip = Clip(
    id: "frostreview",
    title: "Frost over pictures (review)",
    columns: 100,
    rows: 28,
    output: 800,
    script: [.wait(4.0)],
    run: { await FrostReviewApp.main() }
)

struct FrostReviewApp: App {
    var body: some Scene {
        WindowGroup("TUI · Frost review") {
            FrostReview()
                .palette(AppleTerminalPalette(.novel))
        }
    }
}

/// Four photographs drawn by the terminal, a share panel on thin glass across
/// two of them, and a toast on regular glass across the other two.
struct FrostReview: View {
    private static let photos: [(file: String, caption: String)] = [
        ("fawn", "Fawn"), ("galago", "Galago"), ("forest-path", "Forest path"), ("pacific-trillium", "Trillium"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                tile(Self.photos[0])
                tile(Self.photos[1])
            }
            HStack(spacing: 2) {
                tile(Self.photos[2])
                tile(Self.photos[3])
            }
        }
        .padding(1)
        .overlay(alignment: .topLeading) {
            sharePanel.offset(x: 20, y: 3)
        }
        .overlay(alignment: .topLeading) {
            Text(verbatim: " ✓ Copied 4 photos to the clipboard ")
                .bold()
                .padding(.horizontal, 1)
                .background(.regularMaterial)
                .offset(x: 10, y: 19)
        }
    }

    /// The share panel: a floating inspector on frosted glass.
    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "Share 4 photos").bold()
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("To") { Text(verbatim: "sam@example.com") }
                LabeledContent("Size") { Text(verbatim: "Large · 12 MB") }
            }
            HStack(spacing: 2) {
                Spacer()
                Button("Cancel") {}
                Button("Share") {}.buttonStyle(.borderedProminent)
            }
        }
        .padding(1)
        .frame(width: 40)
        .background(.thinMaterial)
        .border()
    }

    /// A photo the terminal draws, its caption beneath.
    private func tile(_ photo: (file: String, caption: String)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.file(ClipAssets.photo(photo.file)))
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 11)
            Text(verbatim: photo.caption).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
