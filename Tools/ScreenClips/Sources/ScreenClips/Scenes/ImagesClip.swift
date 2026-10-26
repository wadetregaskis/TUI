//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagesClip.swift
//
//  `images` and `glyphs`: a picture viewer, filmed twice. `images` steps
//  through the photos in the terminal's own pixels (Kitty's graphics
//  protocol, in Ghostty); `glyphs` draws one photo in text cells, every way
//  TUI can — half blocks, shape-matched quadrants and corner triangles,
//  Braille, shape-aware ASCII with edge lines, and sixteen colours dithered —
//  for the terminals with no graphics.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let imagesClip = Clip(
    id: "images",
    title: "Images",
    columns: 112,
    rows: 32,
    output: 800,
    script: viewerScript(steps: ImageViewer.photos.count),
    run: { await ImagesApp.main() }
)

@MainActor
let glyphsClip = Clip(
    id: "glyphs",
    title: "Images as text",
    columns: 112,
    rows: 32,
    output: 800,
    script: viewerScript(steps: ImageRendering.allCases.count - 1, cue: "glyphs"),
    run: { await ImagesApp.main() }
)

/// Down the sidebar's list, one every two seconds (an arrow moves the list's
/// cursor, Space selects), and back to the first. `cue` tells the app which
/// viewer it is.
private func viewerScript(steps: Int, cue: String? = nil) -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 84, height: 30))]
    if let cue { script += [.cue(cue)] }
    script += [.wait(2.4)]
    for _ in 1..<steps {
        script += [.down, .wait(0.12), .space, .wait(2.1)]
    }
    script += [.home, .wait(0.12), .space, .wait(0.6)]
    return script
}

struct ImagesApp: App {
    @State private var glyphs = false

    var body: some Scene {
        WindowGroup("TUI · Images") {
            ImageViewer(glyphs: glyphs)
                .palette(AppleTerminalPalette(.pro))
                .task {
                    for await cue in ClipCues.stream() where cue == "glyphs" { glyphs = true }
                }
        }
    }
}

/// The renderings the viewer offers, in the order the clip walks them.
enum ImageRendering: Int, CaseIterable, Identifiable {
    case halfBlocks, shapes, braille, ascii, dithered

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .halfBlocks: "Half blocks ▀▄"
        case .shapes: "Quadrants & triangles ▚◥"
        case .braille: "Braille ⣿⡇"
        case .ascii: "ASCII, edges traced"
        case .dithered: "16 colours, dithered"
        }
    }

    var characterSet: ASCIICharacterSet {
        switch self {
        case .halfBlocks, .shapes, .dithered: .blocks(.fine)
        case .braille: .blocks(.braille)
        case .ascii: .ascii(glyphs: nil)
        }
    }

    var shapeAware: Bool { self == .shapes || self == .ascii }
    var colorMode: ASCIIColorMode { self == .dithered ? .ansi16 : .trueColor }
    var dithering: DitheringMode { self == .dithered ? .floydSteinberg : .none }
    var edgeThreshold: Double? { self == .ascii ? 0.9 : nil }
}

/// A picture viewer, two ways: the photos down the side and the selected one
/// in the terminal's own pixels (Kitty graphics); or one photo, the ways to
/// draw it in text down the side.
struct ImageViewer: View {
    /// The photos the pixel viewer lists, by file and caption.
    static let photos: [(file: String, caption: String)] = [
        ("aurora", "Aurora"), ("harbour-at-dawn", "Harbour at dawn"), ("glacier", "Glacier lagoon"),
        ("night-city", "Night city"), ("dunes", "Dunes"), ("lagoon", "Lagoon"),
    ]

    let glyphs: Bool
    @State private var selection: Int? = 0

    private var rendering: ImageRendering { ImageRendering(rawValue: selection ?? 0) ?? .halfBlocks }
    private var photo: (file: String, caption: String) {
        glyphs ? ("harbour-at-dawn", "Harbour at dawn") : Self.photos[min(selection ?? 0, Self.photos.count - 1)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: glyphs ? "Draw with" : "Iceland, 2026").bold()
                if glyphs {
                    List(ImageRendering.allCases, selection: $selection) { rendering in
                        Text(verbatim: rendering.name)
                    }
                } else {
                    List(Self.photos.indices, id: \.self, selection: $selection) { index in
                        Text(verbatim: Self.photos[index].caption)
                    }
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 0) {
                picture
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 1) {
                    Text(verbatim: "\(photo.file).png").bold()
                    Text(verbatim: "640 × 400 ·").foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: glyphs ? rendering.name : "Kitty graphics")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Preview") }
        }
    }

    @ViewBuilder private var picture: some View {
        if glyphs {
            Image(.file(ClipAssets.photo(photo.file)))
                .resizable()
                .scaledToFit()
                .imageCharacterSet(rendering.characterSet)
                .imageShapeAware(rendering.shapeAware)
                .imageColorMode(rendering.colorMode)
                .imageDithering(rendering.dithering)
                .imageEdgeThreshold(rendering.edgeThreshold)
                .terminalGraphics(false)
        } else {
            Image(.file(ClipAssets.photo(photo.file)))
                .resizable()
                .scaledToFit()
        }
    }
}
