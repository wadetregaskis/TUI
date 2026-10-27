//  🖥️ TUI — A Terminal UI framework for Swift
//  MaterialsClip.swift
//
//  `materials`: a photo library, and what floats over it — a share panel on
//  frosted glass, a toast on another, a popover — the library still
//  there, frosted, behind each.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let materialsClip = Clip(
    id: "materials",
    title: "Materials",
    columns: 112,
    rows: 30,
    output: 800,
    // Photographs, and blurs of them: WebP blocks them at the default quality.
    quality: 90,
    budgetKB: 900,
    script: [
        .camera(Shot(x: 0, y: 3, width: 76, height: 25)),
        .wait(1.2), .cue("panel"),
        .wait(2.8), .cue("dismiss"),
        .wait(0.6), .cue("toast"),
        .wait(2.2), .cue("dismiss"),
        .wait(0.6), .cue("popover"),
        .wait(2.4), .cue("dismiss"),
        .wait(1.0),
    ],
    run: { await MaterialsApp.main() }
)

struct MaterialsApp: App {
    var body: some Scene {
        WindowGroup("TUI · Library") {
            PhotoLibrary()
                .palette(AppleTerminalPalette(.novel))
        }
    }
}

/// An album of photos, and the three ways it asks something.
struct PhotoLibrary: View {
    @State private var sharing = false
    @State private var toasting = false
    @State private var showingInfo = false

    /// The album: the owner's photographs (Photos/), by file and caption.
    private static let photos: [(file: String, caption: String)] = [
        ("burrowing-owl", "Burrowing owl"), ("ground-squirrel", "Ground squirrel"),
        ("bald-eagle", "Bald eagle"), ("fawn", "Fawn"),
        ("banana-slug", "Banana slug"), ("cedar-waxwings", "Cedar waxwings"),
        ("lioness", "Lioness"), ("galago", "Galago"),
        ("spurred-tortoise", "Spurred tortoise"), ("salamander", "Salamander"),
        ("snail", "Snail"), ("bee-drinking", "Bee drinking"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(verbatim: "Wildlife").bold()
                Text(verbatim: "12 photos · 41 MB").foregroundStyle(.palette.foregroundSecondary)
                Spinner()
                Text(verbatim: "Syncing").foregroundStyle(.palette.foregroundTertiary)
                Button("Info") { showingInfo = true }
                    .popover(isPresented: $showingInfo) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "Burrowing owl").bold()
                            Text(verbatim: "Athene cunicularia").italic()
                            Text(verbatim: "1024 × 987 · 3.2 MB").foregroundStyle(.palette.foregroundSecondary)
                        }
                        .padding(.horizontal, 1)
                    }
                Button("Share…") { sharing = true }
                Button("Copy") { toasting = true }
                Spacer()
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            tile(Self.photos[row * 4 + column], index: row * 4 + column)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Photos") }
        }
        // Floating surfaces, not a sheet or an alert: a modal flattens the page
        // behind it to two colours (`dimmedAsBackdrop`), so there would be no
        // library left to frost.
        .overlay(alignment: .topLeading) {
            if sharing {
                sharePanel
                    .offset(x: 24, y: 6)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if toasting {
                Text(verbatim: " ✓ Copied 12 photos to the clipboard ")
                    .bold()
                    .padding(.horizontal, 1)
                    .background(.regularMaterial)
                    .offset(x: 18, y: 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            for await cue in ClipCues.stream() {
                withAnimation(.easeInOut(duration: 0.3)) {
                    switch cue {
                    case "panel": sharing = true
                    case "toast": toasting = true
                    case "popover": showingInfo = true
                    default: sharing = false; toasting = false; showingInfo = false
                    }
                }
            }
        }
    }

    /// The share panel: a floating inspector on frosted glass.
    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "Share 12 photos").bold()
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("To") { Text(verbatim: "sam@example.com") }
                LabeledContent("Size") { Text(verbatim: "Large · 41 MB") }
                Toggle("Include location", isOn: .constant(true))
            }
            HStack(spacing: 2) {
                Spacer()
                Button("Cancel") { sharing = false }
                Button("Share") { sharing = false }.buttonStyle(.borderedProminent)
            }
        }
        .padding(1)
        .frame(width: 40)
        // Behind the border, not inside it: inside, the border's own inset
        // (a cell each side) was left unglazed, the photo plain in it.
        .border()
        .background(.thinMaterial)
    }

    /// A photo, its caption beneath, in the terminal's own pixels (Kitty's
    /// graphics, in Ghostty). A material over it frosts a blurred copy of the
    /// picture, which the cells under the glass draw instead.
    private func tile(_ photo: (file: String, caption: String), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.file(ClipAssets.photo(photo.file)))
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 6)
            Text(verbatim: photo.caption).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
