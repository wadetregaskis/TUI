//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameworkModules.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The modules that are the framework. A composite of theirs stays out of the
/// memo: its body forwards, what it reads that no key sees (a handler's hover, a
/// style configuration) is its own business, and the memo at the app's view above
/// it decides for the whole. `PlainMemoCorrectnessTests` holds this list to
/// `Sources/`, so a new module cannot be left off it.
///
/// By name, once per type, since it has to tell apart every type in the program
/// and nothing else about a type says where it was declared: a conformance
/// declared by each of a few hundred framework views would be a thing to forget
/// on each, where this is one list and a test.
package enum FrameworkModules {
    package static let names: Set<Substring> = [
        "TUI", "TUIApp", "TUIAppKit", "TUIBitmaps", "TUIChrome", "TUIColorPicker", "TUICommands",
        "TUICore", "TUICurveEditors", "TUIDocuments", "TUIEffects", "TUIFilePanelImages", "TUIFilePanels", "TUIFilePanelsAppKit", "TUIForms",
        "TUIFoundation", "TUIGrid", "TUIImage", "TUILists", "TUIMenus", "TUINavigation", "TUINumericControls",
        "TUIPickers", "TUIPresentation", "TUIScenes", "TUISearch", "TUIStrings", "TUIStyling", "TUITabImages",
        "TUITables", "TUITabs", "TUITerminalHost", "TUITesting", "TUITextInput", "TUIView", "Swift",
    ]

    /// Whether `type` was declared in one of them. A view of the app's own
    /// generic over a framework view is the app's; the reverse is not.
    static func declares(_ type: Any.Type) -> Bool {
        names.contains(String(reflecting: type).prefix { $0 != "." })
    }
}
