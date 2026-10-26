//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIFilePanelsAppKit re-exports nothing: it is imported beside the module whose view it extends (its Exports.swift).
#if canImport(AppKit)
    import TUIFilePanelsAppKit
    import TUIFoundation

    let value = Text("Open").fileDialogSystemIcons()
#else
    let value = "TUIFilePanelsAppKit is empty off Apple platforms"
#endif

print("UsesTUIFilePanelsAppKit: \(String(reflecting: type(of: value)))")
