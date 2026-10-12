//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitPickers

let view = Picker("Pick", selection: .constant(1)) { Text("One").tag(1) }

print("UsesTUIkitPickers: \(String(reflecting: type(of: view)))")
