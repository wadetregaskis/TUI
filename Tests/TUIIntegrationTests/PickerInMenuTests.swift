//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerInMenuTests.swift
//
//  A `Picker` written in a pop-up menu is no control but its options as the
//  menu's rows, as SwiftUI's is (measured on macOS 15.8,
//  `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`): a submenu
//  titled by its label, the selected option checked — or, `.inline`, its label
//  over its options in the menu itself. It drew its own collapsed drop-down on
//  a line of the menu that the menu's arrows walked past.
//
//  Here rather than beside the menus' own tests because it takes both modules.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
private final class Sorting {
    var key = "Name"
    var binding: Binding<String> { Binding(get: { self.key }, set: { self.key = $0 }) }
}

private struct PickerMenuApp: App {
    var sorting = Sorting()
    var inline = false
    var disabled = false

    var body: some Scene {
        WindowGroup {
            Menu("View") {
                Button("Reload") {}
                if inline {
                    picker.pickerStyle(.inline)
                } else {
                    picker
                }
                Button("Close") {}
            }
        }
    }

    private var picker: some View {
        Picker("Sort", selection: sorting.binding) {
            Text("Name").tag("Name")
            Text("Date").tag("Date")
        }
        .disabled(disabled)
    }
}

/// Where an `.inline` picker stands among a menu's items, for its separators.
private enum InlinePlace {
    case first, last, besideDividers, twoInARow, besideSections, inASection, insideAnAppView
}

/// An `.inline` picker in a menu, placed as `place` says.
private struct InlineEdgesApp: App {
    var place = InlinePlace.first

    var body: some Scene {
        WindowGroup {
            Menu("View") { items }
        }
    }

    @ViewBuilder private var items: some View {
        switch place {
        case .first:
            sortPicker("Sort")
            Button("Close") {}
        case .last:
            Button("Open") {}
            sortPicker("Sort")
        case .besideDividers:
            Button("Open") {}
            Divider()
            sortPicker("Sort")
            Divider()
            Button("Close") {}
        case .twoInARow:
            sortPicker("Sort")
            sortPicker("Group")
        case .besideSections:
            Section("Head") { Button("Open") {} }
            sortPicker("Sort")
            Section { Button("Close") {} }
        case .inASection:
            Section("View") { sortPicker("Sort") }
            Button("Close") {}
        case .insideAnAppView:
            Button("Open") {}
            InlineSortPicker()
            Button("Close") {}
        }
    }
}

/// An inline picker inside a view of the app's own, whose body the menu does
/// not look into.
private struct InlineSortPicker: View {
    var body: some View { sortPicker("Sort") }
}

@MainActor
private func sortPicker(_ title: String) -> some View {
    Picker(title, selection: .constant("Name")) {
        Text("Name").tag("Name")
        Text("Date").tag("Date")
    }
    .pickerStyle(.inline)
}

@MainActor
@Suite("A Picker in a menu")
struct PickerInMenuTests {
    @MainActor
    private final class Driver<Scene: App> {
        let app: HeadlessApp
        private var now: Int64 = 0

        init(_ scene: Scene) {
            app = HeadlessApp(scene, width: 60, height: 24)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func key(_ key: Key) {
            app.send(KeyEvent(key: key))
            frame()
        }

        var text: String { app.screen.map(\.stripped).joined(separator: "\n") }
        func shows(_ label: String) -> Bool { app.screen.contains { $0.stripped.contains(label) } }
        func line(of label: String) -> String? { app.screen.map(\.stripped).first { $0.contains(label) } }

        /// The open menu's lines inside its border, trimmed, a separator as
        /// `-`.
        var menuLines: [String] {
            app.screen.map(\.stripped).compactMap { line in
                guard let first = line.firstIndex(of: "│"), let last = line.lastIndex(of: "│"), first < last else {
                    return nil
                }
                let inside = line[line.index(after: first)..<last].drop { $0 == " " }
                let trimmed = String(inside.reversed().drop { $0 == " " }.reversed())
                return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "─" } ? "-" : trimmed
            }
        }
    }

    /// The menu's lines with the inline picker placed as `place` says.
    private func lines(_ place: InlinePlace) -> [String] {
        let driver = Driver(InlineEdgesApp(place: place))
        driver.key(.enter)
        return driver.menuLines
    }

    @Test("It is a submenu of its options, the selected one checked, and choosing one selects it")
    func submenu() throws {
        let sorting = Sorting()
        let driver = Driver(PickerMenuApp(sorting: sorting))
        driver.key(.enter)
        let row = try #require(driver.line(of: "Sort"), "\(driver.text)")
        #expect(row.contains("▸"), "the picker is a submenu row: \(row)")
        #expect(!driver.shows("Date"), "its options are in the closed submenu: \(driver.text)")
        driver.key(.down)
        driver.key(.right)
        let name = try #require(driver.line(of: "Name"), "\(driver.text)")
        #expect(name.contains("✓ Name"), "the selected option is checked: \(name)")
        driver.key(.down)
        driver.key(.enter)
        #expect(sorting.key == "Date", "choosing Date selected it: \(sorting.key)")
        #expect(!driver.shows("Reload"), "and closed the menus: \(driver.text)")
    }

    @Test("A disabled picker's submenu opens, and its options cannot be chosen")
    func disabled() {
        let sorting = Sorting()
        let driver = Driver(PickerMenuApp(sorting: sorting, disabled: true))
        driver.key(.enter)
        driver.key(.down)
        driver.key(.right)
        #expect(driver.shows("Date"), "the submenu opened: \(driver.text)")
        driver.key(.down)
        driver.key(.enter)
        #expect(sorting.key == "Name", "a disabled option was chosen: \(sorting.key)")
    }

    @Test("An inline picker draws its options in the menu, under its label, the selected one checked")
    func inline() throws {
        let sorting = Sorting()
        let driver = Driver(PickerMenuApp(sorting: sorting, inline: true))
        driver.key(.enter)
        let label = try #require(driver.line(of: "Sort"), "\(driver.text)")
        #expect(!label.contains("▸"), "no submenu: \(label)")
        let name = try #require(driver.line(of: "Name"), "\(driver.text)")
        #expect(name.contains("✓ Name"), "\(name)")
        #expect(driver.shows("Date"), "\(driver.text)")
        // Reload, then the two options: the label is no row.
        driver.key(.down)
        driver.key(.down)
        driver.key(.enter)
        #expect(sorting.key == "Date", "the arrows reached the options: \(sorting.key)")
    }

    // An inline picker is set off as a `Section` is — the separators SwiftUI
    // builds round it are AppKit's to collapse, which draws none at the
    // menu's top or bottom and never two in a row (measured on macOS 15.8,
    // `Tools/SwiftUIProbes/Menu items and alert buttons/shown.out`).

    @Test("First in the menu, an inline picker has no separator above it")
    func inlineFirst() {
        #expect(lines(.first) == ["Sort", "✓ Name", "Date", "-", "Close"])
    }

    @Test("Last in the menu, an inline picker has no separator below it")
    func inlineLast() {
        #expect(lines(.last) == ["Open", "-", "Sort", "✓ Name", "Date"])
    }

    @Test("Beside a Divider the app wrote, an inline picker's separator is that one")
    func inlineBesideDividers() {
        #expect(lines(.besideDividers) == ["Open", "-", "Sort", "✓ Name", "Date", "-", "Close"])
    }

    @Test("Two inline pickers in a row have one separator between them")
    func inlineTwoInARow() {
        #expect(lines(.twoInARow) == ["Sort", "✓ Name", "Date", "-", "Group", "✓ Name", "Date"])
    }

    @Test("Between sections, an inline picker shares their separators")
    func inlineBesideSections() {
        #expect(lines(.besideSections) == ["Head", "Open", "-", "Sort", "✓ Name", "Date", "-", "Close"])
    }

    @Test("In a section, an inline picker is set off from the section's header and shares its last separator")
    func inlineInASection() {
        #expect(lines(.inASection) == ["View", "-", "Sort", "✓ Name", "Date", "-", "Close"])
    }

    @Test("Inside a view of the app's own, which the menu does not look into, it draws its own separators")
    func inlineInsideAnAppView() {
        #expect(lines(.insideAnAppView) == ["Open", "-", "Sort", "✓ Name", "Date", "-", "Close"])
    }
}
