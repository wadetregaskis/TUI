//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationClip.swift
//
//  `navigation`: a field guide to the owner's photographs in a three-column
//  split view — a category in the sidebar, a species in the list, its page in
//  the detail — and a stack in the detail: the page's photo, clicked, zooms
//  up into a screen of its own (`navigationTransition(.zoom)`), and back
//  folds it down into the page again. All of it by the pointer, which the
//  film draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let navigationClip = Clip(
    id: "navigation",
    title: "Navigation",
    columns: 112,
    rows: 16,
    output: 800,
    // Photographs, and blurs of them: WebP blocks them at the default quality.
    quality: 90,
    budgetKB: 900,
    script: navigationScript(),
    run: { await NavigationApp.main() }
)

/// Where the script's pointer goes, in the terminal's cells (1-based, as a
/// mouse report counts them).
private enum Spot {
    static let birds = (6, 3)
    static let mammals = (6, 2)
    static let eagle = (24, 6)
    /// The thumbnail's middle: its first two columns are the link's focus
    /// marker, which a click there does not activate.
    static let photo = (93, 3)
    /// The page's crumb in the photo screen's trail, "Bald eagle › Photo".
    static let back = (50, 1)
    static let rest = (60, 14)
}

private func navigationScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 112, height: 16)), .point(column: Spot.rest.0, row: Spot.rest.1)]
    script += [.wait(1.0)]
    // To Birds in the sidebar; the list follows with its first bird.
    script += Step.glide(from: Spot.rest, to: Spot.birds, over: 0.6) + [.wait(0.15)]
    script += Step.click(Spot.birds.0, Spot.birds.1) + [.wait(0.9)]
    // A bird in the list, the eagle: its page.
    script += Step.glide(from: Spot.birds, to: Spot.eagle, over: 0.5) + [.wait(0.15)]
    script += Step.click(Spot.eagle.0, Spot.eagle.1) + [.wait(1.0)]
    // Its photo, clicked, zooms up to a screen of its own…
    script += Step.glide(from: Spot.eagle, to: Spot.photo, over: 0.7) + [.wait(0.2)]
    script += Step.click(Spot.photo.0, Spot.photo.1) + [.wait(2.2)]
    // …and its page's crumb, clicked, folds it back down into the page.
    script += Step.glide(from: Spot.photo, to: Spot.back, over: 0.6) + [.wait(0.2)]
    script += Step.click(Spot.back.0, Spot.back.1) + [.wait(1.2)]
    // Back to where it began, for the loop.
    script += Step.glide(from: Spot.back, to: Spot.mammals, over: 0.7) + [.wait(0.15)]
    script += Step.click(Spot.mammals.0, Spot.mammals.1) + [.wait(0.6)]
    script += Step.glide(from: Spot.mammals, to: Spot.rest, over: 0.6) + [.wait(0.4)]
    return script
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
            .navigationSplitViewColumnWidth(30)
        } detail: {
            NavigationStack(path: $path) {
                page(for: listed.first { $0.id == species } ?? listed.first)
                    .navigationDestination(for: Species.self) { entry in
                        photoScreen(entry)
                    }
            }
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

    @ViewBuilder private func page(for entry: Species?) -> some View {
        if let entry {
            HStack(alignment: .top, spacing: 2) {
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
                    .frame(width: 30)
                }
                NavigationLink(value: entry) {
                    Image(.file(ClipAssets.photo(entry.photo)))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 6, alignment: .topLeading)
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .matchedTransitionSource(id: entry.id, in: zoom)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 1)
            .navigationTitle(entry.id)
        } else {
            Text(verbatim: "Choose a species").foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// A species' photo on a screen of its own, zoomed up from its page.
    private func photoScreen(_ entry: Species) -> some View {
        GrowingPhoto(entry: entry)
            .padding(.horizontal, 1)
            .navigationTitle("Photo")
            .navigationTransition(.zoom(sourceID: entry.id, in: zoom))
    }
}

/// A species' photo that grows, as its screen zooms in, from the size and place
/// of the thumbnail it was opened from to as large as the column lets it be:
/// the zoom reveals the screen through a growing rectangle, and the photo
/// grows with it, on the same curve (`.default`), so it reads as the
/// thumbnail scaling up.
struct GrowingPhoto: View {
    let entry: Species
    @State private var grown = false

    /// The thumbnail's frame on the species' page, and its column there: past
    /// the facts (30) and the gap beside them (2).
    private static let thumbnail = (width: 16, height: 6, x: 32)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.file(ClipAssets.photo(entry.photo)))
                .resizable()
                .scaledToFit()
                .frame(
                    width: grown ? 62 : Self.thumbnail.width, height: grown ? 12 : Self.thumbnail.height,
                    alignment: grown ? .center : .topLeading)
                .offset(x: grown ? 0 : Self.thumbnail.x)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(verbatim: "\(entry.photo).webp").foregroundStyle(.palette.foregroundSecondary)
        }
        .onAppear { withAnimation(.default) { grown = true } }
    }
}
