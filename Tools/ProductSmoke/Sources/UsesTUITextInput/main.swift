//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUITextInput

let view = TextField("Name", text: .constant(""))

print("UsesTUITextInput: \(String(reflecting: type(of: view)))")
