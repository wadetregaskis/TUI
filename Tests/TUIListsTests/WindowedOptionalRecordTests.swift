//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedOptionalRecordTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// How many `Stamped` views have been made: a `@State` box kept from an
/// earlier frame shows the number it was made with, a new one the latest.
@MainActor
private enum Made {
    static var count = 0

    static func next() -> Int {
        count += 1
        return count
    }
}

/// A view whose `@State` says when its box was made.
private struct Stamped: View {
    @State private var made = Made.next()

    var body: some View {
        Text("made \(made)")
    }
}

/// What an `if` keeps of a row a lazy stack has scrolled past.
///
/// Each `if` keeps a record (`OptionalPresence`): the picture its view last
/// drew, for the frame an animated change takes the view out to fade it from,
/// and where that view was, so the render that finds the `if` empty drops the
/// view's state. A row scrolled out of a lazy stack keeps its state, as
/// SwiftUI's does, and the record went with it, picture, identity chain and
/// all: Stress `titled-lazy`, whose rows each hold an `if`, grew by about 1.7
/// KB a line scrolled, 99 MB after 48,000 lines. Only the dropping of state
/// can still matter for a row nobody has seen since
/// (`StateStorage.wasOnScreenLastPass(writtenOn:at:)`), so the record goes
/// unless the view it held has state.
@MainActor
@Suite("An if's record in a row scrolled past")
struct WindowedOptionalRecordTests {
    private static let viewport = 8
    private static let rowCount = 2_000

    /// A row of one or two lines, the second behind an `if`.
    private struct Row: View, Equatable {
        let index: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("row \(index)")
                if index.isMultiple(of: 2) { Text("detail \(index)") }
            }
        }
    }

    /// A row whose `if` holds a view with state, while `showing`.
    private struct StatefulRow: View, Equatable {
        let index: Int
        let showing: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("row \(index)")
                if showing { Stamped() }
            }
        }
    }

    private func page(line: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { Row(index: $0) }
            }
        }
        .scrollPosition(.constant(ScrollPosition(y: line)))
    }

    private func statefulPage(line: Int, showing: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { StatefulRow(index: $0, showing: showing) }
            }
        }
        .scrollPosition(.constant(ScrollPosition(y: line)))
    }

    /// One frame, with the render-pass hooks the real loop drives.
    @discardableResult
    private func renderFrame<V: View>(_ view: V, tuiContext: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Scrolling through a lazy stack keeps the records of the rows on screen, not of every row passed")
    func recordsStayBounded() {
        let tuiContext = TUIContext()
        var drawn: [String] = []
        for frame in 0..<400 {
            drawn = renderFrame(page(line: frame * 3), tuiContext: tuiContext)
        }
        // 1,200 lines scrolled: 800 rows, each with an `if`. The records kept
        // are those of the rows on screen and those a sweep has not reached
        // yet — never all 800.
        let records = tuiContext.stateStorage.optionalPresence
        #expect(drawn.contains { $0.hasPrefix("row 79") || $0.hasPrefix("row 80") }, "it scrolled: \(drawn)")
        #expect(records.count < 200, "records kept: \(records.count)")
        #expect(records.values.count { $0.picture != nil } < 100)
    }

    /// The record of an `if` whose view has state stays with the row, so the
    /// row coming back with its `if` empty drops that state, as one on
    /// screen does. Read from the storage: the boxes of the view's state,
    /// which the render that finds the `if` empty drops.
    @Test("A row scrolled past and back with its if emptied loses the state of the view the if held")
    func statefulRecordSurvives() {
        let tuiContext = TUIContext()
        let storage = tuiContext.stateStorage
        /// The state boxes of the `Stamped` in row 0.
        func rowZeroStamps() -> Int {
            storage.values.keys.count { key in
                key.identity.path.contains("StatefulRow[0]") && key.identity.path.contains("Stamped")
            }
        }
        let first = renderFrame(statefulPage(line: 0, showing: true), tuiContext: tuiContext)
        #expect(first[1].hasPrefix("made "), "\(first)")
        #expect(rowZeroStamps() > 0, "row 0's view keeps its state in a box")
        for frame in 1..<200 {
            renderFrame(statefulPage(line: frame * 3, showing: true), tuiContext: tuiContext)
        }
        #expect(rowZeroStamps() > 0, "scrolled past, the row keeps its state")
        renderFrame(statefulPage(line: 0, showing: false), tuiContext: tuiContext)
        #expect(rowZeroStamps() == 0, "back with its if empty, the row drops the state of the view the if held")
    }
}
