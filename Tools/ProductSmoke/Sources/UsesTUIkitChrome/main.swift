//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitChrome

// What is drawn around the content: the status bar and `.help`.
let view = VStack {
    Text("Chrome").help("A tooltip")
    StatusBar()
}

print("UsesTUIkitChrome: \(String(reflecting: type(of: view)))")
