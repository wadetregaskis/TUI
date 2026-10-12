//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitNumericControls

let view = Slider(value: .constant(0.5))

print("UsesTUIkitNumericControls: \(String(reflecting: type(of: view)))")
