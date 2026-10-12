//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitMenus

let view = Menu("Menu") { Button("Item") {} }

print("UsesTUIkitMenus: \(String(reflecting: type(of: view)))")
