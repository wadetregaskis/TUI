//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

let value = FrameBuffer(lines: ["Core"])

print("UsesTUICore: \(String(reflecting: type(of: value)))")
