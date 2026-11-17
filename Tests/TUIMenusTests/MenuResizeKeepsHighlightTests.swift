//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuResizeKeepsHighlightTests.swift
//
//  A terminal shrunk while a menu is open: the window of rows the menu shows
//  must still hold the highlighted row. It kept its scroll position instead, so
//  30×14 → 12×4 with Item 9 highlighted showed Items 0 to 2, and Return chose
//  Item 9, a row nobody could see (bug hunt, 2026-11-17). A pop-up menu, a
//  submenu and a context menu are one renderer, and each is checked here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

@MainActor
private final class Chosen {
    var log: [String] = []
}

/// Ten items, in the menu itself, in a submenu, or in a context menu.
private struct TenItemsApp: App {
    enum Kind { case popUp, submenu, context }

    var kind = Kind.popUp
    var chosen = Chosen()

    var body: some Scene {
        WindowGroup {
            switch kind {
            case .popUp:
                Menu("File") { items }
            case .submenu:
                Menu("File") { Menu("More") { items } }
            case .context:
                Text("Document").contextMenu { items }
            }
        }
    }

    private var items: some View {
        ForEach(0..<10, id: \.self) { index in
            Button("Item \(String(index))") { chosen.log.append("Item \(String(index))") }
        }
    }
}

@MainActor
@Suite("A menu shrunk by a resize keeps its highlighted row in sight")
struct MenuResizeKeepsHighlightTests {
    @MainActor
    private final class Driver {
        let app: TestApp
        private var now: Int64 = 0

        init(_ scene: TenItemsApp) {
            app = TestApp(scene, width: 30, height: 14)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func key(_ key: Key, shift: Bool = false, times: Int = 1) {
            for _ in 0..<times {
                app.send(KeyEvent(key: key, shift: shift))
                frame()
            }
        }

        /// The screen's text, one string.
        var text: String { app.screen.lines.joined(separator: "\n") }
    }

    @Test("Shrinking the terminal scrolls the menu to its highlighted row, and Return chooses the row in sight",
          arguments: [TenItemsApp.Kind.popUp, .submenu, .context])
    fileprivate func shrinkKeepsTheHighlight(kind: TenItemsApp.Kind) {
        let chosen = Chosen()
        let driver = Driver(TenItemsApp(kind: kind, chosen: chosen))
        switch kind {
        case .popUp:
            driver.key(.enter)
        case .submenu:
            driver.key(.enter)
            driver.key(.right)
        case .context:
            driver.key(.f10, shift: true)
        }
        // From Item 0 (where the keyboard opened it) down to Item 9.
        driver.key(.down, times: 9)
        #expect(driver.text.contains("Item 9"), "the highlight is drawn before the resize:\n\(driver.text)")

        driver.app.resize(width: 12, height: 4)
        driver.frame()
        driver.frame()
        #expect(driver.text.contains("Item 9"), "\(kind): the highlighted row is out of sight:\n\(driver.text)")

        driver.key(.enter)
        #expect(chosen.log == ["Item 9"], "\(kind): \(chosen.log)")
    }
}
