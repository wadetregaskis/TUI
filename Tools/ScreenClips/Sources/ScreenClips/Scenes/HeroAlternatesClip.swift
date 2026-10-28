//  🖥️ TUI — A Terminal UI framework for Swift
//  HeroAlternatesClip.swift
//
//  A hero alternate, kept for rotating into the README: `todo`, a to-do list
//  whose checked items, once their confetti has gone, walk to the bottom a row
//  at a time, the code the README would show beside it, as it runs. (Search, once its own clip, is in `tables` now.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

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

/// Clicks on the checkboxes: four done, each with a burst of confetti and,
/// once it has settled, a walk to the bottom of the list a row at a time; then
/// all undone, back to the start. The checkboxes are in column 4 and the list's
/// first row is the screen's fourth (1-based, as a mouse report counts).
@MainActor
private func todoScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 48, height: 13)), .wait(1.0)]
    for done in 0..<4 {
        script += Step.click(4, 4)
        // The confetti, then a row's step for each item still to do below it.
        script += [.wait(TodoList.confettiSeconds + Double(TodoList.start.count - 1 - done) * TodoList.stepSeconds + 0.5)]
    }
    script += [.cue("reset"), .wait(1.2)]
    return script
}

struct TodoApp: App {
    var body: some Scene {
        WindowGroup("TUI · To do") {
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
    /// How long a burst of confetti lasts before its row moves.
    static let confettiSeconds = 1.0
    /// How long the row takes over each step down the list.
    static let stepSeconds = 0.22

    static let start = [
        TodoItem(id: "Water the plants", due: "today"), TodoItem(id: "Call Mum", due: "today"),
        TodoItem(id: "Book flights to Lisbon", due: "Fri"), TodoItem(id: "Fix the bike's brakes", due: "Sat"),
        TodoItem(id: "Return library books", due: "Sat"), TodoItem(id: "Renew passport", due: "Nov"),
        TodoItem(id: "Plan Sam's birthday", due: "Dec"), TodoItem(id: "Clear the gutters", due: "Dec"),
        TodoItem(id: "Write the holiday cards", due: "Dec"),
    ]
    @State private var items = Self.start
    /// The list's order, by id: an item checked keeps its place until its
    /// confetti has gone, then walks down a row at a time.
    @State private var order = Self.start.map(\.id)
    @State private var bursts: [ConfettiBurst] = []
    @State private var burstCount = 0

    private var ordered: [TodoItem] { order.compactMap { id in items.first { $0.id == id } } }

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
            // The whole of the shot: as wide as the camera, and as tall as the
            // rows below the header, a list exactly as long as its items.
            .frame(width: 48, height: 11)
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            for await cue in ClipCues.stream() where cue == "reset" {
                withAnimation(.spring(bounce: 0.3)) {
                    items = Self.start
                    order = Self.start.map(\.id)
                }
            }
        }
    }

    private func binding(for item: TodoItem) -> Binding<Bool> {
        Binding(
            get: { item.done },
            set: { done in
                guard let index = items.firstIndex(where: { $0.id == item.id }),
                    let row = ordered.firstIndex(where: { $0.id == item.id })
                else { return }
                // Long enough to see the strikethrough drawn along the title,
                // left to right, as TUI draws one changed under an animation.
                withAnimation(.easeInOut(duration: 0.5)) { items[index].done = done }
                if done {
                    burstCount += 1
                    bursts = bursts.filter { Date().timeIntervalSince($0.start) < 1.2 }
                        + [ConfettiBurst(id: burstCount, row: row, start: Date())]
                }
                guard done else { return }
                Task { await walkDown(item.id) }
            })
    }

    /// Moves `id` down the list a row at a time, once its confetti has gone,
    /// until no item still to do is below it: contiguous movement the eye can
    /// follow, where one spring to the bottom read as a jump.
    private func walkDown(_ id: String) async {
        try? await Task.sleep(for: .seconds(Self.confettiSeconds))
        while let at = order.firstIndex(of: id), at + 1 < order.count,
            items.first(where: { $0.id == order[at + 1] })?.done == false
        {
            withAnimation(.easeInOut(duration: Self.stepSeconds * 0.8)) { order.swapAt(at, at + 1) }
            try? await Task.sleep(for: .seconds(Self.stepSeconds))
        }
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
