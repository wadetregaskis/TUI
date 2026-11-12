//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapePulled.swift
//
//  The application shapes SCROLL-FIT's pull reaches (design P2): lazy stacks
//  that are not their scroll view's direct content — under a title, two
//  stacked, inside a `GroupBox`, inside an app's own `Layout` — scrolled a
//  few lines every tick, so each frame walks the scroll position through the
//  containers that hold them and draws only the rows on screen.
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
    /// `VStack { title; TwoColumns { gutter; heading; LazyVStack; tail } }`,
    /// an app's own two-column `Layout` (SCROLL-FIT design B-SCROLLFIT-13).
    case layout
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
                case .layout:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Synth.sentence(seed, words: 8)).bold()
                        TwoColumns {
                            Text(verbatim: "│\n│\n│").dim()
                            Text(Synth.sentence(seed >> 3, words: 6)).bold()
                            PulledEntries(entries: entries, seed: seed, section: 0)
                            Text(Synth.sentence(seed >> 5, words: 4)).dim()
                        }
                    }
                }
            }
            .scrollPosition(.constant(ScrollPosition(y: line)))
        }
    }
}

/// An app's own `Layout`: the first subview in a gutter at its own width, the
/// others top to bottom in the column a cell to its right, as a textbook
/// conformance writes it (each subview measured in both passes).
private struct TwoColumns: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let width = proposal.width ?? 0
        let (gutter, frames) = frames(width: width, subviews: subviews)
        return ViewSize(width: width, height: max(gutter.height, frames.last.map { $0.y + $0.height } ?? 0))
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let (gutter, frames) = frames(width: bounds.width, subviews: subviews)
        first.place(
            at: CellPoint(x: bounds.x, y: bounds.y), proposal: ProposedViewSize(width: gutter.width, height: gutter.height))
        let x = gutter.width + 1
        for (subview, frame) in zip(subviews.dropFirst(), frames) {
            subview.place(
                at: CellPoint(x: bounds.x + x, y: bounds.y + frame.y),
                proposal: ProposedViewSize(width: max(0, bounds.width - x), height: frame.height))
        }
    }

    private func frames(width: Int, subviews: Subviews) -> (gutter: ViewSize, [(y: Int, height: Int)]) {
        guard let first = subviews.first else { return (ViewSize(width: 0, height: 0), []) }
        let gutter = first.sizeThatFits(.unspecified)
        let column = max(0, width - gutter.width - 1)
        var frames: [(y: Int, height: Int)] = []
        var y = 0
        for subview in subviews.dropFirst() {
            let height = subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            frames.append((y, height))
            y += height
        }
        return (gutter, frames)
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
