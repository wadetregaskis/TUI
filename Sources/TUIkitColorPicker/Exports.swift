//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitColorPicker re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIkitColorPicker` gives
// an app `ColorPicker` with the views it is made of,
// and `ASCIIToneCurve`, which the curve editors' initializers take.
// Beside what it gives an importer, it keeps TUIkitFoundation's names, and
// through its own re-exports the lower and side modules', in scope in every
// file of this one, as they were while TUIkitFoundation compiled these files
// (until step B4). TUIkitPresentation is the third since step C1 peeled it out
// of TUIkitNavigation, which was the third from step B5: the panels are
// `Dialog`s and the picker presents them through `.modal`, both
// TUIkitPresentation's; nothing of the navigation containers'.
// TUIkitTabs is the fourth since step C3 peeled it out of TUIkitLists, which
// was the fourth from step B6: the panel lays its modes out in a `TabView` of
// `Tab`s; nothing of the lists'. TUIkitTextInput is the fifth since step B7
// carved it: the panel's hex field is a `TextField`. TUIkitPickers is the
// sixth since step C8 and TUIkitNumericControls the seventh since step C7
// peeled them out of TUIkitTextInput, which gave the picker both from step
// B7: the channel-curve editor picks its channel with a `RadioButtonGroup`,
// the editors are made of `Slider`s, and the gradient editor colours its
// strips with the tracks' `TrackRenderer.gradientColor`.
// The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitNumericControls
@_exported import TUIkitPickers
@_exported import TUIkitPresentation
@_exported import TUIkitTabs
@_exported import TUIkitTextInput
