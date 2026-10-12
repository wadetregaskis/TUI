//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitPresentation

let view = Text("Presentation").alert("Alert", isPresented: .constant(false)) { Button("OK") {} }

print("UsesTUIkitPresentation: \(String(reflecting: type(of: view)))")
