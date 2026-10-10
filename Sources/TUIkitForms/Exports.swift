//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitForms re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitForms` will give an app forms
// and the view groupings (`Form`, `LabeledContent`, `GroupBox`, `Card` and
// `Panel`, with their styles) once per-module products ship. Beside what it
// gives an importer, it keeps TUIkitFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIkitFoundation (until step B7) and then
// TUIkitTextInput (until step C6) compiled these files; each file imports
// TUIkitFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation, and nothing else does.
@_exported import TUIkitFoundation
