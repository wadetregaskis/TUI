//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by LAYERED.work
//  License: MIT

// The umbrella: `import TUIkit` is the whole framework. It declares nothing of
// its own (Tools/ModuleMap's `umbrella` check holds it to imports): the views,
// modifiers and the rest are TUIkitFoundation's, which compiled every module of
// the planned split until each was carved into a target of its own
// (Documentation/Historical/Module split plan, revision 4; the last at step
// B7), and the carved modules'; the lower four are the substrate beneath it. A
// module already carved out that TUIkitFoundation is built on (TUIkitStrings,
// TUIkitTerminalHost) comes through TUIkitFoundation's own re-exports; one
// carved out that is built on TUIkitFoundation is re-exported here: TUIkitApp
// (`App`, `Scene` and the run loop, since step B3), TUIkitColorPicker
// (`ColorPicker` and its editors, since step B4), TUIkitNavigation (the
// navigation containers, since step B5, and the presentations until step C1),
// TUIkitPresentation (the presentations: alerts, dialogs, sheets and modals,
// since step C1) and TUIkitLists (lists, and tables, tabs and grids until steps
// C2 to C4 peel them; since step B6), TUIkitChrome (the window chrome),
// TUIkitEffects (transitions and visual effects) and TUIkitMenus (`Menu`,
// `.contextMenu`; all three since step B5b), and TUIkitBitmaps (`Image`'s
// bitmap path, `AsyncImage` and the `.image*` options; since step B5c, which
// also took TUIkitImage out of TUIkitFoundation's re-exports, so the line for
// it below is what gives an app `ASCIIConverter` and the rest; TUIkitBitmaps
// and TUIkitColorPicker re-export it too), and TUIkitTextInput (the text
// inputs, and the pickers, forms, search and numeric controls until steps C5 to
// C8 peel them; since step B7). Each by name, though TUIkitColorPicker
// re-exports TUIkitPresentation (TUIkitNavigation from B5 until C1),
// TUIkitLists for good (directly until C3, then through TUIkitTabs, which
// depends on it) and TUIkitTextInput for good (directly until the peels, then
// through the modules they make, TUIkitTextInput's own among them), and
// TUIkitApp and TUIkitPresentation re-export TUIkitChrome (TUIkitNavigation did
// from B5b until C1): the `umbrella` check asks for every module built on
// TUIkitFoundation, because no build notices one this file leaves out while a
// sibling's re-export still reaches it. A qualified name in an app,
// `TUIkit.Label`, still resolves through these re-exports.
@_exported import TUIkitApp
@_exported import TUIkitBitmaps
@_exported import TUIkitChrome
@_exported import TUIkitColorPicker
@_exported import TUIkitCore
@_exported import TUIkitEffects
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitLists
@_exported import TUIkitMenus
@_exported import TUIkitNavigation
@_exported import TUIkitPresentation
@_exported import TUIkitStyling
@_exported import TUIkitTextInput
@_exported import TUIkitView
