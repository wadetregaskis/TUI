//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetToolbarEdgesTests.swift
//
//  A sheet hosts its toolbar's items at its own edges, wherever in its content
//  they are declared — its button row along its bottom, the other items along
//  its top — opens with them, and honours `.toolbarVisibility` for them
//  (decisions D5C, B-D5C-3's fuller version).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport

/// What the probe's sheet does, reachable from an `App`.
private final class SheetProbe: @unchecked Sendable {
    static let shared = SheetProbe()
    var hidesButtonRow = false
    var saves = 0
}

/// A sheet whose items are declared on two different views inside it, neither
/// at its edge.
private struct EdgesApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .sheet(isPresented: .constant(true)) {
                    VStack(spacing: 0) {
                        Text("FIRST LINE")
                        Text("MIDDLE")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("SAVE") { SheetProbe.shared.saves += 1 }
                                }
                            }
                        Text("OTHER")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("CANCEL") {} }
                                ToolbarItem(placement: .principal) { Text("HEADING") }
                            }
                        Text("LAST LINE")
                    }
                    .toolbarVisibility(SheetProbe.shared.hidesButtonRow ? .hidden : .automatic, for: .bottomBar)
                }
        }
    }
}

@MainActor
@Suite("A sheet's toolbar at its edges", .serialized)
struct SheetToolbarEdgesTests {

    private func reset() {
        SheetProbe.shared.hidesButtonRow = false
        SheetProbe.shared.saves = 0
    }

    /// The app, `frames` frames in.
    private func screen(frames: Int) -> (HeadlessApp<EdgesApp>, [String]) {
        let app = HeadlessApp(EdgesApp(), width: 50, height: 16)
        for frame in 1...frames { app.frame(atNanos: Int64(frame) * 20_000_000) }
        return (app, app.screen.map(\.stripped))
    }

    private func row(_ rows: [String], _ text: String) -> Int? {
        rows.firstIndex { $0.contains(text) }
    }

    @Test("The button row is along the sheet's bottom edge and the other items along its top, from the first frame")
    func atTheEdges() {
        reset()
        defer { reset() }
        let (_, rows) = screen(frames: 1)
        guard let first = row(rows, "FIRST LINE"), let last = row(rows, "LAST LINE"),
            let save = row(rows, "SAVE"), let cancel = row(rows, "CANCEL"), let heading = row(rows, "HEADING")
        else {
            Issue.record("\(rows)")
            return
        }
        #expect(save == cancel, "one button row for both declarations: \(rows)")
        #expect(save == last + 1, "below the last line, not under the view that declared it: \(rows)")
        #expect(heading == first - 1, "above the first line: \(rows)")
        if let cancelAt = rows[save].range(of: "CANCEL"), let saveAt = rows[save].range(of: "SAVE") {
            #expect(cancelAt.lowerBound < saveAt.lowerBound, "cancellation, then confirmation: \(rows[save])")
        }
    }

    @Test("The items are live in the sheet: a click on the confirmation button runs it")
    func clickSaves() {
        reset()
        defer { reset() }
        let (app, rows) = screen(frames: 3)
        guard let save = row(rows, "SAVE"), let at = rows[save].range(of: "SAVE") else {
            Issue.record("\(rows)")
            return
        }
        let x = rows[save].distance(from: rows[save].startIndex, to: at.lowerBound)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: save))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: x, y: save))
        app.frame(atNanos: 100_000_000)
        #expect(SheetProbe.shared.saves == 1, "\(app.screen.map(\.stripped))")
    }

    @Test("toolbarVisibility(.hidden, for: .bottomBar) in the sheet takes its button row away")
    func hidingTheButtonRow() {
        reset()
        defer { reset() }
        SheetProbe.shared.hidesButtonRow = true
        let (_, rows) = screen(frames: 3)
        #expect(!rows.contains { $0.contains("SAVE") || $0.contains("CANCEL") }, "\(rows)")
        #expect(rows.contains { $0.contains("HEADING") }, "the top row stays: \(rows)")
    }
}
