//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapePulled.swift
//
//  The application shapes SCROLL-FIT's pull reaches (design P2): lazy stacks
//  that are not their scroll view's direct content — under a title, two
//  stacked, inside a `GroupBox` — scrolled a few lines every tick, so each
//  frame walks the scroll position through the column that holds them and
//  draws only the rows on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Where a pulled page puts its lazy stacks.
enum PulledShape: Sendable {
    /// `VStack { title; LazyVStack }`.
    case titled
    /// `VStack { heading; LazyVStack; heading; LazyVStack }`.
    case twoStacked
    /// `VStack { title; GroupBox { LazyVStack } }`.
    case boxed
}

/// A page of lazy stacks of one- and two-line entries in one scroll view, the
/// page moved three lines down each tick, back to the top before the end: the
/// frames a reader moving through a long document pays.
struct PulledPageApp: View {
    let shape: PulledShape
    let entries: Int
    let seed: UInt64
    @Environment(StressClock.self) private var clock

    var body: some View {
        // Wrapped well before the end, so every frame is a scroll and none a
        // clamp: three lines a tick through about half of the first stack.
        let line = (clock.tick * 3) % max(1, entries / 2)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "pulled", entries)).bold()
            ScrollView {
                switch shape {
                case .titled:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Synth.sentence(seed, words: 8)).bold()
                        PulledEntries(entries: entries, seed: seed, section: 0)
                    }
                case .twoStacked:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Synth.sentence(seed, words: 6)).bold()
                        PulledEntries(entries: entries / 2, seed: seed, section: 0)
                        Text(Synth.sentence(seed >> 3, words: 6)).bold()
                        PulledEntries(entries: entries / 2, seed: seed, section: 1)
                    }
                case .boxed:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Synth.sentence(seed, words: 8)).bold()
                        GroupBox { PulledEntries(entries: entries, seed: seed, section: 0) }
                    }
                }
            }
            .scrollPosition(.constant(ScrollPosition(y: line)))
        }
    }
}

/// A lazy stack of entries, about a third of them two lines.
private struct PulledEntries: View {
    let entries: Int
    let seed: UInt64
    let section: Int

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<entries, id: \.self) { entry in
                PulledEntry(seed: seed, section: section, entry: entry)
            }
        }
    }
}

/// One entry (`Equatable` so unchanged entries value-memoize, as an app's rows would).
private struct PulledEntry: View, Equatable {
    let seed: UInt64
    let section: Int
    let entry: Int

    var body: some View {
        let h = mix(seed, section &* 100_003 &+ entry)
        VStack(alignment: .leading, spacing: 0) {
            Text("\(entry) \(Synth.slug(h)) \(Synth.status(h))")
            if h.isMultiple(of: 3) {
                Text(Synth.sentence(h >> 8, words: 4)).dim()
            }
        }
    }
}
