//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitGrid

let view = Grid {
    GridRow {
        Text("A")
        Text("B")
    }
}

print("UsesTUIkitGrid: \(String(reflecting: type(of: view)))")
