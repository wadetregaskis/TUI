//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICurveEditors

// A curve editor, and TUIImage's `ASCIIToneCurve` through the re-exports.
let view = ToneCurveEditorPanel(stops: .constant([ASCIIToneCurve.Stop]()), isPresented: .constant(false))

print("UsesTUICurveEditors: \(String(reflecting: type(of: view)))")
