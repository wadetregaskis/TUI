//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusAfterMenuRemovesItsViewTests.swift
//
//  A menu item that removes the view its menu hangs from — a pop-up `Menu`'s
//  own control, or the view under a `.contextMenu` — leaves the focus with
//  that view's neighbour, the next control, as a control that removes itself
//  does (FocusSystem.md, "When a Control Loses Focus"). It went to the first
//  control on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
private final class Pressed {
    var log: [String] = []
}

/// Two buttons, a view that its own menu removes, and two buttons after it.
private struct Page: View {
    let pressed: Pressed
    let usesContextMenu: Bool
    @State private var isShown = true

    var body: some View {
        VStack(alignment: .leading) {
            Button("Alpha") { pressed.log.append("alpha") }
            Button("Bravo") { pressed.log.append("bravo") }
            if isShown {
                if usesContextMenu {
                    Text("Target").contextMenu {
                        Button("Keep") {}
                        Button("Remove") { isShown = false }
                    }
                } else {
                    Menu("Target") {
                        Button("Keep") {}
                        Button("Remove") { isShown = false }
                    }
                }
            }
            Button("Charlie") { pressed.log.append("charlie") }
            Button("Delta") { pressed.log.append("delta") }
        }
    }
}

@MainActor
@Suite("Focus after a menu removes the view it hangs from")
struct FocusAfterMenuRemovesItsViewTests {
    @Test("The focus goes to the next control", arguments: [false, true])
    func focusGoesToTheNextControl(usesContextMenu: Bool) {
        let pressed = Pressed()
        let app = TestApp(width: 40, height: 16) { Page(pressed: pressed, usesContextMenu: usesContextMenu) }
        // Alpha has the focus first; two Tabs reach the target.
        app.press(.tab, times: 2)
        if usesContextMenu {
            app.press(.f10, modifiers: .shift)
        } else {
            app.press(.enter)
        }
        // The keyboard opened it, on Keep: Down to Remove, and Return.
        app.press(.down)
        app.press(.enter)
        #expect(!app.screen.contains("Target"), "\(app.screen)")
        app.press(.enter)
        #expect(pressed.log == ["charlie"])
    }
}
