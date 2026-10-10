//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitSearch re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitSearch` will give an app
// search (`.searchable` with its tokens, scopes and suggestions,
// `dismissSearch`, the search field's placements and toolbar behaviour) once
// per-module products ship: TUIkitFoundation, TUIkitTextInput (a search field
// is a `TextField`) and TUIkitPickers (its scope bar is a `Picker`, which
// TUIkitTextInput gave it until step C8), so the text inputs and pickers come
// with it too. Beside what it gives an importer, it keeps their
// names, and through TUIkitFoundation's own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUIkitFoundation (until step B7) and then TUIkitTextInput (until step C5)
// compiled these files; each file imports TUIkitFoundation itself as well, and
// TUIkitTextInput and TUIkitPickers where it uses them (CONTRIBUTING.md,
// "Crossing a module boundary"). The umbrella, Sources/TUIkit, re-exports
// this module beside TUIkitFoundation, and nothing else does.
@_exported import TUIkitFoundation
@_exported import TUIkitPickers
@_exported import TUIkitTextInput
