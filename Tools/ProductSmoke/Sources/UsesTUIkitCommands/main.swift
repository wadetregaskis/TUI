//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCommands

let commands = CommandMenu("Note") { Button("Duplicate") {} }

print("UsesTUIkitCommands: \(String(reflecting: type(of: commands)))")
