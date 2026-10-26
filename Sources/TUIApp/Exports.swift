//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIApp re-exports the modules it is built on, as each module of the split
// re-exports its direct dependencies (Documentation/Historical/Module split
// plan, revision 4, §4), so `import TUIApp` is a whole app's import:
// TUIFoundation, and TUIChrome since step
// B5b, so `.toolbar`, `.help` and `.statusBarItems` come with it. Beside what
// it gives an importer, it keeps their names, and through TUIFoundation's
// own re-exports the lower and side modules' (`FrameBuffer`, `RenderContext`,
// `TerminalClient` …), in scope in every file of this one, as they were while
// TUIFoundation compiled these files (until step B3). The umbrella,
// Sources/TUI, re-exports this module beside TUIFoundation.
@_exported import TUIChrome
@_exported import TUIFoundation
