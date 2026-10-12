//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

let value = FrameBuffer(lines: ["Core"])

print("UsesTUIkitCore: \(String(reflecting: type(of: value)))")
