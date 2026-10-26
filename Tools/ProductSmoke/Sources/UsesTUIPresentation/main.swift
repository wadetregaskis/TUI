//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIPresentation

let view = Text("Presentation").alert("Alert", isPresented: .constant(false)) { Button("OK") {} }

print("UsesTUIPresentation: \(String(reflecting: type(of: view)))")
