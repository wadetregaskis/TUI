//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerTypeSelectTests.swift
//
//  Type select in an open `Picker` drop-down: a typed character moves the
//  highlight to the option it starts, as in a `List` or a `Table` — the same
//  characters, the same second's pause, the same match from the highlight
//  (`TypeSelectBuffer`). Unlike a list's, the first of a prefix does not give
//  way to an app's shortcut on it: the open drop-down holds the keyboard, and
//  the shortcut is behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPickers
import TUITesting
@testable import TUITestSupport

@MainActor
private final class Fruit {
    var choice = "Apple"
    var shortcuts: [String] = []
    var binding: Binding<String> { Binding(get: { self.choice }, set: { self.choice = $0 }) }
}

private struct FruitApp: App {
    var fruit = Fruit()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Fruit", selection: fruit.binding) {
                    Text("Apple").tag("Apple")
                    Text("Banana").tag("Banana")
                    Text("Blueberry").tag("Blueberry")
                    Text("Cherry").tag("Cherry")
                    Text("Date").tag("Date")
                }
                // A page's shortcut on a bare key an option starts with: behind
                // the open drop-down, which keeps the key.
                Button("Delete") { fruit.shortcuts.append("d") }
                    .keyboardShortcut("d", modifiers: [])
            }
        }
    }
}

@MainActor
@Suite("Type select in a Picker's drop-down")
struct PickerTypeSelectTests {
    @MainActor
    private final class Driver {
        let app: TestApp
        private var now: Int64 = 0

        init(_ scene: FruitApp) {
            app = TestApp(scene, width: 40, height: 14)
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

        func type(_ text: String) {
            for character in text { key(.character(character)) }
        }
    }

    @Test("Typed characters move the open drop-down's highlight to the option they start")
    func typingFindsTheOption() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.key(.enter)
        driver.type("bl")
        driver.key(.enter)
        #expect(fruit.choice == "Blueberry", "\(fruit.choice)")
    }

    @Test("A first character steps to the next option it starts, from the highlight")
    func firstCharacterSteps() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.key(.enter)
        driver.type("c")
        driver.key(.enter)
        #expect(fruit.choice == "Cherry", "\(fruit.choice)")
    }

    @Test("A first character finds an option, and fires no page shortcut behind the open drop-down")
    func keepsAShortcutsKey() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.key(.enter)
        driver.type("d")
        #expect(fruit.shortcuts.isEmpty, "the page's shortcut fired behind the drop-down: \(fruit.shortcuts)")
        driver.key(.enter)
        #expect(fruit.choice == "Date", "\(fruit.choice)")
    }

    @Test("A closed drop-down takes no characters, and a page shortcut has its key")
    func closedTakesNothing() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.type("c")
        #expect(fruit.choice == "Apple", "\(fruit.choice)")
        driver.type("d")
        #expect(fruit.shortcuts == ["d"], "\(fruit.shortcuts)")
        #expect(fruit.choice == "Apple", "\(fruit.choice)")
    }
}
