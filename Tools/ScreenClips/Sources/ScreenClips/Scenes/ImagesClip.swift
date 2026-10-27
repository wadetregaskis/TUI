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
/// depths and palettes, dithering and tone curves, each flicked through on the
/// page's own keys (its status bar shows which). The real app, not a scene.
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
    command: ["Example", "--page", "imageFile"],
    environment: ["TUIKIT_GRAPHICS": "0"]
)

/// From fine blocks in true colour: ASCII, then shape matching on (after the
/// cycle has passed the custom ramp, which cannot shape-match and turns it off
/// as it is passed); Unicode and blocks, shape-matched; 256 and 16 colours,
/// dithered, grey; the tone curves; and back to where it began.
private func glyphsScript() -> [Step] {
    func key(_ k: String, _ hold: Double) -> [Step] { [.keys(k), .wait(hold)] }
    var script: [Step] = [.wait(2.0)]
    script += key("c", 0.05) + key("c", 1.6)                   // (custom) ascii
    script += key("s", 1.8)                                    // shape matching
    script += key("c", 1.6) + key("c", 1.4)                    // unicode, blocks
    script += key("m", 1.4) + key("m", 1.4) + key("d", 1.8)    // 256, 16, dithered
    script += key("m", 1.6) + key("d", 0.05)                   // grey, undithered
    script += key("M", 0.05) + key("M", 0.05) + key("M", 1.0)  // back to true colour
    script += key("t", 1.4) + key("t", 1.4) + key("t", 1.8)    // invert, accent, duotone
    script += key("T", 0.05) + key("T", 0.05) + key("T", 0.05) + key("s", 1.2)
    return script
}

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
