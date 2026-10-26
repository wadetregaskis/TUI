//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIChrome

// What is drawn around the content: the status bar and `.help`.
let view = VStack {
    Text("Chrome").help("A tooltip")
    StatusBar()
}

print("UsesTUIChrome: \(String(reflecting: type(of: view)))")
