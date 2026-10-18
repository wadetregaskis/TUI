//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlacementRecordLifetimeTests.swift
//
//  A container remembers where it put its children (`PlacementStore`) for as
//  long as it is on screen: while it renders, or while a memo serves it. Not
//  while a window skips it — kept for that, a record per stack in every row a
//  list had been scrolled through was a table that grew with the scrolling,
//  and the end of every pass walked it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitView

/// Where the list is scrolled, which the test moves between frames.
@Observable
@MainActor
private final class ScrolledListModel {
    var position = ScrollPosition()
}

/// Three thousand rows, each an `HStack` — an eager stack, which remembers
/// its children's places — in a lazy stack that windows them.
private struct ScrolledListApp: App {
    let model: ScrolledListModel

    init() { self.init(model: ScrolledListModel()) }

    init(model: ScrolledListModel) { self.model = model }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<3_000, id: \.self) { index in
                        HStack(spacing: 1) {
                            Text("row")
                            Text(verbatim: "\(index)")
                        }
                    }
                }
            }
            .scrollPosition(Binding(get: { model.position }, set: { model.position = $0 }))
        }
    }
}

@MainActor
@Suite("A container's memory of its children's places lasts while it is on screen")
struct PlacementRecordLifetimeTests {

    /// Scrolled from the first row to the last, fifty rows a frame, with
    /// frames at rest between, the list's own window retaining every row's
    /// `@State` all the way: the records grow until a prune, and a prune
    /// keeps the stacks on screen, so the table stays within twice the
    /// threshold however far the list scrolls (`PlacementStore`, "When
    /// records are forgotten").
    @Test("A list scrolled end to end remembers a bounded number of stacks, not every one it has shown")
    func scrolledRowsAreForgotten() {
        let model = ScrolledListModel()
        let app = HeadlessApp(ScrolledListApp(model: model), width: 30, height: 20)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        let placements = app.services.stateStorage.placements
        let atRest = placements.count
        #expect(atRest > 10, "precondition: the rows on screen are remembered (\(atRest))")
        var most = atRest
        for y in stride(from: 50, through: 3_000, by: 50) {
            model.position.scrollTo(y: y)
            frame()
            frame()
            most = max(most, placements.count)
        }
        #expect(
            app.screen.map(\.stripped).contains { $0.contains("row 2999") },
            "precondition: the list reached its end:\n\(app.screen.map(\.stripped))")
        // Every row scrolled through was built, so without pruning the table
        // would end near 3,000; with it, it never passes the first threshold
        // by more than a frame's rows.
        #expect(
            most <= PlacementStore.minimumPruneThreshold + 100,
            "the records grew with the scrolling: \(atRest) at rest, \(most) at most")
        #expect(placements.pruneThreshold <= 2 * PlacementStore.minimumPruneThreshold)
    }
}
