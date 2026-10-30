//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationClip.swift
//
//  `navigation`: a field guide to the owner's photographs in a three-column
//  split view — a category in the sidebar, a species in the list, its page in
//  the detail, the rest of its category in photos below — and a stack in the
//  detail: the page's photo, clicked, zooms up into a screen of its own
//  (`navigationTransition(.zoom)`); the species list's divider is dragged to
//  give the photo more room, the two leading columns are hidden by their ◀
//  until the photo nearly fills the window, and brought back by the ▶; and the
//  page's crumb folds the photo back down into its thumbnail. All of it by the
//  pointer, which the film draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let navigationClip = Clip(
    id: "navigation",
    title: "Navigation",
    // Ghostty opens this as 108 × 31, which the layout is measured against
    // (``FieldGuide/thumbnail(_:)``) and the camera frames whole: 16:10.
    columns: 106,
    rows: 30,
    output: 800,
    // Photographs, and blurs of them: WebP blocks them at the default quality.
    quality: 90,
    budgetKB: 900,
    script: navigationScript(),
    run: { await NavigationApp.main() }
)

/// Where the script's pointer goes, in the terminal's cells (1-based, as a
/// mouse report counts them). The grid is 108 × 31 (Ghostty opens the 106 ×
/// 30 window a little larger): the sidebar is columns 1–14 and its divider 15;
/// the species list 16–50 and its divider 51, until a drag moves it; the
/// detail, 57 wide, the rest.
private enum Spot {
    static let birds = (6, 3)
    static let mammals = (6, 2)
    static let eagle = (24, 6)
    /// The thumbnail's middle: the link's focus marker is the two columns
    /// before it, which a click does not activate.
    static let photo = (94, 6)
    /// The page's crumb in the photo screen's trail, "Bald eagle › Photo".
    static let back = (56, 1)
    /// The species list's divider, where the drag takes it, and back: ten
    /// columns of the list given to the photo.
    static let divider = (51, 22)
    static let dragged = (41, 22)
    /// The ◀ on the leftmost divider, on its middle row: the sidebar's, and
    /// once that has gone, the species list's (the list then starts at
    /// column 2, after the ▶ edge column, and is twenty-five wide).
    static let hideSidebar = (15, 16)
    static let hideList = (27, 16)
    /// The ▶ edge column, which brings them back, one at a time.
    static let reveal = (1, 16)
    static let rest = (64, 14)
}

private func navigationScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 108, height: 31)), .point(column: Spot.rest.0, row: Spot.rest.1)]
    script += [.wait(0.8)]
    // To Birds in the sidebar; the list follows with its first bird.
    script += Step.glide(from: Spot.rest, to: Spot.birds, over: 0.6) + [.wait(0.15)]
    script += Step.click(Spot.birds.0, Spot.birds.1) + [.wait(0.7)]
    // A bird in the list, the eagle: its page.
    script += Step.glide(from: Spot.birds, to: Spot.eagle, over: 0.5) + [.wait(0.15)]
    script += Step.click(Spot.eagle.0, Spot.eagle.1) + [.wait(0.8)]
    // Its photo, clicked, zooms up from the thumbnail to a screen of its own.
    script += Step.glide(from: Spot.eagle, to: Spot.photo, over: 0.6) + [.wait(0.2)]
    script += Step.click(Spot.photo.0, Spot.photo.1) + [.wait(1.5)]
    // The species list's divider dragged left: the photo takes its room.
    script += Step.glide(from: Spot.photo, to: Spot.divider, over: 0.6) + [.wait(0.15)]
    script += divide(from: Spot.divider, to: Spot.dragged) + [.wait(0.5)]
    // The leading columns hidden, the sidebar's ◀ and then the list's: the
    // photo nearly fills the window.
    script += move(from: Spot.dragged, to: Spot.hideSidebar, over: 0.5) + [.wait(0.15)]
    script += Step.click(Spot.hideSidebar.0, Spot.hideSidebar.1) + [.wait(0.5)]
    script += Step.glide(from: Spot.hideSidebar, to: Spot.hideList, over: 0.3) + [.wait(0.15)]
    script += Step.click(Spot.hideList.0, Spot.hideList.1) + [.wait(1.2)]
    // And brought back by the ▶ edge column, the list, then the sidebar…
    script += Step.glide(from: Spot.hideList, to: Spot.reveal, over: 0.5) + [.wait(0.15)]
    script += Step.click(Spot.reveal.0, Spot.reveal.1) + [.wait(0.5)]
    script += Step.click(Spot.reveal.0, Spot.reveal.1) + [.wait(0.6)]
    // …and the list's divider dragged back where it was.
    script += Step.glide(from: Spot.reveal, to: Spot.dragged, over: 0.6) + [.wait(0.15)]
    script += divide(from: Spot.dragged, to: Spot.divider) + [.wait(0.5)]
    // The page's crumb, clicked, folds the photo back down into its thumbnail.
    script += move(from: Spot.divider, to: Spot.back, over: 0.5) + [.wait(0.15)]
    script += Step.click(Spot.back.0, Spot.back.1) + [.wait(1.0)]
    // Back to where it began, for the loop.
    script += Step.glide(from: Spot.back, to: Spot.mammals, over: 0.7) + [.wait(0.15)]
    script += Step.click(Spot.mammals.0, Spot.mammals.1) + [.wait(0.6)]
    // Held until the sidebar's focus breath, which restarts as the click moves
    // the focus, is where it was on the first frame (an 800 ms breath).
    script += move(from: Spot.mammals, to: Spot.rest, over: 0.6) + [.wait(0.75)]
    return script
}

/// The pointer glided as ``Step/glide(from:to:over:)`` glides it, and the app
/// told: a motion report (no button, 32 + 3) at its first cell and its last.
/// A glide alone moves only the drawn pointer, so a divider let go of went on
/// pulsing its hover after the pointer had left it, to the end of the film —
/// whose first frame has nothing hovered, so the loop jumped.
private func move(from start: (Int, Int), to end: (Int, Int), over seconds: Double) -> [Step] {
    var steps = Step.glide(from: start, to: end, over: seconds)
    if case .point(let column, let row) = steps.first { steps.insert(Step.mouse(35, column, row), at: 1) }
    return steps + [Step.mouse(35, end.0, end.1)]
}

/// A divider dragged along its row, two columns a report, as a quick hand
/// moves it: every report reflows the photo beside it, which is a whole new
/// picture of it in the film, so half as many reports is half the bytes.
private func divide(from start: (Int, Int), to end: (Int, Int)) -> [Step] {
    let step = end.0 > start.0 ? 2 : -2
    var steps: [Step] = [Step.mouse(0, start.0, start.1), .wait(0.15)]
    for column in stride(from: start.0 + step, through: end.0, by: step) {
        steps += [Step.mouse(32, column, start.1), .wait(0.08)]
    }
    return steps + [.wait(0.15), Step.mouse(0, end.0, end.1, release: true)]
}

struct NavigationApp: App {
    var body: some Scene {
        WindowGroup("TUI · Field Guide") {
            FieldGuide()
                .palette(AppleTerminalPalette(.pro))
                .tint(.rgb(143, 170, 120))
        }
    }
}

/// A species in the guide, with the owner's photograph of it (Photos/).
struct Species: Identifiable, Hashable {
    let id: String
    let latin: String
    let photo: String
    let note: String
    var size = "—"
    var lifespan = "—"
    var habitat = "Woodland"
    /// IUCN status: LC, NT, VU, EN.
    var status = "LC"
    /// Sightings this year, of 100.
    var sightings = 40
}

/// The guide: categories, species, a species' page, and its photo.
struct FieldGuide: View {
    @State private var category: String? = "Mammals"
    @State private var species: String? = "Galago"
    @State private var path: [Species] = []
    /// Where a species' photo screen zooms from: the photo on its page.
    @Namespace private var zoom

    private let categories = ["Mammals", "Birds", "Others", "Plants"]
    private let guide: [String: [Species]] = [
        "Mammals": [
            Species(id: "Galago", latin: "Galago senegalensis", photo: "galago",
                note: "Leaps 2 m from a standstill.", size: "16 cm", lifespan: "10 years",
                habitat: "Savanna", sightings: 12),
            Species(id: "Lion", latin: "Panthera leo", photo: "lioness",
                note: "The lionesses hunt together.", size: "2.5 m", lifespan: "14 years",
                habitat: "Grassland", status: "VU", sightings: 6),
            Species(id: "Black-tailed deer", latin: "Odocoileus hemionus", photo: "fawn",
                note: "A fawn lies still, and has no scent.", size: "1.5 m", lifespan: "10 years",
                habitat: "Woodland edge", sightings: 64),
            Species(id: "Ground squirrel", latin: "Otospermophilus beecheyi", photo: "ground-squirrel",
                note: "Its old burrows house owls.", size: "45 cm", lifespan: "6 years",
                habitat: "Grassland", sightings: 81),
        ],
        "Birds": [
            Species(id: "Burrowing owl", latin: "Athene cunicularia", photo: "burrowing-owl",
                note: "Hunts by day, from a burrow.", size: "24 cm", lifespan: "8 years",
                habitat: "Grassland", sightings: 23),
            Species(id: "Cedar waxwing", latin: "Bombycilla cedrorum", photo: "cedar-waxwings",
                note: "Passes berries down the line.", size: "16 cm", lifespan: "7 years",
                habitat: "Orchards", sightings: 47),
            Species(id: "Bald eagle", latin: "Haliaeetus leucocephalus", photo: "bald-eagle",
                note: "Builds the largest nests of any bird.", size: "90 cm", lifespan: "20 years",
                habitat: "Coasts and lakes", sightings: 9),
        ],
        "Others": [
            Species(id: "Banana slug", latin: "Ariolimax columbianus", photo: "banana-slug",
                note: "Eats the forest floor's litter.", size: "20 cm", lifespan: "7 years",
                habitat: "Redwood forest", sightings: 58),
            Species(id: "Spurred tortoise", latin: "Centrochelys sulcata", photo: "spurred-tortoise",
                note: "Digs burrows 3 m deep.", size: "80 cm", lifespan: "70 years",
                habitat: "Sahel", status: "EN", sightings: 3),
            Species(id: "Honey bee", latin: "Apis mellifera", photo: "bee-drinking",
                note: "Carries water home to cool the hive.", size: "1.5 cm", lifespan: "6 weeks",
                habitat: "Everywhere", sightings: 95),
        ],
        "Plants": [
            Species(id: "Pacific trillium", latin: "Trillium ovatum", photo: "pacific-trillium",
                note: "Ants carry its seeds away.", size: "40 cm", lifespan: "25 years",
                habitat: "Redwood forest", sightings: 35),
        ],
    ]

    private var listed: [Species] { guide[category ?? ""] ?? [] }

    /// The photo zooming up from its thumbnail, and folding back into it.
    private static let zoomUp = Animation.easeInOut(duration: 0.6).delay(0.75)
    private static let fold = Animation.easeInOut(duration: 0.6)

    var body: some View {
        NavigationSplitView {
            List(categories, id: \.self, selection: $category) { name in
                Text(verbatim: name)
            }
            .navigationTitle("Guide")
            .navigationSplitViewColumnWidth(14)
        } content: {
            List(listed, selection: $species) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: entry.id)
                    Text(verbatim: entry.latin).italic().foregroundStyle(.palette.foregroundTertiary)
                }
            }
            .navigationTitle(category ?? "")
            // Thirty-five wide, which leaves the detail 57 (``thumbnail(_:)``
            // says why 57), and the person may drag it narrower or wider.
            .navigationSplitViewColumnWidth(min: 16, ideal: 35, max: 40)
        } detail: {
            NavigationStack(path: $path) {
                page(for: listed.first { $0.id == species } ?? listed.first)
                    .navigationDestination(for: Species.self) { entry in
                        photoScreen(entry)
                    }
            }
            // The zoom, both ways, eased: without an animation of its own a
            // push springs, and a spring's long tail held the photo still at
            // the thumbnail's size before it jumped. The way up waits first
            // for the photo screen's first frame, which sends the terminal
            // the photo at its own 720 × 550 (two thirds of a second, here):
            // the zoom's clock starts on that frame, and without the wait the
            // frame after it found the zoom mostly over.
            .animation(path.isEmpty ? Self.fold : Self.zoomUp, value: path)
        }
        .onChange(of: category) { species = listed.first?.id; path = [] }
        .onChange(of: species) { path = [] }
    }

    /// Least concern green, near threatened amber, vulnerable and worse red.
    private func statusColour(_ status: String) -> Color {
        switch status {
        case "LC": .palette.success
        case "NT": .palette.warning
        default: .palette.error
        }
    }

    private func statusName(_ status: String) -> String {
        ["LC": "Least concern", "NT": "Near threatened", "VU": "Vulnerable", "EN": "Endangered"][status] ?? status
    }

    @ViewBuilder private func page(for entry: Species?) -> some View {
        if let entry {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 2) {
                    facts(entry)
                    NavigationLink(value: entry) {
                        thumbnail(entry)
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                Text(verbatim: "\(statusName(entry.status)) (IUCN); seen \(entry.sightings) times this year.")
                    .foregroundStyle(.palette.foregroundSecondary)
                    .frame(width: 56, alignment: .leading)
                relatives(of: entry)
            }
            .padding(.leading, 1)
            .navigationTitle(entry.id)
        } else {
            Text(verbatim: "Choose a species").foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// A species' photo on its page, where its photo screen zooms from.
    ///
    /// The zoom draws the photo screen's picture moved and scaled from the
    /// transition source's frame to its own, and the rest of the screen cut,
    /// not scaled, by the zoom's rectangle. So the source is the picture
    /// itself, 28 × 10 (the photo's own aspect, 28 columns wide), not the
    /// frame round it: marked on the 28 × 15 frame and its padding, the zoom
    /// started with the photo fitted to all fifteen rows, a row and a half
    /// below the thumbnail, which it jumped to the instant it was clicked, and
    /// it folded back into that place too (2026-10-29).
    ///
    /// The stack is 57 × 31 (the film's grid is 108 × 31: Ghostty opens the
    /// 106 × 30 window a little larger), and its photo, as wide as the screen,
    /// is 57 × 20 under the two-row bar: the one box near this size whose
    /// pixels are the photo's own, 720 × 550. What the photo screen sends
    /// first is then enough for every box it grows to as the columns are
    /// dragged and hidden, which the terminal is given as placements alone. A
    /// box whose pixels came out a little wider was sent again, the photo
    /// blank meanwhile.
    private func thumbnail(_ entry: Species) -> some View {
        Image(.file(ClipAssets.photo(entry.photo)))
            .resizable()
            .scaledToFit()
            .matchedTransitionSource(id: entry.id, in: zoom)
            .frame(width: 28, height: 14, alignment: .topLeading)
            .padding(.top, 1)
    }

    /// A species' name, status, note and figures.
    private func facts(_ entry: Species) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text(verbatim: entry.id).bold()
                    Text(verbatim: " \(entry.status) ")
                        .foregroundStyle(.palette.background)
                        .background(statusColour(entry.status))
                }
                Text(verbatim: entry.latin).italic().foregroundStyle(.palette.foregroundSecondary)
            }
            Text(verbatim: entry.note)
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("Size", value: entry.size)
                LabeledContent("Lifespan", value: entry.lifespan)
                LabeledContent("Habitat", value: entry.habitat)
                LabeledContent("Seen") {
                    ProgressView(value: Double(entry.sightings), total: 100)
                        .frame(width: 12)
                }
            }
        }
        .frame(width: 24, alignment: .leading)
    }

    /// The rest of the species' category, a photo each: a click opens its page.
    private func relatives(of entry: Species) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Also in \(category ?? "the guide")").foregroundStyle(.palette.foregroundSecondary)
            HStack(alignment: .top, spacing: 2) {
                ForEach(listed.filter { $0.id != entry.id }.prefix(3)) { other in
                    Button {
                        species = other.id
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Image(.file(ClipAssets.photo(other.photo)))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 6, alignment: .topLeading)
                            Text(verbatim: other.id).lineLimit(1).frame(width: 15, alignment: .leading)
                        }
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
            }
        }
    }

    /// A species' photo on a screen of its own, zoomed up from its page: the
    /// zoom scales and moves the photo with its rectangle, from the
    /// thumbnail's size and place, and folds it back the same way. The photo
    /// is as wide as the screen and starts right under its bar, which is what
    /// lands it on the thumbnail (``thumbnail(_:)``); as the columns beside it
    /// are dragged narrower or hidden, it grows with the room.
    private func photoScreen(_ entry: Species) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.file(ClipAssets.photo(entry.photo)))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text(verbatim: "\(entry.photo).webp · \(entry.latin)")
                .italic()
                .foregroundStyle(.palette.foregroundSecondary)
                .lineLimit(1)
                .padding(.horizontal, 1)
        }
        .navigationTitle("Photo")
        .navigationTransition(.zoom(sourceID: entry.id, in: zoom))
    }
}
