//  🖥️ TUI — A Terminal UI framework for Swift
//  MaterialsClip.swift
//
//  `materials`: a photo library driven from the keyboard alone. The focus
//  breathes round one photo at a time while six are picked, a share panel on
//  frosted glass floats over them, and a "Publishing…" toast on another — the
//  library still there, frosted, behind each.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import ImageIO
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
        .camera(Shot(x: 0, y: 3, width: 87, height: 25)),
        // The burrowing owl has the focus. Six photos picked, the top-left three
        // by two the camera shows, snaking: Space picks, an arrow moves on.
        .wait(1.0), .space,
        .wait(0.6), .right, .wait(0.5), .space,
        .wait(0.6), .right, .wait(0.5), .space,
        .wait(0.6), .down, .wait(0.5), .space,
        .wait(0.6), .left, .wait(0.5), .space,
        .wait(0.6), .left, .wait(0.5), .space,
        // Up to the first photo, and back from it to the toolbar's Share…
        // button, the focus ring's stop before it; pressed.
        .wait(0.9), .up,
        .wait(0.7), .backTab,
        .wait(0.8), .enter,
        // The panel opens with its own Share button focused: confirmed. The
        // focus goes back to the burrowing owl, where the loop began.
        .wait(2.4), .enter,
        .wait(2.6), .cue("published"),
        .wait(1.2), .cue("dismiss"),
        .wait(0.5), .cue("deselect"),
        .wait(1.0),
    ],
    run: {
        // Decoded before the app draws, so its first frame has every picture:
        // a file `Image` decodes off the main actor and shows a placeholder
        // until it has, which put a frame of empty tiles at the loop's start.
        _ = materialsAlbum
        await MaterialsApp.main()
    }
)

/// A photo of the album: its picture, decoded, and its caption.
struct AlbumPhoto {
    let picture: CGImage?
    let caption: String
}

/// The album: the owner's photographs (Photos/), by file and caption.
@MainActor
let materialsAlbum: [AlbumPhoto] = [
    ("burrowing-owl", "Burrowing owl"), ("ground-squirrel", "Ground squirrel"),
    ("bald-eagle", "Bald eagle"), ("fawn", "Fawn"),
    ("banana-slug", "Banana slug"), ("cedar-waxwings", "Cedar waxwings"),
    ("lioness", "Lioness"), ("galago", "Galago"),
    ("spurred-tortoise", "Spurred tortoise"), ("salamander", "Salamander"),
    ("snail", "Snail"), ("bee-drinking", "Bee drinking"),
].map { file, caption in
    let url = URL(fileURLWithPath: ClipAssets.photo(file))
    let picture = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
        CGImageSourceCreateImageAtIndex($0, 0, nil)
    }
    return AlbumPhoto(picture: picture, caption: caption)
}

struct MaterialsApp: App {
    var body: some Scene {
        WindowGroup("TUI · Library") {
            PhotoLibrary()
                .palette(AppleTerminalPalette(.novel))
        }
    }
}

/// An album of photos, picked from the keyboard and shared.
struct PhotoLibrary: View {
    /// Where the app puts the keyboard: on a photo, or on the share panel's
    /// own Share button.
    enum Stop: Hashable {
        case photo(Int)
        case confirm
    }

    /// How far a share has got.
    enum Publishing {
        case running, done
    }

    @State private var selection: Set<Int> = []
    /// The photo the arrows last put the focus on, to hand it back to when the
    /// share panel closes.
    @State private var cursor = 0
    @State private var sharing = false
    @State private var publishing: Publishing?
    @FocusState private var focus: Stop?

    private static let columns = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<Self.columns, id: \.self) { column in
                            let index = row * Self.columns + column
                            PhotoTile(photo: materialsAlbum[index], isSelected: selection.contains(index))
                            .focusable()
                            .focused($focus, equals: .photo(index))
                        }
                    }
                }
            }
            // The arrows move in two dimensions, as a grid of photos does: the
            // focus ring alone is a line, where Down is the next photo.
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                move(press.key)
                return .handled
            }
            // Not animated: faded in, the caption's ink crossed its new fill
            // half-way, and the name went out for a frame or two.
            .onKeyPress(.space) {
                if selection.contains(cursor) { selection.remove(cursor) } else { selection.insert(cursor) }
                return .handled
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .defaultFocus($focus, .photo(0))
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Photos") }
        }
        // Floating surfaces, not a sheet or an alert: a modal flattens the page
        // behind it to two colours (`dimmedAsBackdrop`), so there would be no
        // library left to frost.
        // Fades in, but goes at once when answered, as a dialog does: a
        // frosted panel cannot fade out (its blur is a picture, and a
        // terminal's pictures have no alpha), so a fade left the glass until it
        // ended and then took it away in one frame. Its closing shares a frame
        // with the toast's animated arrival, which TUI draws under one
        // transaction (deviation A7), so the closing turns animation off here.
        .overlay(alignment: .topLeading) {
            Group {
                if sharing {
                    sharePanel
                        .offset(x: 24, y: 6)
                        .transition(.opacity)
                }
            }
            .transaction { $0.disablesAnimations = !sharing }
        }
        // Centred in the camera's shot (which starts at the window's left
        // edge and is 87 cells wide), not in the 112-cell window.
        .overlay(alignment: .bottom) {
            if let publishing {
                toast(publishing)
                    .offset(x: -12, y: -5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            for await cue in ClipCues.stream() {
                switch cue {
                // Not animated, as Space's picks are not.
                case "deselect": selection = []
                default:
                    withAnimation(.easeInOut(duration: 0.3)) {
                        publishing = cue == "published" ? .done : nil
                    }
                }
            }
        }
    }

    /// The album's name, what is picked, and what can be done with it.
    private var header: some View {
        HStack(spacing: 2) {
            Text(verbatim: "Wildlife").bold()
            // One Text, its words and colour changed: an `if` of two would
            // cross-fade them, a blank between the two counts.
            Text(verbatim: selection.isEmpty ? "12 photos · 41 MB" : "\(selection.count) of 12 selected")
                .foregroundStyle(selection.isEmpty ? .palette.foregroundSecondary : .palette.accent)
            Spacer()
            Button("Copy") {}
            Button("Share…") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    sharing = true
                    focus = .confirm
                }
            }
            .disabled(selection.isEmpty)
        }
        .frame(width: 81)
    }

    /// The arrow's neighbour of the focused photo, in the grid's rows and
    /// columns; the focus stays put at an edge.
    private func move(_ key: KeyEquivalent) {
        let count = materialsAlbum.count
        var next = cursor
        switch key {
        case .upArrow where cursor >= Self.columns: next -= Self.columns
        case .downArrow where cursor + Self.columns < count: next += Self.columns
        case .leftArrow where cursor % Self.columns > 0: next -= 1
        case .rightArrow where cursor % Self.columns < Self.columns - 1: next += 1
        default: break
        }
        cursor = next
        focus = .photo(next)
    }

    /// The share panel: a floating inspector on frosted glass.
    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "Share \(selection.count) photos").bold()
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("To") { Text(verbatim: "sam@example.com") }
                LabeledContent("Size") { Text(verbatim: "Large · 21 MB") }
                Toggle("Include location", isOn: .constant(true))
            }
            HStack(spacing: 2) {
                Spacer()
                Button("Cancel") { close() }
                Button("Share") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        publishing = .running
                        close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .focused($focus, equals: .confirm)
            }
        }
        .padding(1)
        .frame(width: 40)
        // Behind the border, not inside it: inside, the border's own inset
        // (a cell each side) was left unglazed, the photo plain in it.
        .border()
        .background(.thinMaterial)
    }

    /// Closes the share panel, the focus back on the photo it came from.
    private func close() {
        sharing = false
        focus = .photo(cursor)
    }

    /// What a share is doing, on a toast of frosted glass: a row of room above
    /// and below its line, and two cells either side.
    private func toast(_ publishing: Publishing) -> some View {
        Group {
            switch publishing {
            case .running: Spinner("Publishing \(selection.count) photos…" as String)
            case .done: Text(verbatim: "✓ Published \(selection.count) photos").bold()
            }
        }
        .frame(width: 22)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(.regularMaterial)
    }
}

/// A photo, its caption beneath, in the terminal's own pixels (Kitty's
/// graphics, in Ghostty). A material over it frosts a blurred copy of the
/// picture, which the cells under the glass draw instead.
///
/// Focused, its frame breathes on TUI's focus clock, in step with every other
/// focused thing; picked, it carries a check on the picture and its caption
/// sits on the accent, as a selected row of a list does. The two are apart, as
/// a list's cursor and its selection are: the frame says where the keyboard
/// is, the accent what is picked.
private struct PhotoTile: View {
    let photo: AlbumPhoto
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picture
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 6)
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Text(verbatim: " ✓ ").bold()
                            .foregroundStyle(palette.readableText(on: palette.accent))
                            .background(palette.accent)
                    }
                }
            HStack(spacing: 0) {
                Text(verbatim: photo.caption)
                Spacer(minLength: 0)
                if isSelected { Text(verbatim: "✓").bold() }
            }
            .frame(width: 22)
            .foregroundStyle(isSelected ? palette.readableText(on: palette.accent) : palette.foregroundSecondary)
            .background(isSelected ? palette.accent : palette.background)
        }
        .border(frame)
    }

    private var picture: Image {
        guard let picture = photo.picture else { return Image(systemName: "photo") }
        return Image(decorative: picture, scale: 1)
    }

    /// The frame round the photo, there only while it has the focus: breathing
    /// in the accent, on TUI's own focus clock. Otherwise it is the page's own
    /// colour — there, holding its place, but not seen — so the one frame on
    /// the page is the keyboard's. Its trough is half the accent, not TUI's
    /// usual 20% for a frame: here no resting border is under it, and at 20%
    /// the cursor all but went out once a breath.
    private var frame: AnimatedColor {
        guard isFocused && isFocusEffectEnabled else { return AnimatedColor(palette.background) }
        let ends = palette.accent.breathEnds(dimmedTo: 0.5, over: palette.background)
        return emphasis.animatedColor(true, dim: ends.dim, bright: ends.bright)
    }
}
