//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUITextInput re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUITextInput` gives an app the
// text inputs (`TextField`, `SecureField` and `TextEditor`)
// (the forms left for TUIForms at step C6, search for
// TUISearch at step C5, the pickers for TUIPickers at step C8, and the
// numeric controls for TUINumericControls at step C7). Beside what it gives
// an importer, it keeps TUIFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIFoundation compiled these files (until
// step B7). Each file
// imports TUIFoundation itself all the same: a closure it passes to a
// module that only this file's re-export reaches would carry a run-time
// main-actor check (CONTRIBUTING.md, "Crossing a module boundary"). The
// umbrella, Sources/TUI, re-exports this module beside TUIFoundation,
// and so do TUIColorPicker and TUISearch.
@_exported import TUIFoundation
