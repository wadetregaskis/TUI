//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitTextInput re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitTextInput` will give an app the
// text inputs, and the pickers, forms, search and numeric controls until steps
// C5 to C8 peel them into TUIkitSearch, TUIkitForms, TUIkitNumericControls and
// TUIkitPickers, once per-module products ship. Beside what it gives an
// importer, it keeps TUIkitFoundation's names, and through its own re-exports
// the lower and side modules', in scope in every file of this target, in all
// five of its directories (Sources/TUIkitTextInput, TUIkitPickers,
// TUIkitForms, TUIkitSearch and TUIkitNumericControls), as they were while
// TUIkitFoundation compiled these files (until step B7). Each file imports
// TUIkitFoundation itself all the same: a closure it passes to a module that
// only this file's re-export reaches would carry a run-time main-actor check
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation, and so does
// TUIkitColorPicker.
@_exported import TUIkitFoundation
