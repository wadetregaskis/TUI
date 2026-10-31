//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFilePanelImages

// The file panels' picture previews, which only this product brings in.
let view = Text("Panel").fileDialogPicturePreviews()

print("UsesTUIFilePanelImages: \(String(reflecting: type(of: view)))")
