//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitColorPicker re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIkitColorPicker` gives
// an app `ColorPicker` and `ColorPickerPanel` with the views they are made of.
// Beside what it gives an importer, it keeps TUIkitFoundation's names, and
// through its own re-exports the lower and side modules', in scope in every
// file of this one, as they were while TUIkitFoundation compiled these files
// (until step B4). TUIkitPresentation is the second since step C1 peeled it out
// of TUIkitNavigation, which was the second from step B5: the panel is a
// `Dialog` and the picker presents it through `.modal`, both
// TUIkitPresentation's; nothing of the navigation containers'.
// TUIkitTabs is the third since step C3 peeled it out of TUIkitLists, which
// was the third from step B6: the panel lays its modes out in a `TabView` of
// `Tab`s; nothing of the lists'. TUIkitTextInput is the fourth since step B7
// carved it: the panel's hex field is a `TextField`. TUIkitNumericControls is
// the fifth since step C7 peeled it out of TUIkitTextInput, which gave the
// picker it from step B7: the channel rows are `Slider`s, and the gradient
// editor's strips take their colours from the tracks' `TrackRenderer`. The
// tone-curve and channel-curve editor panels, which host this module's panel
// body, left at C9b, with the gradient editor, for TUIkitColorEditors (now
// TUIkitCurveEditors: the gradient editor came back on 2026-10-12, needing
// nothing this module did not have), and with them TUIkitImage (the curve
// editors' `ASCIIToneCurve`) and TUIkitPickers (the channel-curve editor's
// `RadioButtonGroup`), which nothing here uses since.
// The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation, and so does TUIkitCurveEditors.
@_exported import TUIkitFoundation
@_exported import TUIkitNumericControls
@_exported import TUIkitPresentation
@_exported import TUIkitTabs
@_exported import TUIkitTextInput
