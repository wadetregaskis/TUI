//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUITables

struct Row: Identifiable {
    let id: Int
    let name: String
}

// A table, and TUILists' `List` through the re-export.
let view = VStack {
    Table([Row(id: 1, name: "One")]) { TableColumn("Name", value: \.name) }
    List { Text("A row") }
}

print("UsesTUITables: \(String(reflecting: type(of: view)))")
