//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitTextInput

let view = TextField("Name", text: .constant(""))

print("UsesTUIkitTextInput: \(String(reflecting: type(of: view)))")
