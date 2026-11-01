//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUITesting

// A view run with no terminal, a key pressed, and the screen read back.
struct Counter: View {
    @State private var count = 0

    var body: some View {
        Button("Count: \(count)") { count += 1 }
    }
}

@MainActor
func run() {
    let app = TestApp(width: 40, height: 3) { Counter() }
    app.press(.space)
    print("UsesTUITesting: \(app.screen.lines[0])")
    guard app.screen.contains("Count: 1") else { fatalError("the key did not reach the button") }
}

MainActor.assumeIsolated { run() }
