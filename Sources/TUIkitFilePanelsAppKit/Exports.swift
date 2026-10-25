//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  TUIkitFilePanelsAppKit: `fileDialogSystemIcons()`, which draws the file
//  panels' items with `NSWorkspace`'s icons, the Finder's (decisions A-FP2-1,
//  the owner's option 2). Import it beside TUIkit where you use it:
//
//      import TUIkit
//      import TUIkitFilePanelsAppKit
//
//  It re-exports nothing, as TUIkitAppKit does, and the umbrella does not
//  re-export it.
//
//  ## Why it is a module of its own
//
//  It needs AppKit (`NSWorkspace`), so it cannot be in the file panels, which
//  nothing may make import AppKit (TUIkitAppKit's `Exports.swift` says why).
//  And it is not in TUIkitAppKit either, which it was for a day: it made
//  TUIkitAppKit depend on TUIkitFilePanels, and through it on the lists, the
//  tables, the pickers and the presentation modules, so an app that took
//  TUIkitAppKit only for `Color(nsColor:)` linked all of them. Measured
//  (release, stripped, Swift 6.2.4): an app on TUIkitApp and TUIkitAppKit using
//  only `Color(nsColor:)` grew 8,367,200 -> 10,816,112 B, +29.3%. Here an app
//  pays for the file panels' icons only when it asks for them (the owner's
//  ruling, 2026-10-24, on the same terms as TUIkitTabImages).
//
//  Empty off Apple platforms, where there is no AppKit to ask.
//
//  Created by Wade Tregaskis
//  License: MIT
