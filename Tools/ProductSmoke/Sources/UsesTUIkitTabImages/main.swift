//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitTabImages

// `Tab`'s `image:` initialisers, which find the named image as `Image(_:bundle:)` does.
let view = TabView { Tab("One", image: "one") { Text("One") } }

print("UsesTUIkitTabImages: \(String(reflecting: type(of: view)))")
