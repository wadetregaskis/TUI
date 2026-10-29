//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarCustomizationTests.swift
//
//  `toolbar(id:content:)`: the person puts a customizable toolbar's items in
//  the bar or takes them out, and moves them, from the bar's context menu and
//  the panel it opens; what they chose is kept per identifier.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// The store the probe's choices are kept in, and what its items did,
/// reachable from an `App`.
private final class CustomizationProbe: @unchecked Sendable {
    static let shared = CustomizationProbe()
    var store = MockStorageBackend()
    var downloads = 0
    var hidesShare = false
    var taps = 0
}

/// A customizable toolbar: two items in the bar, one that starts out of it,
/// one that starts out of it but stays in the overflow menu, and one the
/// person may not touch.
private struct CustomizableApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar(id: "main") {
                    ToolbarItem(id: "share", placement: .primaryAction) { Text("SHARE") }
                        .hidden(CustomizationProbe.shared.hidesShare)
                    ToolbarItem(id: "print", placement: .primaryAction) { Text("PRINT") }
                    ToolbarItem(id: "mail", placement: .primaryAction) { Text("MAIL") }
                        .defaultCustomization(.hidden)
                    ToolbarItem(id: "downloads", placement: .primaryAction) {
                        Button("DOWNLOADS") { CustomizationProbe.shared.downloads += 1 }
                    }
                    .defaultCustomization(.hidden, options: .alwaysAvailable)
                    ToolbarItem(id: "fixed", placement: .primaryAction) { Text("FIXED") }
                        .customizationBehavior(.disabled)
                }
        }
        .defaultAppStorage(CustomizationProbe.shared.store)
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// A customizable toolbar of buttons, for the keyboard's way in.
private struct KeyboardCustomizableApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar(id: "keys") {
                    ToolbarItem(id: "new", placement: .primaryAction) { Button("NEW") {} }
                    ToolbarItem(id: "open", placement: .primaryAction) { Button("OPEN") {} }
                        .defaultCustomization(.hidden)
                }
        }
        .defaultAppStorage(CustomizationProbe.shared.store)
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// A customizable toolbar with items in two places: two at the top bar's
/// leading end, declared either side of one at its trailing end.
private struct MixedPlacementsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar(id: "mixed") {
                    ToolbarItem(id: "lead", placement: .navigation) { Text("LEAD") }
                    ToolbarItem(id: "act", placement: .primaryAction) { Text("ACT") }
                    ToolbarItem(id: "second", placement: .navigation) { Text("SECOND") }
                }
        }
        .defaultAppStorage(CustomizationProbe.shared.store)
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// A customizable toolbar of buttons to drag in the bar: three the person
/// may take out, and one they may only move.
private struct DraggableApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar(id: "drag") {
                    ToolbarItem(id: "alpha", placement: .primaryAction) {
                        Button("ALPHA") { CustomizationProbe.shared.taps += 1 }
                    }
                    ToolbarItem(id: "beta", placement: .primaryAction) { Text("BETA") }
                    ToolbarItem(id: "gamma", placement: .primaryAction) { Text("GAMMA") }
                    ToolbarItem(id: "kept", placement: .primaryAction) { Text("KEPT") }
                        .customizationBehavior(.reorderable)
                }
        }
        .defaultAppStorage(CustomizationProbe.shared.store)
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Toolbar customization", .serialized)
struct ToolbarCustomizationTests {

    private func reset() {
        CustomizationProbe.shared.store = MockStorageBackend()
        CustomizationProbe.shared.downloads = 0
        CustomizationProbe.shared.hidesShare = false
        CustomizationProbe.shared.taps = 0
    }

    /// The app and its frame clock.
    @MainActor
    private final class Driver<Probe: App> {
        let app: HeadlessApp<Probe>
        var now: Int64 = 0

        init(_ probe: Probe) {
            app = HeadlessApp(probe, width: 70, height: 16)
            frames(2)
        }

        func frames(_ count: Int = 2) {
            for _ in 0..<count {
                now += 20_000_000
                app.frame(atNanos: now)
            }
        }

        var rows: [String] { app.screen.map(\.stripped) }

        /// Clicks the first cell showing `text`, with `button`.
        func click(_ text: String, button: MouseButton = .left, after skip: String? = nil) {
            for (row, line) in rows.enumerated() {
                guard let found = line.range(of: text) else { continue }
                if let skip, !line.contains(skip) { continue }
                let x = line.distance(from: line.startIndex, to: found.lowerBound)
                _ = app.send(MouseEvent(button: button, phase: .pressed, x: x, y: row))
                _ = app.send(MouseEvent(button: button, phase: .released, x: x, y: row))
                frames()
                return
            }
            Issue.record("no \(text) on the screen: \(rows)")
        }

        /// Drags the grip of the panel row showing `text` down `rows` rows (up
        /// where negative), a frame after each step.
        func dragGrip(of text: String, rows count: Int) {
            guard let row = rows.firstIndex(where: { $0.contains(text) && $0.contains("▼") }),
                let found = rows[row].range(of: "\u{283F}")
            else {
                Issue.record("no grip for \(text): \(rows)")
                return
            }
            let x = rows[row].distance(from: rows[row].startIndex, to: found.lowerBound)
            _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
            frames()
            for step in 1...abs(count) {
                _ = app.send(MouseEvent(button: .left, phase: .dragged, x: x, y: row + step * count.signum()))
                frames()
            }
            _ = app.send(MouseEvent(button: .left, phase: .released, x: x, y: row + count))
            frames()
        }

        /// Drags the bar's item showing `text` by its first cell, `across`
        /// cells sideways and then `down` rows, a cell at a time with a frame
        /// after each, and lets it go there.
        func dragBarItem(_ text: String, across: Int, down: Int = 0) {
            guard let bar = rows.first, let found = bar.range(of: text) else {
                Issue.record("no \(text) in the bar: \(rows)")
                return
            }
            let x = bar.distance(from: bar.startIndex, to: found.lowerBound)
            _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: 0))
            frames()
            var at = (x: x, y: 0)
            for _ in 0..<abs(across) {
                at.x += across.signum()
                _ = app.send(MouseEvent(button: .left, phase: .dragged, x: at.x, y: at.y))
                frames()
            }
            for _ in 0..<abs(down) {
                at.y += down.signum()
                _ = app.send(MouseEvent(button: .left, phase: .dragged, x: at.x, y: at.y))
                frames()
            }
            _ = app.send(MouseEvent(button: .left, phase: .released, x: at.x, y: at.y))
            frames()
        }

        /// Opens the panel from the top bar's context menu.
        func openPanel() {
            click("PRINT", button: .right)
            click("Customize Toolbar")
        }
    }

    @Test("Items start as declared: one starting hidden is out, an always-available one is in the overflow menu")
    func startsAsDeclared() {
        reset()
        defer { reset() }
        let bar = Driver(CustomizableApp()).rows.first ?? ""
        #expect(bar.contains("SHARE") && bar.contains("PRINT") && bar.contains("FIXED"), "\(bar)")
        #expect(!bar.contains("MAIL") && !bar.contains("DOWNLOADS"), "\(bar)")
        #expect(bar.contains("»"), "the overflow menu: \(bar)")
    }

    @Test("The overflow menu holds a removed always-available item, which works from there")
    func overflowWorks() {
        reset()
        defer { reset() }
        let driver = Driver(CustomizableApp())
        driver.click("»")
        driver.click("DOWNLOADS")
        #expect(CustomizationProbe.shared.downloads == 1, "\(driver.rows)")
    }

    @Test("The bar's context menu opens the panel, whose checkbox puts an item in the bar, and keeps the choice")
    func checkboxAddsAnItem() {
        reset()
        defer { reset() }
        let driver = Driver(CustomizableApp())
        driver.openPanel()
        #expect(driver.rows.contains { $0.contains("MAIL") }, "the panel lists every item: \(driver.rows)")
        driver.click("□", after: "MAIL")
        driver.frames(2)
        driver.click("Done")
        #expect(driver.rows.first?.contains("MAIL") == true, "\(driver.rows)")
        #expect(CustomizationProbe.shared.store.hasValue(forKey: "TUI Toolbar Configuration main"))
        // Kept: a new run of the app finds it.
        #expect(Driver(CustomizableApp()).rows.first?.contains("MAIL") == true)
    }

    @Test("▼ moves an item past the next, in the bar")
    func arrowMovesAnItem() {
        reset()
        defer { reset() }
        let driver = Driver(CustomizableApp())
        driver.openPanel()
        driver.click("▼", after: "SHARE")
        driver.frames(2)
        // The panel follows: each row is still its own item's.
        let panel = driver.rows
        let share = panel.firstIndex { $0.contains("SHARE") && $0.contains("▼") }
        let print = panel.firstIndex { $0.contains("PRINT") && $0.contains("▼") }
        if let share, let print {
            #expect(print < share, "\(panel)")
        } else {
            Issue.record("\(panel)")
        }
        driver.click("Done")
        let bar = driver.rows.first ?? ""
        if let share = bar.range(of: "SHARE"), let print = bar.range(of: "PRINT") {
            #expect(print.lowerBound < share.lowerBound, "\(bar)")
        } else {
            Issue.record("\(bar)")
        }
    }

    /// The owner, 2026-10-28: re-ordering the customiser's items with the mouse.
    @Test("Dragging an item's grip down two rows moves it two places, each worked out from the order the last left")
    func gripDragMovesAnItem() {
        reset()
        defer { reset() }
        let driver = Driver(CustomizableApp())
        driver.openPanel()
        let before = driver.rows.filter { $0.contains("▼") }
        driver.dragGrip(of: "SHARE", rows: 2)
        let after = driver.rows.filter { $0.contains("▼") }
        let was = before.firstIndex { $0.contains("SHARE") }
        let now = after.firstIndex { $0.contains("SHARE") }
        if let was, let now {
            #expect(now == was + 2, "before \(before), after \(after)")
        } else {
            Issue.record("\(before) \(after)")
        }
    }

    @Test("The panel lists the items in the bars' order, and ▼ moves one past the next of its own place")
    func arrowsKeepToThePlace() {
        reset()
        defer { reset() }
        let driver = Driver(MixedPlacementsApp())
        driver.click("LEAD", button: .right)
        driver.click("Customize Toolbar")
        // The leading items, then the trailing one: the bar's order, not the
        // declaration's.
        let panel = driver.rows
        let lead = panel.firstIndex { $0.contains("LEAD") && $0.contains("▼") }
        let second = panel.firstIndex { $0.contains("SECOND") && $0.contains("▼") }
        let act = panel.firstIndex { $0.contains("ACT") && $0.contains("▼") }
        if let lead, let second, let act {
            #expect(lead < second && second < act, "\(panel)")
        } else {
            Issue.record("\(panel)")
        }
        // ▼ takes the first leading item past the second, not past the
        // trailing one, which would change nothing in the bar.
        driver.click("▼", after: "LEAD")
        driver.frames(2)
        let moved = driver.rows
        let movedLead = moved.firstIndex { $0.contains("LEAD") && $0.contains("▼") }
        let movedSecond = moved.firstIndex { $0.contains("SECOND") && $0.contains("▼") }
        if let movedLead, let movedSecond {
            #expect(movedSecond < movedLead, "the panel follows the bar: \(moved)")
        } else {
            Issue.record("\(moved)")
        }
        driver.click("Done")
        let bar = driver.rows.first ?? ""
        if let first = bar.range(of: "LEAD"), let next = bar.range(of: "SECOND") {
            #expect(next.lowerBound < first.lowerBound, "\(bar)")
        } else {
            Issue.record("\(bar)")
        }
    }

    @Test("An item the app hides is out of the bar, whatever the person chose")
    func appHidden() {
        reset()
        defer { reset() }
        CustomizationProbe.shared.hidesShare = true
        let bar = Driver(CustomizableApp()).rows.first ?? ""
        #expect(!bar.contains("SHARE") && bar.contains("PRINT"), "\(bar)")
    }

    @Test("The keyboard reaches the panel: Shift+F10 on a bar item, then Tab and Space in the panel")
    func keyboardCustomizes() {
        reset()
        defer { reset() }
        let app = HeadlessApp(KeyboardCustomizableApp(), width: 60, height: 14)
        var now: Int64 = 0
        func frames() {
            for _ in 0..<2 {
                now += 20_000_000
                app.frame(atNanos: now)
            }
        }
        func press(_ event: KeyEvent) {
            _ = app.send(event)
            frames()
        }
        frames()
        // The page has no stop, so Tab reaches the bar's button.
        press(KeyEvent(key: .tab))
        #expect(app.focusedID?.contains("button") == true, "\(String(describing: app.focusedID))")
        press(KeyEvent(key: .f10, shift: true))
        #expect(app.screen.contains { $0.stripped.contains("Customize Toolbar") }, "\(app.screen.map(\.stripped))")
        press(KeyEvent(key: .enter))
        let panel = app.screen.map(\.stripped)
        #expect(panel.contains { $0.contains("□") && $0.contains("OPEN") }, "\(panel)")
        // The first checkbox is NEW's, which is in the bar; OPEN's is the next stop
        // after NEW's arrows.
        for _ in 0..<3 { press(KeyEvent(key: .tab)) }
        press(KeyEvent(key: .space))
        #expect(app.screen.first?.stripped.contains("OPEN") == true, "\(app.screen.map(\.stripped))")
    }

    @Test("Reset forgets every choice")
    func resetForgets() {
        reset()
        defer { reset() }
        let driver = Driver(CustomizableApp())
        driver.openPanel()
        driver.click("□", after: "MAIL")
        driver.frames(2)
        driver.click("Reset")
        driver.click("Done")
        #expect(driver.rows.first?.contains("MAIL") == false, "\(driver.rows)")
        #expect(!CustomizationProbe.shared.store.hasValue(forKey: "TUI Toolbar Configuration main"))
    }

    /// The owner, 2026-10-28, afternoon list #41: the bar's own items dragged
    /// while the toolbar is customized, as on macOS.
    @Test("Dragged sideways in the bar while customizing, an item moves past each neighbour it crosses")
    func barDragReorders() {
        reset()
        defer { reset() }
        let driver = Driver(DraggableApp())
        driver.click("BETA", button: .right)
        driver.click("Customize Toolbar")
        // Past GAMMA ("GAMMA" and the gap after it), and no further.
        driver.dragBarItem("BETA", across: 6)
        let bar = driver.rows.first ?? ""
        if let beta = bar.range(of: "BETA"), let gamma = bar.range(of: "GAMMA"), let kept = bar.range(of: "KEPT") {
            #expect(gamma.lowerBound < beta.lowerBound && beta.lowerBound < kept.lowerBound, "\(bar)")
        } else {
            Issue.record("\(driver.rows)")
        }
        // And back, past GAMMA then ALPHA.
        driver.dragBarItem("BETA", across: -20)
        let back = driver.rows.first ?? ""
        if let beta = back.range(of: "BETA"), let alpha = back.range(of: "ALPHA") {
            #expect(beta.lowerBound < alpha.lowerBound, "\(back)")
        } else {
            Issue.record("\(driver.rows)")
        }
        #expect(driver.rows.contains { $0.contains("Done") }, "the panel stays open: \(driver.rows)")
    }

    @Test("Dragged off the bar while customizing, an item leaves it; one the person may not remove stays")
    func barDragRemoves() {
        reset()
        defer { reset() }
        let driver = Driver(DraggableApp())
        driver.click("BETA", button: .right)
        driver.click("Customize Toolbar")
        driver.dragBarItem("GAMMA", across: 0, down: 3)
        #expect(driver.rows.first?.contains("GAMMA") == false, "\(driver.rows)")
        #expect(driver.rows.contains { $0.contains("Done") }, "the panel stays open: \(driver.rows)")
        driver.dragBarItem("KEPT", across: 0, down: 3)
        #expect(driver.rows.first?.contains("KEPT") == true, "\(driver.rows)")
        // One row under the bar is still the bar's: nothing is taken out.
        driver.dragBarItem("BETA", across: 0, down: 1)
        #expect(driver.rows.first?.contains("BETA") == true, "\(driver.rows)")
        driver.click("Done")
        #expect(driver.rows.first?.contains("GAMMA") == false, "kept: \(driver.rows)")
    }

    @Test("While customizing, a bar item takes no click; afterwards it does again")
    func barItemInertWhileCustomizing() {
        reset()
        defer { reset() }
        let driver = Driver(DraggableApp())
        driver.click("ALPHA")
        #expect(CustomizationProbe.shared.taps == 1)
        driver.click("BETA", button: .right)
        driver.click("Customize Toolbar")
        driver.click("ALPHA")
        #expect(CustomizationProbe.shared.taps == 1, "\(driver.rows)")
        #expect(driver.rows.contains { $0.contains("Done") }, "nor does it close the panel: \(driver.rows)")
        driver.click("Done")
        driver.click("ALPHA")
        #expect(CustomizationProbe.shared.taps == 2)
    }

    @Test("An item dragged off the bar goes in a puff where it was let go, gone after a third of a second")
    func barDragPoofs() {
        reset()
        defer { reset() }
        let driver = Driver(DraggableApp())
        driver.click("BETA", button: .right)
        driver.click("Customize Toolbar")
        guard let bar = driver.rows.first, let found = bar.range(of: "GAMMA") else {
            Issue.record("\(driver.rows)")
            return
        }
        let x = bar.distance(from: bar.startIndex, to: found.lowerBound)
        func cell(_ row: Int, _ column: Int) -> Character? {
            let line = Array(driver.rows[row])
            return line.indices.contains(column) ? line[column] : nil
        }
        driver.dragBarItem("GAMMA", across: 0, down: 3)
        // The release's frame and the next: the puff's first frame, a star.
        #expect(cell(3, x) == "*", "\(driver.rows)")
        // Its second, five sixtieths of a second in (the frames are 20 ms
        // apart): it opens.
        driver.frames(4)
        #expect(cell(3, x) == "\u{273B}" && cell(3, x - 1) == ".", "\(driver.rows)")
        driver.frames(15)
        #expect(!driver.rows.contains { $0.contains("\u{273B}") || $0.contains("\u{273A}") }, "\(driver.rows)")
        #expect(cell(3, x) != "*", "\(driver.rows)")
        // One the person may not take out goes in no puff.
        driver.dragBarItem("KEPT", across: 0, down: 3)
        #expect(!driver.rows.contains { $0.contains("*") }, "\(driver.rows)")
    }
}
