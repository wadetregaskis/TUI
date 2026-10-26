//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIBitmaps

// `Image`'s bitmap path.
let view = AsyncImage(url: URL(string: "file:///dev/null"))

print("UsesTUIBitmaps: \(String(reflecting: type(of: view)))")
