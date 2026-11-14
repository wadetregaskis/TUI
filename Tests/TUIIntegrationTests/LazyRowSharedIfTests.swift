//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyRowSharedIfTests.swift
//
//  A lazy stack's rows that each hold an `if` over one shared value: scrolled
//  down and back to the top, the rows on screen must show what the value now
//  says when it flips, as they do before any scrolling.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
import TUITesting
@testable import TUITestSupport

/// The value every row's `if` reads.
@Observable
@MainActor
private final class Shared {
    var showing = false
}

/// A row handed the value by its parent.
private struct HandedRow: View {
    let index: Int
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row \(index)")
            if showing { Text(verbatim: "  more \(index)") }
        }
    }
}

/// A handed row a lazy stack memoises by its value.
private struct EquatableRow: View, Equatable {
    let index: Int
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row \(index)")
            if showing { Text(verbatim: "  more \(index)") }
        }
    }
}

/// A handed row whose `if` holds a view with state.
private struct StatefulRow: View, Equatable {
    let index: Int
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row \(index)")
            if showing { MoreLine(index: index) }
        }
    }
}

private struct MoreLine: View {
    let index: Int
    @State private var shown = 0

    var body: some View { Text(verbatim: "  more \(index)") }
}

/// A row that reads the value itself.
private struct ReadingRow: View {
    let index: Int
    let shared: Shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row \(index)")
            if shared.showing { Text(verbatim: "  more \(index)") }
        }
    }
}

/// A row whose `if` reads a `@State` of the page's, through a binding.
private struct BoundRow: View {
    let index: Int
    @Binding var showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "row \(index)")
            if showing { Text(verbatim: "  more \(index)") }
        }
    }
}

/// How a row learns the value.
enum SharedIfRowKind: CaseIterable, Sendable { case handed, equatable, stateful, reading, bound, inline, inlineState }

private struct SharedIfPage: View {
    let shared: Shared
    let kind: SharedIfRowKind
    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rows
            // A change made in an event, as an app makes one.
            Button("flip") { withAnimation(.linear(duration: 0.5)) { shared.showing = true } }
        }
        .onChange(of: shared.showing) { showing = shared.showing }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2_000, id: \.self) { index in
                    switch kind {
                    case .handed: HandedRow(index: index, showing: shared.showing)
                    case .equatable: EquatableRow(index: index, showing: shared.showing)
                    case .stateful: StatefulRow(index: index, showing: shared.showing)
                    case .reading: ReadingRow(index: index, shared: shared)
                    case .bound: BoundRow(index: index, showing: $showing)
                    case .inline:
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "row \(index)")
                            if shared.showing { Text(verbatim: "  more \(index)") }
                        }
                    case .inlineState:
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "row \(index)")
                            if showing { Text(verbatim: "  more \(index)") }
                        }
                    }
                }
            }
        }
    }
}

/// The control: the same rows in an eager stack.
private struct EagerSharedIfPage: View {
    let shared: Shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { HandedRow(index: $0, showing: shared.showing) }
                }
            }
            Button("flip") { withAnimation(.linear(duration: 0.5)) { shared.showing = true } }
        }
    }
}

@MainActor
@Suite("A lazy stack's rows show a shared if's new content after scrolling away and back", .drawsInTruecolor)
struct LazyRowSharedIfTests {
    @Test("Never scrolled: the rows show the if's content when it turns on", arguments: SharedIfRowKind.allCases)
    func unscrolled(kind: SharedIfRowKind) {
        let shared = Shared()
        let app = TestApp(width: 40, height: 10) { SharedIfPage(shared: shared, kind: kind) }
        #expect(app.screen.contains("row 0"))
        shared.showing = true
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more 0"), "\(app.screen.text)")
    }

    @Test(
        "Scrolled down and back to the top: the rows show the if's content when it turns on",
        arguments: SharedIfRowKind.allCases, [10, 60, 400])
    func scrolledBack(kind: SharedIfRowKind, ticks: Int) {
        let shared = Shared()
        let app = TestApp(width: 40, height: 10) { SharedIfPage(shared: shared, kind: kind) }
        let centre = CellPoint(x: 20, y: 5)
        #expect(app.screen.contains("row 0"))
        app.scroll(.down, by: ticks, at: centre)
        #expect(!app.screen.contains("row 0"))
        app.scroll(.up, by: ticks * 2, at: centre)
        #expect(app.screen.lines.first?.contains("row 0") == true, "\(app.screen.text)")
        shared.showing = true
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more 0"), "\(app.screen.text)")
        #expect(app.screen.contains("more 1"), "\(app.screen.text)")
    }

    @Test(
        "Never scrolled, an animated change: the rows show the if's content when it has arrived",
        arguments: [SharedIfRowKind.handed, .stateful, .inline])
    func unscrolledAnimated(kind: SharedIfRowKind) throws {
        let shared = Shared()
        let app = TestApp(width: 40, height: 10) { SharedIfPage(shared: shared, kind: kind) }
        #expect(app.screen.contains("row 0"))
        try app.click("flip")
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more 0"), "\(app.screen.text)")
        #expect(app.screen.contains("more 1"), "\(app.screen.text)")
    }

    @Test("An eager stack, an animated change: the rows show the if's content when it has arrived")
    func eagerAnimated() throws {
        let shared = Shared()
        let app = TestApp(width: 40, height: 10) { EagerSharedIfPage(shared: shared) }
        #expect(app.screen.contains("row 0"))
        try app.click("flip")
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more 0"), "\(app.screen.text)")
    }

    /// The same with the change animated, so the content arrives with its
    /// default transition: an `if` seen empty on screen before plays one.
    @Test(
        "Scrolled down and back, an animated change: the rows show the if's content when it has arrived",
        arguments: [SharedIfRowKind.handed, .stateful, .inline], [60, 400])
    func scrolledBackAnimated(kind: SharedIfRowKind, ticks: Int) throws {
        let shared = Shared()
        let app = TestApp(width: 40, height: 10) { SharedIfPage(shared: shared, kind: kind) }
        let centre = CellPoint(x: 20, y: 5)
        app.scroll(.down, by: ticks, at: centre)
        app.scroll(.up, by: ticks * 2, at: centre)
        #expect(app.screen.lines.first?.contains("row 0") == true, "\(app.screen.text)")
        try app.click("flip")
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("more 0"), "\(app.screen.text)")
        #expect(app.screen.contains("more 1"), "\(app.screen.text)")
    }
}
