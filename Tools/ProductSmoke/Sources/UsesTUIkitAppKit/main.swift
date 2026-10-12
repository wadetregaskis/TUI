//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitAppKit re-exports nothing: it is imported beside the module whose types it bridges (its Exports.swift).
#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit
    import TUIkitFoundation

    let value = Color(nsColor: .red)
#else
    let value = "TUIkitAppKit is empty off Apple platforms"
#endif

print("UsesTUIkitAppKit: \(String(reflecting: type(of: value)))")
