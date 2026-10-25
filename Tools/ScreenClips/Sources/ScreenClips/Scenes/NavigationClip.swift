//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationClip.swift
//
//  `navigation`: a field guide in a three-column split view — a category in
//  the sidebar, a species in the list, its page in the detail — and a stack
//  in the detail, pushed into a related species and popped back out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let navigationClip = Clip(
    id: "navigation",
    title: "Navigation",
    columns: 112,
    rows: 30,
    script: navigationScript(),
    run: { await NavigationApp.main() }
)

private func navigationScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0.6, y: 2.6, width: 54, height: 19)), .wait(0.9)]
    // Sidebar: down to Birds (an arrow moves a list's cursor, Space selects);
    // across to the species (past the column divider's collapse toggle, which
    // is a focus stop of its own), two down.
    script += [.down, .wait(0.1), .space, .wait(0.8), .tab, .wait(0.1), .tab, .wait(0.5)]
    script += [.down, .wait(0.1), .space, .wait(0.6), .down, .wait(0.1), .space, .wait(0.7)]
    // The camera drifts right to the detail (and stays: the loop's seam is its
    // cut back); into the related species, and back out.
    script += [.camera(Shot(x: 40, y: 2.6, width: 54, height: 19, over: 1.2))]
    script += [.tab, .wait(0.1), .tab, .wait(0.9), .enter, .wait(1.4), .escape, .wait(0.9)]
    script += [.backTab, .wait(0.1), .backTab, .wait(0.1), .backTab, .wait(0.1), .backTab, .wait(0.4),
               .up, .wait(0.1), .space, .wait(1.2)]
    return script
}

struct NavigationApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Field Guide") {
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
    let related: String
}

/// The guide: categories, species, a species' page.
struct FieldGuide: View {
    @State private var category: String? = "Mammals"
    @State private var species: String?
    @State private var path: [Species] = []

    private let categories = ["Mammals", "Birds", "Fungi", "Trees"]
    private let guide: [String: [Species]] = [
        "Mammals": [
            Species(id: "Red fox", latin: "Vulpes vulpes", note: "Hunts at dusk; caches food.", related: "Arctic fox"),
            Species(id: "Badger", latin: "Meles meles", note: "Lives in setts for generations.", related: "Otter"),
            Species(id: "Hedgehog", latin: "Erinaceus europaeus", note: "Travels 2 km a night.", related: "Mole"),
        ],
        "Birds": [
            Species(id: "Puffin", latin: "Fratercula arctica", note: "Carries ten fish at once.", related: "Razorbill"),
            Species(id: "Wren", latin: "Troglodytes troglodytes", note: "Loud for its size.", related: "Dunnock"),
            Species(id: "Kestrel", latin: "Falco tinnunculus", note: "Hovers into the wind.", related: "Merlin"),
            Species(id: "Barn owl", latin: "Tyto alba", note: "Hears a vole under snow.", related: "Tawny owl"),
        ],
        "Fungi": [
            Species(id: "Fly agaric", latin: "Amanita muscaria", note: "Red cap, white spots.", related: "Panther cap"),
            Species(id: "Chanterelle", latin: "Cantharellus cibarius", note: "Smells of apricots.", related: "Hedgehog fungus"),
        ],
        "Trees": [
            Species(id: "Silver birch", latin: "Betula pendula", note: "First into new ground.", related: "Downy birch"),
            Species(id: "Rowan", latin: "Sorbus aucuparia", note: "Berries for thrushes.", related: "Whitebeam"),
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

    @ViewBuilder private func page(for entry: Species?) -> some View {
        if let entry {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.id).bold()
                Text(verbatim: entry.latin).italic().foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: entry.note)
                NavigationLink(value: Species(id: entry.related, latin: "see also", note: "A relative of the \(entry.id.lowercased()).", related: entry.id)) {
                    Text(verbatim: "Related: \(entry.related) ›")
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
