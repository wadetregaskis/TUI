//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitApp re-exports the modules it is built on, as each module of the split
// re-exports its direct dependencies (Documentation/Historical/Module split
// plan, revision 4, §4), so `import TUIkitApp` will be a whole app's import
// once per-module products ship: TUIkitFoundation, and TUIkitChrome since step
// B5b, so `.toolbar`, `.help` and `.statusBarItems` come with it. Beside what
// it gives an importer, it keeps their names, and through TUIkitFoundation's
// own re-exports the lower and side modules' (`FrameBuffer`, `RenderContext`,
// `TerminalClient` …), in scope in every file of this one, as they were while
// TUIkitFoundation compiled these files (until step B3). The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation.
@_exported import TUIkitChrome
@_exported import TUIkitFoundation
