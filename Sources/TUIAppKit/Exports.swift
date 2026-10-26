//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  TUIAppKit: the bridges between TUI and AppKit's graphics types —
//  `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)` — and the named
//  colours and images of a compiled asset catalogue (`Color(_:bundle:)` and
//  `Image(_:bundle:)` reading `Assets.car`, after TUI's own reading of an
//  uncompiled one). Import it beside TUI where you use them:
//
//      import TUI
//      import TUIAppKit
//
//  ## Why they are a module of their own (decisions B50)
//
//  They name AppKit types, so the module that declares them imports AppKit —
//  and from the macOS 15 SDK, AppKit imports SwiftUICore. A module that
//  imports AppKit at all, even with `internal import`, makes every app that
//  imports IT load SwiftUICore too (a SwiftPM package is built without library
//  evolution, so its clients load its dependencies, internal ones included —
//  measured with a two-module probe on Swift 6.2.4). And until an app opts into
//  Swift's member-import-visibility rule, every extension member of every
//  module it loads is in scope: SwiftUICore's `FormatStyle.offset(to:)`,
//  `.timer(countingDownIn:)` and the rest sat beside TUI's own in every app
//  that imported TUI, ambiguous or, picked, failing to link.
//
//  So nothing TUI is built from imports AppKit, and these bridges live here.
//  Core Graphics' — `Color(cgColor:)`, `Color.Resolved.cgColor` and the
//  `CGImage` initialisers of `Image` — are TUI's own since 2026-10-19
//  (decisions B-D3M-4): Core Graphics does not import SwiftUICore.
//  An app that imports only TUI sees nothing of SwiftUICore. An app that
//  imports this module (or AppKit itself) loads it again, and for it TUI's
//  doubled statics (`SystemFormatStyle+DiscreteStatics.swift`) keep a `Text`'s
//  format resolving to TUI's.
//
//  Empty off Apple platforms, where there is no AppKit to bridge to.
//
//  Created by Wade Tregaskis
//  License: MIT
