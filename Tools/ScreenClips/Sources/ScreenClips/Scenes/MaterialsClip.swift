//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MaterialsClip.swift
//
//  `materials`: a photo library, and what it presents over itself — a sheet
//  on frosted glass, an alert, a popover — the library still there, frosted,
//  behind each.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let materialsClip = Clip(
    id: "materials",
    title: "Materials",
    columns: 112,
    rows: 30,
    output: 800,
    script: [
        .camera(Shot(x: 0, y: 3, width: 76, height: 22)),
        .wait(1.2), .cue("sheet"),
        .wait(2.6), .cue("dismiss"),
        .wait(0.9), .cue("alert"),
        .wait(2.4), .cue("dismiss"),
        .wait(0.9), .cue("popover"),
        .wait(2.4), .cue("dismiss"),
        .wait(1.0),
    ],
    run: { await MaterialsApp.main() }
)

struct MaterialsApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Library") {
            PhotoLibrary()
                .palette(AppleTerminalPalette(.novel))
        }
    }
}

/// An album of photos, and the three ways it asks something.
struct PhotoLibrary: View {
    @State private var sharing = false
    @State private var deleting = false
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
                Button("Delete") { deleting = true }
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
        .sheet(isPresented: $sharing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Share 8 photos").bold()
                LabeledContent("To") { Text(verbatim: "kristín@example.is") }
                LabeledContent("Size") { Text(verbatim: "Large · 214 MB") }
                Toggle("Include location", isOn: .constant(true))
                HStack(spacing: 2) {
                    Spacer()
                    Button("Cancel") { sharing = false }
                    Button("Share") { sharing = false }.buttonStyle(.borderedProminent)
                }
            }
            .padding(1)
            .frame(width: 44)
            .presentationBackground(.thinMaterial)
        }
        .alert("Delete 8 photos?", isPresented: $deleting) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "They stay in Recently Deleted for 30 days.")
        }
        .task {
            for await cue in ClipCues.stream() {
                switch cue {
                case "sheet": sharing = true
                case "alert": deleting = true
                case "popover": showingInfo = true
                default: sharing = false; deleting = false; showingInfo = false
                }
            }
        }
    }

    /// A photo, its caption beneath. Drawn in text cells (half blocks), not
    /// the terminal's graphics: a sheet's frost blurs what is beneath it cell
    /// by cell, and a picture the terminal draws itself is not in the cells.
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
