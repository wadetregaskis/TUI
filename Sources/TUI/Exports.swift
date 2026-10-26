//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by LAYERED.work
//  License: MIT

// The umbrella: `import TUI` is the whole framework. It declares nothing of
// its own (Tools/ModuleMap's `umbrella` check holds it to imports): the views,
// modifiers and the rest are TUIFoundation's, which compiled every module of
// the planned split until each was carved into a target of its own
// (Documentation/Historical/Module split plan, revision 4; the last at step
// B7), and the carved modules'; the lower four are the substrate beneath it. A
// module already carved out that TUIFoundation is built on (TUIStrings,
// TUITerminalHost) comes through TUIFoundation's own re-exports; one
// carved out that is built on TUIFoundation is re-exported here: TUIApp
// (`App`, `Scene` and the run loop, since step B3), TUIColorPicker
// (`ColorPicker` and its panel, since step B4), TUICommands (the
// commands and the menu bar they draw, since lane O13), TUIFilePanels (the
// file panels, since lane O10), TUICurveEditors (the
// tone-curve and channel-curve editors, TUIColorPicker's until C9b and
// TUIColorEditors' until 2026-10-12), TUINavigation (the
// navigation containers, since step B5, and the presentations until step C1),
// TUIPresentation (the presentations: alerts, dialogs, sheets and modals,
// since step C1), TUIScenes (the `Settings` scene and `AlertScene`, since
// lane O9), TUILists (lists, since step B6), TUITables (tables,
// since step C2), TUITabs (tab views, since step C3) and TUIGrid (grids,
// since step C4), all three of which TUILists compiled until then,
// TUITabImages (`Tab`'s `image:` initialisers, built on TUIBitmaps and
// TUITabs, since the owner's TAB-IMAGE-NAME option 2),
// TUIChrome (the window chrome), TUIEffects (transitions and visual
// effects) and TUIMenus (`Menu`, `.contextMenu`; all three since step B5b),
// and TUIBitmaps (`Image`'s bitmap path, `AsyncImage` and the `.image*`
// options; since step B5c, which also took TUIImage out of
// TUIFoundation's re-exports, so the line for it below is what gives an app
// `ASCIIConverter` and the rest; TUIBitmaps and TUICurveEditors
// re-export it too), TUITextInput (the text inputs, since step B7), TUIForms
// (forms and the view groupings, since step C6), TUISearch (`.searchable`
// with its tokens and scopes, since step C5), TUIPickers (`Picker`,
// `RadioButtonGroup` and `DatePicker`, since step C8) and
// TUINumericControls (`Slider`, `Stepper`, `Gauge` and `ProgressView`,
// since step C7), all four of which TUITextInput compiled until then. Each
// by name, though TUIColorPicker re-exports
// TUIPresentation (TUINavigation from B5 until C1), TUITabs, and
// through it TUILists (directly until C3), and TUITextInput for good
// (directly until the peels, then through the modules they make,
// TUITextInput's own among them), and TUIApp and TUIPresentation
// re-export TUIChrome (TUINavigation did from B5b until C1), TUITables
// and TUITabs TUILists, TUISearch TUITextInput, TUISearch and
// TUICurveEditors TUIPickers, TUIColorPicker and TUICurveEditors
// TUINumericControls, and TUICurveEditors TUIColorPicker: the `umbrella`
// check asks for every module built on TUIFoundation, because no build
// notices one this file leaves out while a sibling's re-export still reaches
// it. A qualified name in an app, `TUI.Label`, still resolves through these
// re-exports.
@_exported import TUIApp
@_exported import TUIBitmaps
@_exported import TUIChrome
@_exported import TUIColorPicker
@_exported import TUICommands
@_exported import TUICore
@_exported import TUICurveEditors
@_exported import TUIEffects
@_exported import TUIFilePanels
@_exported import TUIForms
@_exported import TUIFoundation
@_exported import TUIGrid
@_exported import TUIImage
@_exported import TUILists
@_exported import TUIMenus
@_exported import TUINavigation
@_exported import TUINumericControls
@_exported import TUIPickers
@_exported import TUIPresentation
@_exported import TUIScenes
@_exported import TUISearch
@_exported import TUIStyling
@_exported import TUITabImages
@_exported import TUITables
@_exported import TUITabs
@_exported import TUITextInput
@_exported import TUIView
