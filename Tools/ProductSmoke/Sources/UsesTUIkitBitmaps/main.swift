//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitBitmaps

// `Image`'s bitmap path.
let view = AsyncImage(url: URL(string: "file:///dev/null"))

print("UsesTUIkitBitmaps: \(String(reflecting: type(of: view)))")
