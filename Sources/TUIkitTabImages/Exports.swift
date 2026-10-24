//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitTabImages re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitTabImages` gives an app
// `Tab(_:image:…)`, the tabs whose picture is an image resource named by a
// string, together with the tab views (TUIkitTabs) and the bitmap path that
// finds the name (TUIkitBitmaps). It is a module of its own, and not part of
// either, so that neither pays for the other (decisions C11, the owner's
// TAB-IMAGE-NAME option 2, 2026-10-24): in TUIkitBitmaps it made an app on
// TUIkitApp and TUIkitBitmaps with no tab view 10.9% larger, and in TUIkitTabs
// it would put the image decoders under TUIkitColorPicker, whose panel is a
// `TabView`. The umbrella, Sources/TUIkit, re-exports this module beside the
// two.
@_exported import TUIkitBitmaps
@_exported import TUIkitTabs
