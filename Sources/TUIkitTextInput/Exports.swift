//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitTextInput re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitTextInput` will give an app the
// text inputs, and the numeric controls until step C7 peels them into
// TUIkitNumericControls, once per-module products ship (the forms left for
// TUIkitForms at step C6, search for TUIkitSearch at step C5, and the pickers
// for TUIkitPickers at step C8). Beside what it gives an importer, it keeps
// TUIkitFoundation's names, and through its own re-exports the lower and side
// modules', in scope in every file of this target, in both of its directories
// (Sources/TUIkitTextInput and TUIkitNumericControls), as they were while
// TUIkitFoundation compiled these files (until step B7). Each file
// imports TUIkitFoundation itself all the same: a closure it passes to a
// module that only this file's re-export reaches would carry a run-time
// main-actor check (CONTRIBUTING.md, "Crossing a module boundary"). The
// umbrella, Sources/TUIkit, re-exports this module beside TUIkitFoundation,
// and so do TUIkitColorPicker and TUIkitSearch.
@_exported import TUIkitFoundation
