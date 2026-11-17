//  🖥️ TUI — A Terminal UI framework for Swift
//  ObservationLeaseOpeningTests.swift
//
//  A page opens in two frames: the first, which learns which of its view
//  types read an `@Observable`, and the second, drawn after the clear that
//  learning asks for. Not three: at the second frame's end the first frame's
//  observation leases retire, and their sentinels fire the scopes they were
//  read in — among them a page's kept scope armed in the first frame before
//  its type was known to read, which read no sentinel of its own but collected
//  those of the leased row scopes nested in it. Such a scope cannot tell a
//  retirement from a change; once a frame drawn wholly after a clear of the
//  cache has replaced the one it watched, it has nothing left to report.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIView

/// One row's model: an object of its own, so a write to one is observed by its
/// row alone.
@Observable
@MainActor
private final class OpeningItem: Identifiable, Equatable {
    let id: Int
    var label: String
    var isOn = false

    init(id: Int) {
        self.id = id
        label = "item \(id)"
    }

    nonisolated static func == (lhs: OpeningItem, rhs: OpeningItem) -> Bool { lhs === rhs }
}

@Observable
@MainActor
private final class OpeningModel {
    var items: [OpeningItem]
    var title = "title 0"

    init(count: Int) { items = (0..<count).map(OpeningItem.init) }
}

private struct OpeningRow: View {
    let item: OpeningItem
    var body: some View { Text(verbatim: item.label) }
}

/// `ForEach` rows memoised in a stack, below a title the page reads itself:
/// the shape of `grid-scroll` and `focus-tab-scaling`.
private struct StackPage: View {
    let model: OpeningModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
            ForEach(model.items) { item in OpeningRow(item: item) }
        }
    }
}

/// A form's loop rows, memoised by their element: the shape of the form cases.
private struct FormPage: View {
    let model: OpeningModel
    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
            Form {
                Section("Rows") {
                    ForEach(model.items) { item in
                        Toggle(item.label, isOn: Binding(get: { item.isOn }, set: { item.isOn = $0 }))
                    }
                }
            }
        }
    }
}

private struct OpeningApp<Page: View>: App {
    let page: Page?
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its page") }
    init(_ page: Page) { self.page = page }
    var body: some Scene { WindowGroup { page } }
}

@MainActor
@Suite("A page opens in two frames, and a change after it is still drawn", .serialized)
struct ObservationLeaseOpeningTests {
    /// Draws frames as the case player does (`CasePlayer.drawFrames`): one,
    /// and another while a frame asks for one — but at least `atLeast`.
    /// Returns how many it drew.
    private func drawFrames(_ app: HeadlessApp, nanos: inout Int64, atLeast: Int = 1) -> Int {
        var frames = 0
        while frames < 6 {
            _ = app.takeFrameRequest()
            let asked = app.framesAsked
            nanos += 16_700_000
            app.frame(atNanos: nanos)
            frames += 1
            if !app.takeFrameRequest(), app.framesAsked == asked, frames >= atLeast { break }
        }
        return frames
    }

    private func text(_ app: HeadlessApp) -> String { app.screen.map(\.stripped).joined(separator: "\n") }

    private func play(_ app: HeadlessApp, _ model: OpeningModel) {
        var nanos: Int64 = 0
        // Two at least: a page with nothing to focus asks for no second frame,
        // and the first frame's leases retire at the end of the second, so
        // the second is drawn as anything that asks for one would draw it.
        let opening = drawFrames(app, nanos: &nanos, atLeast: 2)
        #expect(opening == 2, "the page opened in \(opening) frames")
        #expect(text(app).contains("title 0") && text(app).contains("item 9"))

        // What the first frame's scopes read is still observed: a write to a
        // row, and one to what the page's body reads, each asks for a frame
        // and is drawn in it.
        model.items[3].label = "changed 3"
        #expect(app.takeFrameRequest(), "the row's write asked for no frame")
        _ = drawFrames(app, nanos: &nanos)
        #expect(text(app).contains("changed 3"), "the row kept its label:\n\(text(app))")

        model.title = "title 1"
        #expect(app.takeFrameRequest(), "the title's write asked for no frame")
        _ = drawFrames(app, nanos: &nanos)
        #expect(text(app).contains("title 1"), "the page kept its title:\n\(text(app))")
        #expect(!text(app).contains("item 3"))
    }

    @Test("Rows memoised in a stack")
    func stack() {
        let model = OpeningModel(count: 12)
        play(HeadlessApp(OpeningApp(StackPage(model: model)), width: 40, height: 30), model)
    }

    @Test("A form's rows memoised by their element")
    func form() {
        let model = OpeningModel(count: 12)
        play(HeadlessApp(OpeningApp(FormPage(model: model)), width: 40, height: 30), model)
    }
}
