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
// (until step B4). TUIkitNavigation is the third since step B5 carved it: the
// panels are `Dialog`s and the picker presents them through `.modal`, both
// TUIkitPresentation's, which compiles into TUIkitNavigation until step C1.
// The umbrella, Sources/TUIkit, re-exports this module beside TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitNavigation
