//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitNavigation

let view = NavigationStack { Text("Root") }

print("UsesTUIkitNavigation: \(String(reflecting: type(of: view)))")
