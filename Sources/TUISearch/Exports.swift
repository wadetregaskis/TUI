//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUISearch re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUISearch` gives an app
// search (`.searchable` with its tokens, scopes and suggestions,
// `dismissSearch`, the search field's placements and toolbar behaviour):
// TUIFoundation, TUITextInput (a search field
// is a `TextField`) and TUIPickers (its scope bar is a `Picker`, which
// TUITextInput gave it until step C8), so the text inputs and pickers come
// with it too. Beside what it gives an importer, it keeps their
// names, and through TUIFoundation's own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUIFoundation (until step B7) and then TUITextInput (until step C5)
// compiled these files; each file imports TUIFoundation itself as well, and
// TUITextInput and TUIPickers where it uses them (CONTRIBUTING.md,
// "Crossing a module boundary"). The umbrella, Sources/TUI, re-exports
// this module beside TUIFoundation, and nothing else does.
@_exported import TUIFoundation
@_exported import TUIPickers
@_exported import TUITextInput
