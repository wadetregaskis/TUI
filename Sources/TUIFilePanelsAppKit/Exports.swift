//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  TUIFilePanelsAppKit: `fileDialogSystemIcons()`, which draws the file
//  panels' items with `NSWorkspace`'s icons, the Finder's (decisions A-FP2-1,
//  the owner's option 2). Import it beside TUI where you use it:
//
//      import TUI
//      import TUIFilePanelsAppKit
//
//  It re-exports nothing, as TUIAppKit does, and the umbrella does not
//  re-export it.
//
//  ## Why it is a module of its own
//
//  It needs AppKit (`NSWorkspace`), so it cannot be in the file panels, which
//  nothing may make import AppKit (TUIAppKit's `Exports.swift` says why).
//  And it is not in TUIAppKit either, which it was for a day: it made
//  TUIAppKit depend on TUIFilePanels, and through it on the lists, the
//  tables, the pickers and the presentation modules, so an app that took
//  TUIAppKit only for `Color(nsColor:)` linked all of them. Measured
//  (release, stripped, Swift 6.2.4): an app on TUIApp and TUIAppKit using
//  only `Color(nsColor:)` grew 8,367,200 -> 10,816,112 B, +29.3%. Here an app
//  pays for the file panels' icons only when it asks for them (the owner's
//  ruling, 2026-10-24, on the same terms as TUITabImages).
//
//  Empty off Apple platforms, where there is no AppKit to ask.
//
//  Created by Wade Tregaskis
//  License: MIT
