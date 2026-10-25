//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImagesClip.swift
//
//  `images`: one picture through both of TUIkit's renderers — the terminal's
//  own graphics (Kitty's protocol: real pixels, in Ghostty), then text cells:
//  half blocks, shape-matched quadrants and corner triangles, Braille,
//  shape-aware ASCII with edge lines, and sixteen colours dithered.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

@MainActor
let imagesClip = Clip(
    id: "images",
    title: "Images",
    columns: 112,
    rows: 32,
    output: 800,
    script: imagesScript(),
    run: { await ImagesApp.main() }
)

/// Down the list of renderings, one every two seconds (an arrow moves the
/// list's cursor, Space selects), and back to the first.
private func imagesScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 27.6, y: 3.6, width: 66, height: 28.4)), .wait(2.4)]
    for _ in 1..<ImageRendering.allCases.count {
        script += [.down, .wait(0.12), .space, .wait(2.1)]
    }
    script += [.home, .wait(0.12), .space, .wait(0.6)]
    return script
}

struct ImagesApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Images") {
            ImageViewer()
                .palette(AppleTerminalPalette(.pro))
        }
    }
}

/// The renderings the viewer offers, in the order the clip walks them.
enum ImageRendering: Int, CaseIterable, Identifiable {
    case graphics, halfBlocks, shapes, braille, ascii, dithered

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .graphics: "Pixels (Kitty graphics)"
        case .halfBlocks: "Half blocks ▀▄"
        case .shapes: "Quadrants & triangles ▚◥"
        case .braille: "Braille ⣿⡇"
        case .ascii: "ASCII, edges traced"
        case .dithered: "16 colours, dithered"
        }
    }

    var characterSet: ASCIICharacterSet {
        switch self {
        case .graphics, .halfBlocks, .shapes, .dithered: .blocks(.fine)
        case .braille: .blocks(.braille)
        case .ascii: .ascii(glyphs: nil)
        }
    }

    var shapeAware: Bool { self == .shapes || self == .ascii }
    var colorMode: ASCIIColorMode { self == .dithered ? .ansi16 : .trueColor }
    var dithering: DitheringMode { self == .dithered ? .floydSteinberg : .none }
    var edgeThreshold: Double? { self == .ascii ? 0.9 : nil }
}

/// A picture viewer: the renderings down the side, the picture beside them,
/// what it is drawn with along the bottom.
struct ImageViewer: View {
    @State private var selection: Int? = 0

    /// The picture: the project's own logo, staged beside the player.
    private let path: String = {
        let directory = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .deletingLastPathComponent()
        return directory.appendingPathComponent("tuikit-logo.png").path
    }()

    private var rendering: ImageRendering { ImageRendering(rawValue: selection ?? 0) ?? .graphics }

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Render as").bold()
                List(ImageRendering.allCases, selection: $selection) { rendering in
                    Text(verbatim: rendering.name)
                }
            }
            .frame(width: 30)

            VStack(alignment: .center, spacing: 0) {
                Image(.file(path))
                    .resizable()
                    .scaledToFit()
                    .imageCharacterSet(rendering.characterSet)
                    .imageShapeAware(rendering.shapeAware)
                    .imageColorMode(rendering.colorMode)
                    .imageDithering(rendering.dithering)
                    .imageEdgeThreshold(rendering.edgeThreshold)
                    .terminalGraphics(rendering == .graphics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 1) {
                    Spinner(style: .dots)
                    Text(verbatim: "tuikit-logo.png").bold()
                    Text(verbatim: "1024 × 1024 ·")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: rendering.name)
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
}
