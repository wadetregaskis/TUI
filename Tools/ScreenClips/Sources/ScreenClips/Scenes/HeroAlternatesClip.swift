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

import Foundation
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
    columns: 48,
    rows: 16,
    output: 720,
    script: todoScript(),
    run: { await TodoApp.main() }
)

/// Clicks on the checkboxes: four done, each with a burst of confetti and a
/// glide to the bottom of the list, then all undone from the keyboard, back
/// to the start. The checkboxes are in column 4 and the list's first row is
/// the screen's fourth (1-based, as a mouse report counts).
private func todoScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 48, height: 13)), .wait(1.0)]
    for _ in 0..<4 {
        script += Step.click(4, 4)
        script += [.wait(1.4)]
    }
    script += [.cue("reset"), .wait(1.2)]
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
    let due: String
    var done = false
}

/// A burst of confetti: where, and when it went off.
struct ConfettiBurst: Identifiable {
    let id: Int
    let row: Int
    let start: Date
}

struct TodoList: View {
    private static let start = [
        TodoItem(id: "Water the plants", due: "today"), TodoItem(id: "Call Mum", due: "today"),
        TodoItem(id: "Book flights to Lisbon", due: "Fri"), TodoItem(id: "Fix the bike's brakes", due: "Sat"),
        TodoItem(id: "Return library books", due: "Sat"), TodoItem(id: "Renew passport", due: "Nov"),
        TodoItem(id: "Plan Sam's birthday", due: "Dec"),
    ]
    @State private var items = Self.start
    @State private var bursts: [ConfettiBurst] = []
    @State private var burstCount = 0

    private var ordered: [TodoItem] { items.filter { !$0.done } + items.filter(\.done) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text(verbatim: "Saturday").bold()
                Text(verbatim: "· \(items.filter(\.done).count) of \(items.count) done")
                    .foregroundStyle(.palette.foregroundSecondary)
                ProgressView(value: Double(items.filter(\.done).count), total: Double(items.count))
                    .frame(width: 12)
            }
            .padding(.horizontal, 1)
            ZStack(alignment: .topLeading) {
                List {
                    ForEach(ordered) { item in
                        HStack(spacing: 1) {
                            Toggle(isOn: binding(for: item)) {
                                Text(verbatim: item.id)
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? .palette.foregroundTertiary : .palette.foreground)
                            }
                            Spacer()
                            Text(verbatim: item.due).foregroundStyle(.palette.foregroundTertiary)
                        }
                    }
                }
                TimelineView(.animation) { context in
                    Confetti(bursts: bursts, now: context.date)
                }
            }
            .frame(width: 46, height: 10)
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            for await cue in ClipCues.stream() where cue == "reset" {
                withAnimation(.spring(bounce: 0.3)) { items = Self.start }
            }
        }
    }

    private func binding(for item: TodoItem) -> Binding<Bool> {
        Binding(
            get: { item.done },
            set: { done in
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                if done, let row = ordered.firstIndex(where: { $0.id == item.id }) {
                    burstCount += 1
                    bursts = bursts.filter { Date().timeIntervalSince($0.start) < 1.2 }
                        + [ConfettiBurst(id: burstCount, row: row, start: Date())]
                }
                withAnimation(.spring(bounce: 0.3)) { items[index].done = done }
            })
    }
}

/// Confetti: each burst throws a dozen pieces out from its row's checkbox,
/// which fall a little and fade as they go.
struct Confetti: View {
    let bursts: [ConfettiBurst]
    let now: Date

    private static let pieces: [Character] = ["✦", "•", "◆", "★", "▪", "✧"]
    private static let colours: [Color] = [
        .rgb(255, 90, 90), .rgb(255, 200, 60), .rgb(90, 220, 120), .rgb(80, 170, 255), .rgb(200, 120, 255),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bursts) { burst in
                let age = now.timeIntervalSince(burst.start)
                if age >= 0, age < 1.0 {
                    ForEach(0..<12, id: \.self) { index in
                        piece(index, of: burst, age: age)
                    }
                }
            }
        }
    }

    /// One piece of `burst`, `age` seconds after it went off: thrown out along
    /// its own angle, falling as it goes, fading.
    private func piece(_ index: Int, of burst: ConfettiBurst, age: Double) -> some View {
        let angle = Double(index) / 12 * 2 * Double.pi + Double(burst.id)
        let speed = 9 + Double(index % 3) * 4
        let x = 3 + Int((cos(angle) * speed * age).rounded())
        let y = burst.row + Int((sin(angle) * speed * 0.35 * age + 4 * age * age).rounded())
        return Text(verbatim: String(Self.pieces[(index + burst.id) % Self.pieces.count]))
            .foregroundStyle(Self.colours[(index * 7 + burst.id) % Self.colours.count])
            .opacity(1 - age)
            .offset(x: x, y: y)
    }
}
