//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitFilePanelsAppKit re-exports nothing: it is imported beside the module whose view it extends (its Exports.swift).
#if canImport(AppKit)
    import TUIkitFilePanelsAppKit
    import TUIkitFoundation

    let value = Text("Open").fileDialogSystemIcons()
#else
    let value = "TUIkitFilePanelsAppKit is empty off Apple platforms"
#endif

print("UsesTUIkitFilePanelsAppKit: \(String(reflecting: type(of: value)))")
