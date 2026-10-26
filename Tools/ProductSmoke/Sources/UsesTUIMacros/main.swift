//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIMacros re-exports nothing: it is imported beside the module whose `Animatable` the macro conforms a type
// to, TUICore, which the product brings.
import TUICore
import TUIMacros

@Animatable
struct Level {
    var value: Double
}

let value = Level(value: 0.5).animatableData

print("UsesTUIMacros: \(String(reflecting: type(of: value)))")
