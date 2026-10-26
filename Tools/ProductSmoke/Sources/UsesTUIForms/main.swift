//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIForms

let view = Form { LabeledContent("Name", value: "TUI") }

print("UsesTUIForms: \(String(reflecting: type(of: view)))")
