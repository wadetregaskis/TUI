//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitPickers re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitPickers` will give an app the
// pickers (`Picker` with its styles, `RadioButtonGroup` and `DatePicker` with
// its styles) once per-module products ship. Beside what
// it gives an importer, it keeps TUIkitFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIkitTextInput compiled these files (until step
// C8); each file imports TUIkitFoundation itself as well (CONTRIBUTING.md,
// "Crossing a module boundary"). The umbrella, Sources/TUIkit, re-exports this
// module beside TUIkitFoundation, and so do TUIkitColorPicker and
// TUIkitSearch.
@_exported import TUIkitFoundation
