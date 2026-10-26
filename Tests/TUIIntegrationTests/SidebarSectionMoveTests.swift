//  🖥️ TUI — A Terminal UI framework for Swift
//  SidebarSectionMoveTests.swift
//
//  A person reorders a customizable sidebar's sections (decisions B79): from
//  the keyboard on a section's header, as a list's row is moved, or by
//  dragging a header onto another; the new order is written through the
//  `TabViewCustomization` binding.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Where the app keeps its customization, outside the views.
@MainActor
private final class Store {
    var customization = TabViewCustomization()
    var binding: Binding<TabViewCustomization> {
        Binding(get: { self.customization }, set: { self.customization = $0 })
    }

    /// The section order written, read off the encoding (the order is the
    /// value's own, with no public reader).
    var sectionOrder: [String]? {
        guard let data = try? JSONEncoder().encode(customization),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["sectionOrder"] as? [String]
    }
}

@MainActor
@Suite("Moving a customizable sidebar's sections")
struct SidebarSectionMoveTests {
    private func sidebar(_ store: Store, bound: Bool = true) -> some View {
        let tabs = TabView(selection: .constant(0)) {
            Tab("Inbox", value: 0) { Text("INBOX BODY") }
            TabSection("Folders") {
                Tab("Work", value: 1) { Text("WORK BODY") }
            }
            .customizationID("folders")
            TabSection("Tags") {
                Tab("Red", value: 2) { Text("RED BODY") }
            }
            .customizationID("tags")
        }
        .tabViewStyle(.sidebarAdaptable)
        return Group {
            if bound { tabs.tabViewCustomization(store.binding) } else { tabs }
        }
    }

    /// Where `text` starts on screen, in cells.
    private func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
        for (y, line) in buffer.lines.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    /// Whether `first` is drawn above `second`.
    private func isAbove(_ first: String, _ second: String, in buffer: FrameBuffer) -> Bool {
        guard let top = cell(of: first, in: buffer), let bottom = cell(of: second, in: buffer) else { return false }
        return top.y < bottom.y
    }

    /// Puts the focus on the first section's header — the Folders fold.
    private func focusFolders(_ harness: InputChainHarness) -> Bool {
        guard let fold = harness.focusManager.registeredFocusIDsInActiveSection().first(where: { !$0.hasPrefix("list") })
        else { return false }
        harness.focusManager.focus(id: fold)
        return true
    }

    private static let pickUp = KeyEvent(key: .character("r"), ctrl: true)

    @Test("Ctrl-R, Down and Return move a section, written through the binding when put down")
    func keyboardMove() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        #expect(isAbove("Folders", "Tags", in: harness.frame(sidebar(store))))
        guard focusFolders(harness) else {
            Issue.record("no section header to focus")
            return
        }
        harness.frame(sidebar(store))
        harness.press(Self.pickUp)
        harness.press(KeyEvent(key: .down))
        let held = harness.frame(sidebar(store))
        #expect(isAbove("Tags", "Folders", in: held), "the section in hand shows where it would go: \(held.lines.map(\.stripped))")
        #expect(store.sectionOrder == nil, "nothing is written until it is put down")
        harness.press(KeyEvent(key: .enter))
        let placed = harness.frame(sidebar(store))
        #expect(store.sectionOrder == ["tags", "folders"], "\(String(describing: store.sectionOrder))")
        #expect(isAbove("Tags", "Folders", in: placed), "\(placed.lines.map(\.stripped))")
        // The focus went with the section: Return folds Folders now.
        harness.press(KeyEvent(key: .enter))
        let folded = harness.frame(sidebar(store))
        #expect(
            !folded.lines.map(\.stripped).joined().contains("Work") && folded.lines.map(\.stripped).joined().contains("Red"),
            "\(folded.lines.map(\.stripped))")
    }

    @Test("Escape puts a section in hand back, and writes nothing")
    func escapeCancels() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        harness.frame(sidebar(store))
        guard focusFolders(harness) else {
            Issue.record("no section header to focus")
            return
        }
        harness.frame(sidebar(store))
        harness.press(Self.pickUp)
        harness.press(KeyEvent(key: .down))
        harness.frame(sidebar(store))
        harness.press(KeyEvent(key: .escape))
        let back = harness.frame(sidebar(store))
        #expect(isAbove("Folders", "Tags", in: back), "\(back.lines.map(\.stripped))")
        #expect(store.sectionOrder == nil)
    }

    /// The keys that place or put back a section in hand are its header's:
    /// once the focus has left the header, by a click on a tab, say, they
    /// cannot reach it, so the section goes back, as a list puts back a row
    /// in hand when it loses the focus. It stayed in hand, drawn where it
    /// would go, until the focus came back to that header and a key with it.
    @Test("A section in hand goes back when the focus leaves its header")
    func focusLeavingPutsItBack() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        harness.frame(sidebar(store))
        guard focusFolders(harness) else {
            Issue.record("no section header to focus")
            return
        }
        harness.frame(sidebar(store))
        harness.press(Self.pickUp)
        harness.press(KeyEvent(key: .down))
        #expect(isAbove("Tags", "Folders", in: harness.frame(sidebar(store))), "precondition: the section is in hand")
        guard let list = harness.focusManager.registeredFocusIDsInActiveSection().first(where: { $0.hasPrefix("list") })
        else {
            Issue.record("no list to focus")
            return
        }
        harness.focusManager.focus(id: list)
        harness.frame(sidebar(store))
        let back = harness.frame(sidebar(store))
        #expect(isAbove("Folders", "Tags", in: back), "\(back.lines.map(\.stripped))")
        // Back on the header, the arrows move the focus, not a section.
        guard focusFolders(harness) else { return }
        harness.frame(sidebar(store))
        harness.press(KeyEvent(key: .down))
        harness.press(KeyEvent(key: .enter))
        let after = harness.frame(sidebar(store))
        #expect(isAbove("Folders", "Tags", in: after), "\(after.lines.map(\.stripped))")
        #expect(store.sectionOrder == nil, "\(String(describing: store.sectionOrder))")
    }

    /// A move orders the sections the sidebar shows with a header; the
    /// stored order holds others too — one whose tabs are all hidden now, one
    /// with no header. Written over with the moved ones alone, the others
    /// lost their places: shown again, each went back to where it was
    /// declared, and moving one section moved another.
    @Test("Moving a section keeps the stored places of the sections it did not move")
    func moveKeepsOtherSectionsPlaces() throws {
        let store = Store()
        store.customization = try JSONDecoder().decode(
            TabViewCustomization.self,
            from: Data(#"{"sidebarVisibility": {"old": "hidden"}, "sectionOrder": ["tags", "archive", "folders"]}"#.utf8))
        func view() -> some View {
            TabView(selection: .constant(0)) {
                Tab("Inbox", value: 0) { Text("INBOX BODY") }
                TabSection("Folders") {
                    Tab("Work", value: 1) { Text("WORK BODY") }
                }
                .customizationID("folders")
                TabSection("Archive") {
                    Tab("Old", value: 3) { Text("OLD BODY") }.customizationID("old")
                }
                .customizationID("archive")
                TabSection("Tags") {
                    Tab("Red", value: 2) { Text("RED BODY") }
                }
                .customizationID("tags")
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization(store.binding)
        }
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(view())
        #expect(
            isAbove("Tags", "Folders", in: drawn) && cell(of: "Archive", in: drawn) == nil,
            "precondition: the stored order, with the archive's only tab hidden: \(drawn.lines.map(\.stripped))")
        // The first section header: the Tags fold.
        guard focusFolders(harness) else {
            Issue.record("no section header to focus")
            return
        }
        harness.frame(view())
        harness.press(Self.pickUp)
        harness.press(KeyEvent(key: .down))
        harness.press(KeyEvent(key: .enter))
        let moved = harness.frame(view())
        #expect(isAbove("Folders", "Tags", in: moved), "\(moved.lines.map(\.stripped))")
        #expect(store.sectionOrder == ["folders", "archive", "tags"], "\(String(describing: store.sectionOrder))")
    }

    @Test("Without a customization bound, Ctrl-R on a section header moves nothing")
    func unboundDoesNothing() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        harness.frame(sidebar(store, bound: false))
        guard focusFolders(harness) else {
            Issue.record("no section header to focus")
            return
        }
        harness.frame(sidebar(store, bound: false))
        harness.press(Self.pickUp)
        harness.press(KeyEvent(key: .down))
        let after = harness.frame(sidebar(store, bound: false))
        #expect(isAbove("Folders", "Tags", in: after), "\(after.lines.map(\.stripped))")
    }

    @Test("Dragging a section's header onto another's moves it there")
    func dragMove() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(sidebar(store))
        guard let folders = cell(of: "Folders", in: drawn), let tags = cell(of: "Tags", in: drawn) else {
            Issue.record("no headers in \(drawn.lines.map(\.stripped))")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: folders.x + 1, y: folders.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: folders.x + 2, y: folders.y))
        let moving = harness.frame(sidebar(store))
        #expect(cell(of: "Tags", in: moving)?.y == tags.y, "the headers keep their places as the drag begins")
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: tags.x + 1, y: tags.y))
        harness.frame(sidebar(store))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: tags.x + 1, y: tags.y))
        let dropped = harness.frame(sidebar(store))
        #expect(store.sectionOrder == ["tags", "folders"], "\(String(describing: store.sectionOrder))")
        #expect(isAbove("Tags", "Folders", in: dropped), "\(dropped.lines.map(\.stripped))")
    }

    @Test("A click on a movable section's header still folds it")
    func clickStillFolds() {
        let store = Store()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(sidebar(store))
        guard let folders = cell(of: "Folders", in: drawn) else {
            Issue.record("no header in \(drawn.lines.map(\.stripped))")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: folders.x + 1, y: folders.y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: folders.x + 1, y: folders.y))
        let folded = harness.frame(sidebar(store)).lines.map(\.stripped).joined(separator: "\n")
        #expect(!folded.contains("Work") && folded.contains("Red"), "\(folded)")
        #expect(store.sectionOrder == nil)
    }
}
