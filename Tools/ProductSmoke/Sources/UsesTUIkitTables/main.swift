//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitTables

struct Row: Identifiable {
    let id: Int
    let name: String
}

// A table, and TUIkitLists' `List` through the re-export.
let view = VStack {
    Table([Row(id: 1, name: "One")]) { TableColumn("Name", value: \.name) }
    List { Text("A row") }
}

print("UsesTUIkitTables: \(String(reflecting: type(of: view)))")
