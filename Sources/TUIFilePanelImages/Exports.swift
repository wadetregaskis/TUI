//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIFilePanelImages re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIFilePanelImages` gives an
// app `fileDialogPicturePreviews()` together with the file panels
// (TUIFilePanels) and the image decoders (TUIBitmaps). It is a module of its
// own, and not part of either, so that neither pays for the other (the
// owner's PREVIEW-IMAGES option "glue", 2026-10-28, as TUITabImages is for
// `Tab`'s images, decisions C11): an app with file panels and no pictures
// carries no decoders, and one showing pictures carries no file panels. The
// umbrella, Sources/TUI, re-exports this module beside the two.
@_exported import TUIBitmaps
@_exported import TUIFilePanels
