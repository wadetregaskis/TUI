//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitForms

let view = Form { LabeledContent("Name", value: "TUIkit") }

print("UsesTUIkitForms: \(String(reflecting: type(of: view)))")
