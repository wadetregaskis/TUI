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
        .camera(Shot(x: 18.6, y: 3.4, width: 76, height: 23)),
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

/// An album of gradient "photos", and the three ways it asks something.
struct PhotoLibrary: View {
    @State private var sharing = false
    @State private var deleting = false
    @State private var showingInfo = false

    private static let photos: [(String, [Color])] = [
        ("Harbour at dawn", [.rgb(255, 140, 90), .rgb(120, 60, 160)]),
        ("Fern", [.rgb(40, 120, 60), .rgb(190, 230, 120)]),
        ("Glacier", [.rgb(200, 240, 255), .rgb(40, 110, 190)]),
        ("Market", [.rgb(250, 200, 60), .rgb(220, 70, 60)]),
        ("Night bus", [.rgb(20, 20, 70), .rgb(230, 90, 200)]),
        ("Dunes", [.rgb(240, 190, 120), .rgb(170, 90, 50)]),
        ("Lagoon", [.rgb(30, 200, 190), .rgb(20, 60, 120)]),
        ("Orchard", [.rgb(250, 230, 200), .rgb(220, 90, 110)]),
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

    /// A photo, its name beneath.
    private func tile(_ photo: (String, [Color]), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: photo.1, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 8)
            Text(verbatim: photo.0).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
