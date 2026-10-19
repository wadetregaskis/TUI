//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerTypeSelectTests.swift
//
//  Type select in an open `Picker` drop-down: a typed character moves the
//  highlight to the option it starts, as in a `List` or a `Table` — the same
//  characters, the same second's pause, the same match from the highlight
//  (`TypeSelectBuffer`) — and the first of a prefix gives way to an app's
//  shortcut on it, as the list's does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitPickers
@testable import TUIkitTestSupport

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
                }
                // An app shortcut on a bare key, which the first character of
                // a prefix gives way to.
                Button("Shortcut") { fruit.shortcuts.append("x") }
                    .keyboardShortcut("x", modifiers: [])
            }
        }
    }
}

@MainActor
@Suite("Type select in a Picker's drop-down")
struct PickerTypeSelectTests {
    @MainActor
    private final class Driver {
        let app: HeadlessApp<FruitApp>
        private var now: Int64 = 0

        init(_ scene: FruitApp) {
            app = HeadlessApp(scene, width: 40, height: 14)
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

    @Test("The first character of a prefix gives way to an app's shortcut on it")
    func givesWayToAShortcut() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.key(.enter)
        driver.type("x")
        #expect(fruit.shortcuts == ["x"], "the shortcut fired: \(fruit.shortcuts)")
    }

    @Test("A closed drop-down takes no characters")
    func closedTakesNothing() {
        let fruit = Fruit()
        let driver = Driver(FruitApp(fruit: fruit))
        driver.type("c")
        #expect(fruit.choice == "Apple", "\(fruit.choice)")
    }
}
