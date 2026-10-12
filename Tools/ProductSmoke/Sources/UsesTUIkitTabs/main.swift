//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitTabs

let view = TabView { Tab("One", systemImage: "1.circle") { Text("One") } }

print("UsesTUIkitTabs: \(String(reflecting: type(of: view)))")
