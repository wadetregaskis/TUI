//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationClip.swift
//
//  `animation`: a habit tracker that moves — a tab underline gliding between
//  tabs (matched geometry), habits flying from one column to the other as
//  they are done, a notice sliding in and out (a transition), and a streak
//  bar springing to its new length.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let animationClip = Clip(
    id: "animation",
    title: "Animation",
    columns: 112,
    rows: 30,
    output: 800,
    script: [
        .camera(Shot(x: 0, y: 2, width: 86, height: 18)),
        .wait(0.9), .cue("done"),
        .wait(1.1), .cue("tab 1"),
        .wait(1.0), .cue("done"),
        .wait(1.1), .cue("tab 2"),
        .wait(1.0), .cue("done"),
        .wait(1.3), .cue("reset"), .cue("tab 0"),
        .wait(1.4),
    ],
    run: { await AnimationApp.main() }
)

struct AnimationApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Habits") {
            HabitTracker()
                .palette(SystemPalette(.blue))
        }
    }
}

/// Habits to do and done, a tab bar, a streak, and a notice when one is done.
struct HabitTracker: View {
    @Namespace private var space
    @State private var toDo = ["Stretch", "Read 20 pages", "Water plants", "Walk 5 km"]
    @State private var done = ["Meditate"]
    @State private var tab = 0
    @State private var notice: String?

    private static let tabs = ["Today", "This week", "This month"]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            tabBar
            HStack(alignment: .top, spacing: 2) {
                column("To do", habits: toDo)
                column("Done", habits: done)
                week
            }
            streak
            if let notice {
                Text(verbatim: "✓ \(notice) — streak +1")
                    .padding(.horizontal, 1)
                    .foregroundStyle(.palette.background)
                    .background(.palette.success)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Habits") }
        }
        .task {
            for await cue in ClipCues.stream() { apply(cue) }
        }
    }

    private func apply(_ cue: String) {
        let spring = Animation.spring(duration: 0.6, bounce: 0.35)
        if cue == "done", !toDo.isEmpty {
            withAnimation(spring) {
                let habit = toDo.removeFirst()
                done.append(habit)
                notice = habit
            }
        } else if cue.hasPrefix("tab "), let index = Int(cue.dropFirst(4)) {
            withAnimation(spring) { tab = index; notice = nil }
        } else if cue == "reset" {
            withAnimation(spring) {
                toDo = ["Stretch", "Read 20 pages", "Water plants", "Walk 5 km"]
                done = ["Meditate"]
                notice = nil
            }
        }
    }

    private var tabBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                ForEach(Self.tabs.indices, id: \.self) { index in
                    Text(verbatim: Self.tabs[index])
                        .bold(index == tab)
                        .matchedGeometryEffect(id: index, in: space, anchor: .bottom)
                }
            }
            Color.accentColor
                .frame(height: 1)
                .matchedGeometryEffect(id: tab, in: space, anchor: .top, isSource: false)
        }
    }

    private func column(_ title: String, habits: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title).bold()
            ForEach(habits, id: \.self) { habit in
                Text(verbatim: " \(habit) ")
                    .foregroundStyle(.palette.background)
                    .background(title == "Done" ? .palette.success : .palette.accent)
                    .matchedGeometryEffect(id: habit, in: space)
            }
        }
        .frame(width: 17, height: 7, alignment: .topLeading)
        .padding(.horizontal, 1)
        .border()
    }

    /// The week so far: a row of days per habit, today's lit once it is done.
    private var week: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text(verbatim: "This week").bold()
                Spacer(minLength: 0)
                Text(verbatim: "M T W T F S S").foregroundStyle(.palette.foregroundTertiary)
            }
            ForEach(Self.allHabits, id: \.self) { habit in
                HStack(spacing: 1) {
                    Text(verbatim: habit).foregroundStyle(.palette.foregroundSecondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 1) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(verbatim: day > Self.today ? "·" : "■")
                                .foregroundStyle(cellColour(habit: habit, day: day))
                        }
                    }
                }
            }
        }
        .frame(width: 30, height: 7, alignment: .topLeading)
        .padding(.horizontal, 1)
        .border()
    }

    private static let allHabits = ["Meditate", "Stretch", "Read 20 pages", "Water plants", "Walk 5 km"]
    /// Friday.
    private static let today = 4

    /// Done days in the accent, missed ones dim; today's follows the columns.
    private func cellColour(habit: String, day: Int) -> Color {
        if day > Self.today { return .palette.foregroundTertiary }
        if day == Self.today { return done.contains(habit) ? .palette.success : .palette.foregroundTertiary }
        let hash = habit.unicodeScalars.reduce(day * 31) { $0 &+ Int($1.value) }
        return hash.isMultiple(of: 4) ? .palette.foregroundTertiary : .palette.accent
    }

    /// The streak: a bar as long as the habits done, springing to it.
    private var streak: some View {
        HStack(spacing: 1) {
            Text(verbatim: "Streak")
            Color.palette.accent
                .frame(width: 6 * done.count, height: 1)
            Text(verbatim: "\(done.count * 3) days").foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
