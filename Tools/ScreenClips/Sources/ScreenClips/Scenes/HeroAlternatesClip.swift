//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeroAlternatesClip.swift
//
//  The hero's two alternates, kept for rotating into the README: `search`, a
//  list filtered live as a query is typed into `.searchable`'s field, and
//  `todo`, a to-do list whose checked items spring to the bottom. Each is the
//  code the README would show beside it, as it runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let searchClip = Clip(
    id: "search",
    title: "Search",
    columns: 34,
    rows: 14,
    output: 720,
    script: searchScript(),
    run: { await SearchApp.main() }
)

private func searchScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: -0.4, y: -0.2, width: 36.8, height: 14.4)), .wait(1.0)]
    script += Step.type("an", interval: 0.35)
    script += [.wait(1.0)]
    script += Step.type("d", interval: 0.3)
    script += [.wait(1.2)]
    script += Step.repeat(.keys("\u{7F}"), 3, interval: 0.25)  // Backspace, back to everything
    script += [.wait(0.6)]
    script += Step.type("ia", interval: 0.35)
    script += [.wait(1.3)]
    script += Step.repeat(.keys("\u{7F}"), 2, interval: 0.25)
    script += [.wait(0.8)]
    return script
}

struct SearchApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Countries") {
            Countries()
                .palette(LiveTerminalPalette())
        }
    }
}

struct Countries: View {
    @State private var query = ""
    let names = ["Argentina", "Australia", "Canada", "Finland", "Iceland",
                 "India", "Ireland", "Japan", "Kenya", "Netherlands", "New Zealand", "Poland"]

    var body: some View {
        NavigationStack {
            List(names.filter { query.isEmpty || $0.localizedStandardContains(query) }, id: \.self) {
                Text($0)
            }
            .searchable(text: $query)
            .navigationTitle("Countries")
        }
    }
}

@MainActor
let todoClip = Clip(
    id: "todo",
    title: "To do",
    columns: 34,
    rows: 12,
    output: 720,
    script: todoScript(),
    run: { await TodoApp.main() }
)

/// Clicks on the checkboxes (column 3; the list's rows start on row 2): three
/// done, each springing to the bottom, then each undone, back to the start.
private func todoScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: -0.4, y: -0.2, width: 36.8, height: 8.4)), .wait(1.0)]
    for row in [2, 2, 3, 4, 5, 6] {
        script += Step.click(3, row)
        script += [.wait(1.3)]
    }
    return script
}

struct TodoApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · To do") {
            TodoList()
                .palette(LiveTerminalPalette())
        }
    }
}

struct TodoItem: Identifiable, Hashable {
    let id: String
    var done = false
}

struct TodoList: View {
    @State private var items = ["Water the plants", "Call Mum", "Book flights", "Fix the bike", "Return library books"]
        .map { TodoItem(id: $0) }

    var body: some View {
        List {
            ForEach(items.sorted { !$0.done && $1.done }) { item in
                Toggle(item.id, isOn: binding(for: item))
            }
        }
        .animation(.spring(bounce: 0.3), value: items)
    }

    private func binding(for item: TodoItem) -> Binding<Bool> {
        Binding(
            get: { item.done },
            set: { done in
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].done = done }
            })
    }
}
