//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarTitleMenuTests.swift
//
//  A title menu makes the window's title in the top bar a pull-down of its
//  items: a click opens it, and an item chosen from it runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What the probe's items did, and how it declares its menu, reachable from
/// an `App`.
private final class TitleMenuProbe: @unchecked Sendable {
    static let shared = TitleMenuProbe()
    var duplicates = 0
    var asModifier = false
    var principal = false
    var empty = false
}

/// A titled page whose title opens a menu, declared as `TitleMenuProbe` says.
private struct TitleMenuApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            if TitleMenuProbe.shared.asModifier {
                page.toolbarTitleMenu {
                    Button("DUPLICATE") { TitleMenuProbe.shared.duplicates += 1 }
                }
            } else {
                page.toolbar {
                    if TitleMenuProbe.shared.empty {
                        ToolbarTitleMenu()
                    } else {
                        ToolbarTitleMenu {
                            Button("DUPLICATE") { TitleMenuProbe.shared.duplicates += 1 }
                        }
                    }
                }
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }

    private var page: some View {
        Text("PAGE")
            .navigationTitle("DOC")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Text("END") }
                if TitleMenuProbe.shared.principal {
                    ToolbarItem(placement: .principal) { Text("MID") }
                }
            }
    }
}

@MainActor
@Suite("Toolbar title menu", .serialized)
struct ToolbarTitleMenuTests {

    private func reset() {
        TitleMenuProbe.shared.duplicates = 0
        TitleMenuProbe.shared.asModifier = false
        TitleMenuProbe.shared.principal = false
        TitleMenuProbe.shared.empty = false
    }

    /// The app, and the frame clock it is stepped on.
    @MainActor
    private final class Driver {
        let app = HeadlessApp(TitleMenuApp(), width: 40, height: 8)
        var now: Int64 = 0

        func frame() -> [String] {
            now += 20_000_000
            app.frame(atNanos: now)
            return app.screen.map(\.stripped)
        }

        func click(x: Int, y: Int) {
            _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
    }

    /// The top bar's row once the bar is drawn: one frame to declare it, one
    /// to draw it.
    private func topRow() -> String {
        let driver = Driver()
        _ = driver.frame()
        return driver.frame().first ?? ""
    }

    /// Clicks the title, then the item, and says what the screen showed.
    private func chooseFromTheTitle() -> (closed: [String], open: [String]) {
        let driver = Driver()
        _ = driver.frame()
        let closed = driver.frame()
        driver.click(x: 1, y: 0)
        let open = driver.frame()
        if let row = open.firstIndex(where: { $0.contains("DUPLICATE") }),
            let found = open[row].range(of: "DUPLICATE")
        {
            driver.click(x: open[row].distance(from: open[row].startIndex, to: found.lowerBound) + 1, y: row)
            _ = driver.frame()
        }
        return (closed, open)
    }

    @Test("The title is a pull-down whose item runs when chosen")
    func titleOpensItsMenu() {
        reset()
        defer { reset() }
        let (closed, open) = chooseFromTheTitle()
        #expect(closed.first?.trimmingCharacters(in: .whitespaces).hasPrefix("DOC \(DropdownMenu.closedCaret)") == true, "\(closed)")
        #expect(!closed.contains { $0.contains("DUPLICATE") }, "closed: \(closed)")
        #expect(open.contains { $0.contains("DUPLICATE") }, "open: \(open)")
        #expect(TitleMenuProbe.shared.duplicates == 1)
    }

    @Test("toolbarTitleMenu(content:) is the same menu")
    func modifierForm() {
        reset()
        defer { reset() }
        TitleMenuProbe.shared.asModifier = true
        let (closed, _) = chooseFromTheTitle()
        #expect(closed.first?.trimmingCharacters(in: .whitespaces).hasPrefix("DOC \(DropdownMenu.closedCaret)") == true, "\(closed)")
        #expect(TitleMenuProbe.shared.duplicates == 1)
    }

    @Test("A principal item that takes the title's place takes its menu too")
    func principalTakesTheMenu() {
        reset()
        defer { reset() }
        TitleMenuProbe.shared.principal = true
        let row = topRow()
        #expect(!row.contains("DOC") && !row.contains(DropdownMenu.closedCaret), "\(row)")
    }

    @Test("A title menu with nothing in it leaves the title as it is")
    func emptyMenu() {
        reset()
        defer { reset() }
        TitleMenuProbe.shared.empty = true
        let row = topRow()
        #expect(row.hasPrefix("DOC") && !row.contains(DropdownMenu.closedCaret), "\(row)")
    }
}
