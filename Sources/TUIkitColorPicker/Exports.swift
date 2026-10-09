//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitColorPicker re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIkitColorPicker` will give
// an app `ColorPicker` with the views it is made of once per-module products
// ship, and `ASCIIToneCurve`, which the curve editors' initializers take.
// Beside what it gives an importer, it keeps TUIkitFoundation's names, and
// through its own re-exports the lower and side modules', in scope in every
// file of this one, as they were while TUIkitFoundation compiled these files
// (until step B4). TUIkitPresentation is the third since step C1 peeled it out
// of TUIkitNavigation, which was the third from step B5: the panels are
// `Dialog`s and the picker presents them through `.modal`, both
// TUIkitPresentation's; nothing of the navigation containers'.
// TUIkitLists is the fourth since step B6 carved it: the panel lays its modes
// out in a `TabView` of `Tab`s, TUIkitTabs', which compiles into TUIkitLists
// until step C3. TUIkitTextInput is the fifth since step B7 carved it: the
// editors are made of `Slider`s (TUIkitNumericControls'), the panel's hex
// field is a `TextField` and the channel-curve editor picks its channel with a
// `RadioButtonGroup` (TUIkitPickers'), all three of which compile into
// TUIkitTextInput until steps C7 and C8 peel the first and last. The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitLists
@_exported import TUIkitPresentation
@_exported import TUIkitTextInput
