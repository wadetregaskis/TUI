//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationClip.swift
//
//  `navigation`: a field guide in a three-column split view — a category in
//  the sidebar, a species in the list, its page in the detail — and a stack
//  in the detail, pushed into another species of the same habitat (Kestrel
//  to Barn owl, both on farmland) and popped back out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let navigationClip = Clip(
    id: "navigation",
    title: "Navigation",
    columns: 112,
    // As tall as the content: the split view's columns fill the window, and
    // at 30 rows half of every column was empty.
    rows: 18,
    output: 800,
    script: navigationScript(),
    run: { await NavigationApp.main() }
)

private func navigationScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 70, height: 18)), .wait(0.9)]
    // Sidebar: down to Birds (an arrow moves a list's cursor, Space selects);
    // across to the species (past the column divider's collapse toggle, which
    // is a focus stop of its own), two down.
    script += [.down, .wait(0.1), .space, .wait(0.8), .tab, .wait(0.1), .tab, .wait(0.5)]
    script += [.down, .wait(0.1), .space, .wait(0.6), .down, .wait(0.1), .space, .wait(0.7)]
    // The camera drifts right to the detail (and stays: the loop's seam is its
    // cut back); into the species that shares the habitat, and back out.
    script += [.camera(Shot(x: 30, y: 0, width: 70, height: 18, over: 1.2))]
    script += [.tab, .wait(0.1), .tab, .wait(0.9), .enter, .wait(1.4), .escape, .wait(0.9)]
    script += [.backTab, .wait(0.1), .backTab, .wait(0.1), .backTab, .wait(0.1), .backTab, .wait(0.4),
               .up, .wait(0.1), .space, .wait(1.2)]
    return script
}

struct NavigationApp: App {
    var body: some Scene {
        WindowGroup("TUI · Field Guide") {
            FieldGuide()
                .palette(AppleTerminalPalette(.grass))
        }
    }
}

/// A species in the guide.
struct Species: Identifiable, Hashable {
    let id: String
    let latin: String
    let note: String
    var size = "—"
    var lifespan = "—"
    var habitat = "Woodland"
    /// IUCN status: LC, NT, VU, EN.
    var status = "LC"
    /// Sightings this year, of 100.
    var sightings = 40
}

/// The guide: categories, species, a species' page.
struct FieldGuide: View {
    @State private var category: String? = "Mammals"
    @State private var species: String?
    @State private var path: [Species] = []

    private let categories = ["Mammals", "Birds", "Fungi", "Trees"]
    private let guide: [String: [Species]] = [
        "Mammals": [
            Species(id: "Red fox", latin: "Vulpes vulpes", note: "Hunts at dusk; caches food.",
                size: "70 cm", lifespan: "3–4 years", habitat: "Everywhere", sightings: 72),
            Species(id: "Badger", latin: "Meles meles", note: "Lives in setts for generations.",
                size: "80 cm", lifespan: "6 years", habitat: "Woodland edge", sightings: 31),
            Species(id: "Hedgehog", latin: "Erinaceus europaeus", note: "Travels 2 km a night.",
                size: "25 cm", lifespan: "2–5 years", habitat: "Gardens", status: "VU", sightings: 18),
        ],
        "Birds": [
            Species(id: "Puffin", latin: "Fratercula arctica", note: "Carries ten fish at once.",
                size: "30 cm", lifespan: "20 years", habitat: "Sea cliffs", status: "VU", sightings: 26),
            Species(id: "Wren", latin: "Troglodytes troglodytes", note: "Loud for its size.",
                size: "10 cm", lifespan: "2 years", habitat: "Hedgerows", sightings: 88),
            Species(id: "Kestrel", latin: "Falco tinnunculus", note: "Hovers into the wind.",
                size: "35 cm", lifespan: "4 years", habitat: "Farmland", status: "NT", sightings: 47),
            Species(id: "Barn owl", latin: "Tyto alba", note: "Hears a vole under snow.",
                size: "35 cm", lifespan: "4 years", habitat: "Farmland", sightings: 22),
        ],
        "Fungi": [
            Species(id: "Fly agaric", latin: "Amanita muscaria", note: "Red cap, white spots."),
            Species(id: "Chanterelle", latin: "Cantharellus cibarius", note: "Smells of apricots."),
        ],
        "Trees": [
            Species(id: "Silver birch", latin: "Betula pendula", note: "First into new ground."),
            Species(id: "Rowan", latin: "Sorbus aucuparia", note: "Berries for thrushes."),
        ],
    ]

    private var listed: [Species] { guide[category ?? ""] ?? [] }

    var body: some View {
        NavigationSplitView {
            List(categories, id: \.self, selection: $category) { name in
                Text(verbatim: name)
            }
            .navigationTitle("Guide")
        } content: {
            List(listed, selection: $species) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: entry.id)
                    Text(verbatim: entry.latin).italic().foregroundStyle(.palette.foregroundTertiary)
                }
            }
            .navigationTitle(category ?? "")
        } detail: {
            NavigationStack(path: $path) {
                page(for: listed.first { $0.id == species } ?? listed.first)
                    .navigationDestination(for: Species.self) { related in
                        page(for: related)
                    }
            }
        }
        .onChange(of: category) { species = listed.first?.id; path = [] }
    }

    /// Another species of the guide found in the same habitat: what the
    /// page's link pushes, its own page in full.
    private func neighbour(of entry: Species) -> Species? {
        categories.compactMap { guide[$0] }.joined().first { $0.habitat == entry.habitat && $0.id != entry.id }
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
                            .frame(width: 14)
                    }
                }
                .frame(width: 34)
                if let neighbour = neighbour(of: entry) {
                    NavigationLink(value: neighbour) {
                        Text(verbatim: "Same habitat: \(neighbour.id) ›")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 1)
            .navigationTitle(entry.id)
        } else {
            Text(verbatim: "Choose a species").foregroundStyle(.palette.foregroundTertiary)
        }
    }
}
