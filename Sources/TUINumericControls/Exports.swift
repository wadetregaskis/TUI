//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUINumericControls re-exports the module it is built on, as each module
// of the split re-exports its direct dependencies
// (Documentation/Historical/Module split plan, revision 4, §4), so `import
// TUINumericControls` gives an app the numeric controls (`Slider`,
// `Stepper`, `Gauge` and `ProgressView`, with their styles and
// `.trackStyle`). Beside what it gives an
// importer, it keeps
// TUIFoundation's names, and through its own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUITextInput compiled these files (until step C7); each file imports
// TUIFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUI, re-exports this module beside
// TUIFoundation, and so does TUIColorPicker.
@_exported import TUIFoundation
