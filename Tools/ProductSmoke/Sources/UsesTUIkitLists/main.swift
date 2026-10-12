//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitLists

let view = List { Text("A row") }

print("UsesTUIkitLists: \(String(reflecting: type(of: view)))")
