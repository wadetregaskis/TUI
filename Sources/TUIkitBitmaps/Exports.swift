//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitBitmaps re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitBitmaps` gives an app
// `Image(_:)` from a file or URL, `Image(_:bundle:)`, `AsyncImage` and the
// `.image*` options, and TUIkitImage's
// `ASCIIToneCurve`, `ASCIICharacterSet` and the rest those options take.
// Beside what it gives an importer, it keeps TUIkitFoundation's names, and
// through its own re-exports the lower and side modules', in scope in every
// file of this module, as they were while TUIkitFoundation compiled these
// files (until step B5c); each file imports TUIkitFoundation itself as well,
// and TUIkitImage where it uses it (CONTRIBUTING.md, "Crossing a module
// boundary"). TUIkitFoundation does not depend on TUIkitImage since this
// step, so this module is where it comes from. The umbrella, Sources/TUIkit,
// re-exports this module beside TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitImage
