//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarLabelledGroupTests.swift
//
//  A labelled `ToolbarItemGroup` shows its views while the bar has room for
//  them, and collapses to its label — a pull-down of the views — when it does
//  not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the probe's buttons did, reachable from an `App`.
private final class Formatting: @unchecked Sendable {
    static let shared = Formatting()
    var italic = 0
}

/// A labelled group of three buttons at the top bar's trailing end.
private struct LabelledGroupApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("BOLD") {}
                        Button("ITALIC") { Formatting.shared.italic += 1 }
                        Button("UNDERLINE") {}
                    } label: {
                        Text("FORMAT")
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Labelled toolbar item group", .serialized)
struct ToolbarLabelledGroupTests {

    /// The app at `width`, after the frame that declares the bar and the one
    /// that draws it.
    private func app(width: Int) -> (HeadlessApp, [String]) {
        let app = HeadlessApp(LabelledGroupApp(), width: width, height: 10)
        app.frame(atNanos: 20_000_000)
        app.frame(atNanos: 40_000_000)
        return (app, app.screen.map(\.stripped))
    }

    @Test("With room, the group's views are drawn side by side")
    func fits() {
        let (_, rows) = app(width: 60)
        let top = rows.first ?? ""
        #expect(top.contains("BOLD") && top.contains("ITALIC") && top.contains("UNDERLINE"), "\(rows)")
        #expect(!top.contains("FORMAT"), "\(rows)")
    }

    @Test("Without room, the group collapses to its label, which opens the views as a menu")
    func collapses() {
        Formatting.shared.italic = 0
        let (app, rows) = app(width: 24)
        let top = rows.first ?? ""
        #expect(top.contains("FORMAT \(DropdownMenu.closedCaret)"), "\(rows)")
        #expect(!top.contains("ITALIC"), "\(rows)")
        guard let at = top.range(of: "FORMAT") else { return }
        let column = top.distance(from: top.startIndex, to: at.lowerBound)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        app.frame(atNanos: 60_000_000)
        let open = app.screen.map(\.stripped)
        guard let row = open.firstIndex(where: { $0.contains("ITALIC") }), let found = open[row].range(of: "ITALIC")
        else {
            Issue.record("the menu did not open: \(open)")
            return
        }
        let x = open[row].distance(from: open[row].startIndex, to: found.lowerBound)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: x, y: row))
        app.frame(atNanos: 80_000_000)
        #expect(Formatting.shared.italic == 1, "the item chosen from the menu runs")
    }
}
