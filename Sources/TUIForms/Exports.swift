//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIForms re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIForms` gives an app forms
// and the view groupings (`Form`, `LabeledContent`, `GroupBox`, `Card` and
// `Panel`, with their styles). Beside what it
// gives an importer, it keeps TUIFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIFoundation (until step B7) and then
// TUITextInput (until step C6) compiled these files; each file imports
// TUIFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUI, re-exports this module beside
// TUIFoundation, and nothing else does.
@_exported import TUIFoundation
