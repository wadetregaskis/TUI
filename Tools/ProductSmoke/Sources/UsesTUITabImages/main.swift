//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUITabImages

// `Tab`'s `image:` initialisers, which find the named image as `Image(_:bundle:)` does.
let view = TabView { Tab("One", image: "one") { Text("One") } }

print("UsesTUITabImages: \(String(reflecting: type(of: view)))")
