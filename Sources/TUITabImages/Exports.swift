//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUITabImages re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUITabImages` gives an app
// `Tab(_:image:…)`, the tabs whose picture is an image resource named by a
// string, together with the tab views (TUITabs) and the bitmap path that
// finds the name (TUIBitmaps). It is a module of its own, and not part of
// either, so that neither pays for the other (decisions C11, the owner's
// TAB-IMAGE-NAME option 2, 2026-10-24): in TUIBitmaps it made an app on
// TUIApp and TUIBitmaps with no tab view 10.9% larger, and in TUITabs
// it would put the image decoders under TUIColorPicker, whose panel is a
// `TabView`. The umbrella, Sources/TUI, re-exports this module beside the
// two.
@_exported import TUIBitmaps
@_exported import TUITabs
