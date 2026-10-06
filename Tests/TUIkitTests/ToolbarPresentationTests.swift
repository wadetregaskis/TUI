//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarPresentationTests.swift
//
//  A `.toolbar` in a sheet's content is the sheet's: its items are drawn in the
//  sheet, round the view that declared them, live in the sheet's focus
//  section, with the confirmation item the default button — not dead buttons
//  in the window's bar, which is inert while the sheet is up.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the sheet's items did, reachable from an `App`.
private final class SheetItemProbe: @unchecked Sendable {
    static let shared = SheetItemProbe()
    var saves = 0
    var cancels = 0
    var discards = 0

    func reset() {
        saves = 0
        cancels = 0
        discards = 0
    }
}

/// A sheet whose content declares a sheet's three actions.
private struct SheetToolbarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .sheet(isPresented: .constant(true)) {
                    TextField("Name", text: .constant("NAME"))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("SAVE") { SheetItemProbe.shared.saves += 1 }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("CANCEL") { SheetItemProbe.shared.cancels += 1 }
                            }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("DISCARD") { SheetItemProbe.shared.discards += 1 }
                            }
                        }
                }
        }
    }
}

/// A popover whose content declares a confirmation item.
private struct PopoverToolbarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("ANCHOR")
                .popover(isPresented: .constant(true)) {
                    Text("BODY")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("APPLY") { SheetItemProbe.shared.saves += 1 }
                            }
                        }
                }
        }
    }
}

/// A page with the line of key hints, under a sheet that asks to hide the
/// bottom bar.
private struct SheetHidingBarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
                .sheet(isPresented: .constant(true)) {
                    Text("SHEET").toolbarVisibility(.hidden, for: .bottomBar)
                }
        }
    }
}

@MainActor
@Suite("A toolbar in a sheet", .serialized)
struct ToolbarPresentationTests {

    private func settled() -> HeadlessApp<SheetToolbarApp> {
        let app = HeadlessApp(SheetToolbarApp(), width: 60, height: 14)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app
    }

    @Test("The items are drawn in the sheet, under its content, as a sheet's button row — and the window grows no bar")
    func itemsAreTheSheetsButtonRow() throws {
        let screen = settled().screen.map(\.stripped)
        let field = try #require(screen.firstIndex { $0.contains("NAME") }, "\(screen)")
        let row = try #require(screen.firstIndex { $0.contains("SAVE") }, "\(screen)")
        #expect(row > field, "below the content: \(screen)")
        let line = screen[row]
        let discard = try #require(line.range(of: "DISCARD"))
        let cancel = try #require(line.range(of: "CANCEL"))
        let save = try #require(line.range(of: "SAVE"))
        #expect(discard.lowerBound < cancel.lowerBound, "destructive leads: \(line)")
        #expect(cancel.lowerBound < save.lowerBound, "confirmation is last: \(line)")
        #expect(!screen.contains { $0.hasPrefix("╭") }, "no window bar: \(screen)")
    }

    @Test("The items are live: Return from the field fires the confirmation item, and a click fires one")
    func itemsAreLive() throws {
        SheetItemProbe.shared.reset()
        let app = settled()
        app.send(KeyEvent(key: .enter))
        #expect(SheetItemProbe.shared.saves == 1, "Return, from the text field, is the default button")
        app.frame(atNanos: 40_000_000)
        let screen = app.screen.map(\.stripped)
        let row = try #require(screen.firstIndex { $0.contains("CANCEL") }, "\(screen)")
        let column = screen[row].distance(
            from: screen[row].startIndex, to: try #require(screen[row].range(of: "CANCEL")).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(SheetItemProbe.shared.cancels == 1, "a click")
        #expect(SheetItemProbe.shared.discards == 0)
    }

    @Test("Tab reaches the items after the sheet's own content")
    func itemsAreInTheSheetsTabRing() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(SheetToolbarApp())
        _ = loop.render()
        _ = loop.render()
        let ring = harness.focusManager.activeSection?.focusables.map(\.focusID) ?? []
        #expect(ring.count == 4, "the field and the three buttons, in the sheet's section: \(ring)")
        #expect(ring.first.map { !$0.hasPrefix("button-") } == true, "the field first, then the buttons: \(ring)")
        #expect(harness.focusManager.currentFocusedID == ring.first, "the field has the focus")
    }

    @Test("A popover's toolbar is the popover's too: drawn under its content, and live")
    func popoverHostsItsItems() throws {
        SheetItemProbe.shared.reset()
        let app = HeadlessApp(PopoverToolbarApp(), width: 60, height: 14)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let screen = app.screen.map(\.stripped)
        let body = try #require(screen.firstIndex { $0.contains("BODY") }, "\(screen)")
        let row = try #require(screen.firstIndex { $0.contains("APPLY") }, "\(screen)")
        #expect(row > body, "below the popover's content: \(screen)")
        // Sized to its content and its row of items, not to the terminal: the
        // row's spacers fill what they are offered, so measured against the
        // popover's room the row made the popover as wide as the screen.
        #expect(!screen.contains { $0.hasPrefix("╭") && $0.count == 60 }, "as wide as its content: \(screen)")
        let column = screen[row].distance(
            from: screen[row].startIndex, to: try #require(screen[row].range(of: "APPLY")).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(SheetItemProbe.shared.saves == 1, "a click on the item fires it")
    }

    @Test("A sheet's .toolbarVisibility does not take the window's bar, with the key that closes the sheet")
    func sheetVisibilityStaysInTheSheet() {
        let app = HeadlessApp(SheetHidingBarApp(), width: 50, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let rows = app.screen.map(\.stripped)
        #expect(rows[rows.count - 2].contains("dismiss"), "\(rows)")
    }
}
