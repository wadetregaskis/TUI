//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIPickers

let view = Picker("Pick", selection: .constant(1)) { Text("One").tag(1) }

print("UsesTUIPickers: \(String(reflecting: type(of: view)))")
