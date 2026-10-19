//  🖥️ TUIkit — Terminal UI Kit for Swift
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

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

@MainActor
@Suite("A Picker in a menu")
struct PickerInMenuTests {
    @MainActor
    private final class Driver {
        let app: HeadlessApp<PickerMenuApp>
        private var now: Int64 = 0

        init(_ scene: PickerMenuApp) {
            app = HeadlessApp(scene, width: 60, height: 20)
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
}
