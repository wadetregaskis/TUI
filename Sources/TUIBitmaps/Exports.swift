//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIBitmaps re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIBitmaps` gives an app
// `Image(_:)` from a file or URL, `Image(_:bundle:)`, `AsyncImage` and the
// `.image*` options, and TUIImage's
// `ASCIIToneCurve`, `ASCIICharacterSet` and the rest those options take.
// Beside what it gives an importer, it keeps TUIFoundation's names, and
// through its own re-exports the lower and side modules', in scope in every
// file of this module, as they were while TUIFoundation compiled these
// files (until step B5c); each file imports TUIFoundation itself as well,
// and TUIImage where it uses it (CONTRIBUTING.md, "Crossing a module
// boundary"). TUIFoundation does not depend on TUIImage since this
// step, so this module is where it comes from. The umbrella, Sources/TUI,
// re-exports this module beside TUIFoundation.
@_exported import TUIFoundation
@_exported import TUIImage
