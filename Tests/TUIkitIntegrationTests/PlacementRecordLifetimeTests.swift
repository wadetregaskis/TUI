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

/// Three hundred rows, each an `HStack` — an eager stack, which remembers
/// its children's places — in a lazy stack that windows them.
private struct ScrolledListApp: App {
    let model: ScrolledListModel

    init() { self.init(model: ScrolledListModel()) }

    init(model: ScrolledListModel) { self.model = model }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { index in
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

    /// Scrolled from the first row to the last, ten rows a frame, with frames
    /// at rest between, the list's own window retaining every row's `@State`
    /// all the way: the stacks remembered are the ones on screen, not the
    /// ones scrolled through.
    @Test("A list scrolled end to end remembers the stacks it shows, not every one it has shown")
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
        for y in stride(from: 10, through: 300, by: 10) {
            model.position.scrollTo(y: y)
            frame()
            frame()
            most = max(most, placements.count)
        }
        #expect(
            app.screen.map(\.stripped).contains { $0.contains("row 299") },
            "precondition: the list reached its end:\n\(app.screen.map(\.stripped))")
        #expect(most < atRest + 20, "a record outlived its row's going off screen: \(atRest) at rest, \(most) at most")
    }
}
