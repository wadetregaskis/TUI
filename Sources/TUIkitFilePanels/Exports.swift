//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitFilePanels re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIkitFilePanels` gives an
// app the file panels (`fileImporter`, `fileExporter`, `fileMover` and the
// `fileDialog` customizations) with the views a panel is made of: the sheet
// and alert it is presented in (TUIkitPresentation), the table it lists a
// folder in (TUIkitTables, which brings `List` with it), the fields it names
// a file and types a path in (TUIkitTextInput), the segmented picker its path
// control is (TUIkitPickers), and TUIkitFoundation. Beside
// what it gives an importer, it keeps their names, and through their own
// re-exports the chrome's and the lower and side modules', in scope in every
// file of this module; each file imports TUIkitFoundation itself as well, and
// the others where it uses them (CONTRIBUTING.md, "Crossing a module
// boundary").
//
// It does NOT re-export UniformTypeIdentifiers, as SwiftUI does not: an
// `allowedContentTypes: [.pdf]` names its types through the parameter's type,
// and code that names `UTType` itself imports UniformTypeIdentifiers, as it
// does beside SwiftUI. Where that module does not exist (Linux), this module
// declares a `UTType` of its own (ContentTypes/UTType.swift).
//
// The umbrella, Sources/TUIkit, re-exports this module beside TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitPickers
@_exported import TUIkitPresentation
@_exported import TUIkitTables
@_exported import TUIkitTextInput
