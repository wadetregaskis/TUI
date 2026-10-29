//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuTypeSelectTests.swift
//
//  Type select in an open pop-up menu: a typed character moves the highlight
//  to the row whose title it starts, in whichever menu open the keys are in —
//  by the rule a `List` and a `Picker`'s drop-down use (`TypeSelectBuffer`),
//  a row found by its title from its first letter (a toggle row's mark is not
//  its title), and every character type select takes kept from the bare key
//  equivalents, a row's own included (the owner's ruling B77-KEYTIME).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
@testable import TUITestSupport

@MainActor
private final class Chosen {
    var log: [String] = []
    var showsHidden = false
    var binding: Binding<Bool> { Binding(get: { self.showsHidden }, set: { self.showsHidden = $0 }) }
}

private struct TypeSelectMenuApp: App {
    var chosen = Chosen()

    var body: some Scene {
        WindowGroup {
            Menu("File") {
                Button("Open") { chosen.log.append("Open") }
                Menu("Copy") {
                    Button("As Text") { chosen.log.append("As Text") }
                    Button("As Link") { chosen.log.append("As Link") }
                }
                Toggle("Show Hidden", isOn: chosen.binding)
                Button("Export") { chosen.log.append("Export") }
                    .keyboardShortcut("x", modifiers: [])
                Button("Delete") { chosen.log.append("Delete") }
            }
        }
    }
}

@MainActor
@Suite("Type select in a pop-up menu")
struct MenuTypeSelectTests {
    @MainActor
    private final class Driver {
        let app: HeadlessApp<TypeSelectMenuApp>
        private var now: Int64 = 0

        init(_ scene: TypeSelectMenuApp) {
            app = HeadlessApp(scene, width: 50, height: 16)
            frame()
            frame()
            // Opened from the keyboard: the first row highlighted.
            key(.enter)
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

    /// A character Option composed (`ƒ` for ⌥F where the terminal does not send
    /// Option as Alt) is the Option chord's: type select leaves it, so the
    /// chord can switch menus or reach a shortcut (2026-10-29: a focused List
    /// or an open menu swallowed it).
    @Test("Type select leaves a character Option composed")
    func composedCharacterDeclined() {
        let composed = KeyEvent(key: .character("ƒ"), pasteAttachments: [], optionComposedKey: .character("f"))
        #expect(!TypeSelectBuffer.takes(composed))
        #expect(TypeSelectBuffer.takes(KeyEvent(key: .character("ƒ"))), "the same character typed is taken")
    }

    @Test("A typed character highlights the row its title starts, and Return chooses it")
    func typingFindsTheRow() {
        let chosen = Chosen()
        let driver = Driver(TypeSelectMenuApp(chosen: chosen))
        driver.type("de")
        driver.key(.enter)
        #expect(chosen.log == ["Delete"], "\(chosen.log)")
    }

    @Test("In an entered submenu the keys find its rows, a first character the next match")
    func typingInASubmenu() {
        let chosen = Chosen()
        let driver = Driver(TypeSelectMenuApp(chosen: chosen))
        driver.type("c")
        driver.key(.right)
        driver.type("a")
        driver.key(.enter)
        #expect(chosen.log == ["As Link"], "from As Text, a first 'a' is the next row it starts: \(chosen.log)")
    }

    @Test("A toggle row is found by its title, not its mark")
    func toggleTitle() {
        let chosen = Chosen()
        let driver = Driver(TypeSelectMenuApp(chosen: chosen))
        driver.type("sh")
        driver.key(.enter)
        #expect(chosen.showsHidden, "Return flipped the toggle the prefix found")
    }

    @Test("A character is type select's even where a row's bare key equivalent is on it")
    func keepsAKeyEquivalentsKey() {
        let chosen = Chosen()
        let driver = Driver(TypeSelectMenuApp(chosen: chosen))
        driver.type("x")
        #expect(chosen.log.isEmpty, "no key equivalent fired: \(chosen.log)")
        // No title starts with x: the highlight stays on the first row.
        driver.key(.enter)
        #expect(chosen.log == ["Open"], "\(chosen.log)")
    }
}
