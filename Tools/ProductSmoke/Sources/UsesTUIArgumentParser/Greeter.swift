//  🖥️ TUI — A Terminal UI framework for Swift
//  Greeter.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIArgumentParser

// A command line parsed, then an app run from it. verify-products.sh runs this with no terminal, which is where the
// launch ends up here, and asks for its help and gives it a mistake.
struct Greeter: App {
    var name = "nobody"

    var body: some Scene {
        WindowGroup { Text("Hello, \(name)") }
    }

    static func runWithoutTerminal(_ situation: NoTerminal) async -> NoTerminal.Outcome {
        print("UsesTUIArgumentParser: reached the app's launch")
        return .exit(0)
    }
}

// `@main`, and so not a main.swift: a top-level `await GreeterCommand.main()` compiled to ParsableCommand's synchronous
// `main()`, with a warning that nothing was awaited, and exited with a failure at launch (measured on Swift 6.4.0).
@main
struct GreeterCommand: AppCommand {
    @Option(help: "Who to greet.")
    var name = "world"

    var app: some App { Greeter(name: name) }
}
