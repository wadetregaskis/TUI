//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCurveEditors

// A curve editor, and TUIkitImage's `ASCIIToneCurve` through the re-exports.
let view = ToneCurveEditorPanel(stops: .constant([ASCIIToneCurve.Stop]()), isPresented: .constant(false))

print("UsesTUIkitCurveEditors: \(String(reflecting: type(of: view)))")
