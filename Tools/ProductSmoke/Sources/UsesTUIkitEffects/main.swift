//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitEffects

let view = Text("Effects").transition(.opacity)

print("UsesTUIkitEffects: \(String(reflecting: type(of: view)))")
