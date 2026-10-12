//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitColorEditors

// An editor panel, and TUIkitStyling's `Gradient` through the re-exports.
let view = GradientEditorPanel(
    gradient: .constant(Gradient(colors: [.red, .blue])), isPresented: .constant(false))

print("UsesTUIkitColorEditors: \(String(reflecting: type(of: view)))")
