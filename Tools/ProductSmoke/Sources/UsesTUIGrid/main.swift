//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIGrid

let view = Grid {
    GridRow {
        Text("A")
        Text("B")
    }
}

print("UsesTUIGrid: \(String(reflecting: type(of: view)))")
