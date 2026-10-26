//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIAppKit re-exports nothing: it is imported beside the module whose types it bridges (its Exports.swift).
#if canImport(AppKit)
    import AppKit
    import TUIAppKit
    import TUIFoundation

    let value = Color(nsColor: .red)
#else
    let value = "TUIAppKit is empty off Apple platforms"
#endif

print("UsesTUIAppKit: \(String(reflecting: type(of: value)))")
