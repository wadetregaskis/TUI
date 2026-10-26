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
    script: [
        .camera(Shot(x: 0, y: 3, width: 76, height: 22)),
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

    /// The album: make_photos.py's pictures, by file and caption.
    private static let photos: [(file: String, caption: String)] = [
        ("harbour-at-dawn", "Harbour at dawn"), ("glacier", "Glacier lagoon"),
        ("dunes", "Dunes"), ("night-city", "Night city"),
        ("fern-valley", "Fern valley"), ("lagoon", "Lagoon"),
        ("orchard", "Orchard"), ("aurora", "Aurora"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(verbatim: "Iceland, 2026").bold()
                Text(verbatim: "8 photos · 214 MB").foregroundStyle(.palette.foregroundSecondary)
                Spinner()
                Text(verbatim: "Syncing").foregroundStyle(.palette.foregroundTertiary)
                Button("Info") { showingInfo = true }
                    .popover(isPresented: $showingInfo) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "Harbour at dawn").bold()
                            Text(verbatim: "Reykjavík · 06:12")
                            Text(verbatim: "ƒ/2.8 · 1/250 s · ISO 100").foregroundStyle(.palette.foregroundSecondary)
                        }
                        .padding(.horizontal, 1)
                    }
                Button("Share…") { sharing = true }
                Button("Copy") { toasting = true }
                Spacer()
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 1) {
                ForEach(0..<2, id: \.self) { row in
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
                Text(verbatim: " ✓ Copied 8 photos to the clipboard ")
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
            Text(verbatim: "Share 8 photos").bold()
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("To") { Text(verbatim: "kristín@example.is") }
                LabeledContent("Size") { Text(verbatim: "Large · 214 MB") }
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
        .background(.thinMaterial)
        .border()
    }

    /// A photo, its caption beneath. Drawn in text cells (half blocks), not
    /// the terminal's graphics: a material's frost blurs what is beneath it
    /// cell by cell, and a picture the terminal draws itself is not in the
    /// cells.
    private func tile(_ photo: (file: String, caption: String), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.file(ClipAssets.photo(photo.file)))
                .resizable()
                .scaledToFill()
                .terminalGraphics(false)
                .frame(width: 22, height: 7)
            Text(verbatim: photo.caption).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
