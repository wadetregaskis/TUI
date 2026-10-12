//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitMacros re-exports nothing: it is imported beside the module whose `Animatable` the macro conforms a type
// to, TUIkitCore, which the product brings.
import TUIkitCore
import TUIkitMacros

@Animatable
struct Level {
    var value: Double
}

let value = Level(value: 0.5).animatableData

print("UsesTUIkitMacros: \(String(reflecting: type(of: value)))")
