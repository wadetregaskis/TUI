//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagesClip.swift
//
//  `images`: a picture viewer stepping through a library of photos in the
//  terminal's own pixels (Kitty's graphics protocol, in Ghostty). `glyphs`:
//  the Example's image page itself, graphics off, drawing a photo in text
//  cells every way TUI can, for the terminals with no graphics.
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
    rows: 34,
    output: 800,
    // Photographs, and blurs of them: WebP blocks them at the default quality.
    quality: 90,
    budgetKB: 900,
    // The first six: the list is longer than the walk, as a library is.
    script: viewerScript(steps: 6),
    run: { await ImagesApp.main() }
)

/// The Example's own image page, with the terminal's graphics off so the
/// picture is drawn in text cells: the glyph sets, shape matching, colour
/// depths and palettes, dithering and tone curves, each chosen in the page's
/// Inspector. The real app, not a scene.
@MainActor
let glyphsClip = Clip(
    id: "glyphs",
    title: "Images as text",
    columns: 112,
    rows: 34,
    output: 800,
    // Photographs, and blurs of them: WebP blocks them at the default quality.
    quality: 90,
    budgetKB: 900,
    script: glyphsScript(),
    command: ["Example", "--page", "images"],
    // Lil' Mac Guy, the macOS mascot (the owner calls him Lil' Finder Guy):
    // big flat areas and a few clean edges, which each glyph set and palette
    // keeps or loses legibly. Touko Madobe's fine line work was too detailed
    // to read at this size (the owner, 2026-10-29).
    environment: ["TUI_GRAPHICS": "0", "TUI_EXAMPLE_PICTURE": "Lil' Mac Guy"]
)

/// Every change made in the Inspector, from the keyboard, as a user makes it:
/// the focus walks to the control (the pane scrolls to keep it in view), the
/// control changes, and the picture redraws. The status bar's single keys
/// would do the same with nothing in the pane moving, which reads as the
/// settings changing by themselves (the owner, 2026-10-29).
///
/// From fine blocks in true colour, the focus on the render style's options:
/// ASCII, then shape matching on; Unicode and blocks, shape-matched; the tone
/// curves (negative, accent, duotone) and off again; 256 and 16 colours,
/// dithered, greyscale, undithered; true colour; and back up the pane,
/// shape matching off, to where it began.
private func glyphsScript() -> [Step] {
    /// Selects the option `moves` arrows along from the cursor (negative:
    /// up), a beat on each, then holds on the picture it draws.
    func choose(_ moves: Int, hold: Double) -> [Step] {
        Step.repeat(moves < 0 ? .up : .down, abs(moves), interval: 0.3) + [.wait(0.1), .space, .wait(hold)]
    }
    /// Walks the focus `stops` controls on (negative: back), as Tab does.
    func walk(_ stops: Int) -> [Step] {
        Step.repeat(stops < 0 ? .backTab : .tab, abs(stops), interval: 0.24) + [.wait(0.2)]
    }
    // The window but its status bar, which gains ⌃Z Undo with the first
    // change and would jump back where the loop wraps; the Inspector says
    // what is chosen. Its top border runs off the foot, as a border may.
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 112, height: 32)), .wait(1.6)]
    // Characters.
    script += choose(-2, hold: 1.6)                         // ASCII
    script += walk(2) + [.space, .wait(1.8)]                // past its glyph count to Shape-aware: on
    script += walk(-2)                                      // back to the options
    script += choose(1, hold: 1.5)                          // Unicode
    script += choose(1, hold: 1.6)                          // Blocks
    // Tone, down the pane past the sampling and the adjustments.
    script += walk(toneStops)
    script += choose(1, hold: 1.3) + choose(1, hold: 1.3) + choose(1, hold: 1.7)  // negative, accent, duotone
    script += [.home, .wait(0.3), .space, .wait(0.8)]       // off
    // Colour.
    script += walk(1)
    script += choose(1, hold: 1.3) + choose(1, hold: 1.4)   // 256, 16
    script += walk(2) + [.space, .wait(1.7)]                // past Posterize to Dithering: on
    script += walk(-2) + choose(1, hold: 1.6)               // greyscale, dithered
    script += walk(2) + [.space, .wait(1.3)]                // undithered
    script += walk(-2) + [.home, .wait(0.3), .space, .wait(1.0)]  // true colour
    // Back up the pane: shape matching off, and the focus on the options.
    script += walk(-toneStops) + [.space, .wait(1.0)]
    script += walk(-2) + [.wait(0.8)]
    return script
}

/// How many Tab stops lie between the render style's options (Blocks chosen,
/// shape-matched) and the tone's: Shape-aware, Edge contrast, the four
/// adjustments.
private let toneStops = 7

/// Down the sidebar's list, one every two seconds (an arrow moves the list's
/// cursor, Space selects), and back to the first.
private func viewerScript(steps: Int) -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 112, height: 32))]
    script += [.wait(2.4)]
    for _ in 1..<steps {
        script += [.down, .wait(0.12), .space, .wait(2.1)]
    }
    script += [.home, .wait(0.12), .space, .wait(0.6)]
    return script
}

struct ImagesApp: App {
    var body: some Scene {
        WindowGroup("TUI · Images") {
            ImageViewer()
                .palette(AppleTerminalPalette(.pro))
        }
    }
}

/// A picture viewer: the photos down the side, the selected one in the
/// terminal's own pixels (Kitty graphics).
struct ImageViewer: View {
    /// The photos the pixel viewer lists (the owner's, Photos/): file, caption
    /// and size in pixels.
    static let photos: [(file: String, caption: String, size: String)] = [
        ("bald-eagle", "Bald eagle", "720 × 550"), ("galago", "Galago", "720 × 480"),
        ("ground-squirrel", "Ground squirrel", "720 × 494"), ("pigeon-point-lighthouse", "Lighthouse", "668 × 720"),
        ("cedar-waxwings", "Cedar waxwings", "454 × 720"), ("lioness", "Lioness", "720 × 567"),
        ("burrowing-owl", "Burrowing owl", "694 × 720"), ("fawn", "Fawn", "720 × 518"),
        ("forest-path", "Forest path", "720 × 405"), ("pacific-trillium", "Pacific trillium", "720 × 484"),
        ("bee-drinking", "Bee drinking", "720 × 480"), ("banana-slug", "Banana slug", "720 × 523"),
        ("spurred-tortoise", "Spurred tortoise", "720 × 489"), ("salamander", "Salamander", "520 × 720"),
        ("palm-cone", "Palm cone", "720 × 488"), ("snail", "Snail", "720 × 405"),
        ("raisin", "Raisin", "720 × 457"),
    ]

    @State private var selection: Int? = 0

    private var photo: (file: String, caption: String, size: String) {
        Self.photos[min(selection ?? 0, Self.photos.count - 1)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Wildlife").bold()
                List(Self.photos.indices, id: \.self, selection: $selection) { index in
                    Text(verbatim: Self.photos[index].caption)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 0) {
                Image(.file(ClipAssets.photo(photo.file)))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 1) {
                    Text(verbatim: "\(photo.file).webp").bold()
                    Text(verbatim: "\(photo.size) ·").foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: "Kitty graphics").bold().foregroundStyle(.palette.accent)
                }
            }
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Preview") }
        }
    }
}
