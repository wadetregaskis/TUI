//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUICurveEditors re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4), so `import TUICurveEditors` gives an
// app the tone-curve and channel-curve editor panels with `ColorPicker` and
// the rest of TUIColorPicker, whose colour panel body, editor chrome,
// swatch style and gradient-stop chips the panels are made of, and
// TUIImage's `ASCIIToneCurve`, which their initializers take. TUIPickers
// is the channel-curve editor's (it picks its channel with a
// `RadioButtonGroup`), and TUINumericControls the `Slider`s both are made
// of. The panels compiled into TUIColorPicker from step B4 until C9b moved
// them, with the gradient editor, into a module of their own,
// TUIColorEditors; the gradient editor went back to TUIColorPicker on
// 2026-10-12, and the module took the name of what it holds. So an app that
// uses `ColorPicker` alone neither compiles nor links the curve editors, nor
// TUIImage and TUIPickers. Beside what it gives an importer, it keeps
// those modules' names in scope in every file of this one; each file imports
// what it uses itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUI, re-exports this module, and
// nothing else does.
@_exported import TUIColorPicker
@_exported import TUIFoundation
@_exported import TUIImage
@_exported import TUINumericControls
@_exported import TUIPickers
