//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitSearch

let view = Text("Search").searchable(text: .constant(""))

print("UsesTUIkitSearch: \(String(reflecting: type(of: view)))")
