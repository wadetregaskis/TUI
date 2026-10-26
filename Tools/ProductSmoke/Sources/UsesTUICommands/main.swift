//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICommands

let commands = CommandMenu("Note") { Button("Duplicate") {} }

print("UsesTUICommands: \(String(reflecting: type(of: commands)))")
