//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitColorEditors re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUIkitColorEditors` gives an
// app the gradient, tone-curve and channel-curve editor panels with
// `ColorPicker` and the rest of TUIkitColorPicker, whose colour panel body,
// editor chrome and swatch style the panels are made of, and TUIkitImage's
// `ASCIIToneCurve`, which the curve editors' initializers take. TUIkitPickers
// is the channel-curve editor's (it picks its channel with a
// `RadioButtonGroup`), and TUIkitNumericControls the `Slider`s all three are
// made of and the tracks' `TrackRenderer.gradientColor`, which colours the
// gradient editor's strips. The panels compiled into TUIkitColorPicker from
// step B4 until C9b moved them here, so that an app that uses `ColorPicker`
// alone neither compiles nor links them. Beside what it gives an importer, it
// keeps those modules' names in scope in every file of this one; each file
// imports what it uses itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUIkit, re-exports this module, and
// nothing else does.
@_exported import TUIkitColorPicker
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitNumericControls
@_exported import TUIkitPickers
