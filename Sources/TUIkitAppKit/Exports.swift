//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  TUIkitAppKit: the bridges between TUIkit and Apple's own graphics types —
//  `Color(nsColor:)`, `NSColor(_:)`, `Color(cgColor:)`, `Color.Resolved.cgColor`,
//  `Image(_:scale:orientation:label:)`, `Image(decorative:scale:orientation:)`
//  and `Image(nsImage:)` — and the named colours and images of a compiled
//  asset catalogue (`Color(_:bundle:)` and `Image(_:bundle:)` reading
//  `Assets.car`, after TUIkit's own reading of an uncompiled one). Import it
//  beside TUIkit where you use them:
//
//      import TUIkit
//      import TUIkitAppKit
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
//  `.timer(countingDownIn:)` and the rest sat beside TUIkit's own in every app
//  that imported TUIkit, ambiguous or, picked, failing to link.
//
//  So nothing TUIkit is built from imports AppKit, and these bridges live here.
//  An app that imports only TUIkit sees nothing of SwiftUICore. An app that
//  imports this module (or AppKit itself) loads it again, and for it TUIkit's
//  doubled statics (`SystemFormatStyle+DiscreteStatics.swift`) keep a `Text`'s
//  format resolving to TUIkit's.
//
//  Empty off Apple platforms, where there is no AppKit and no Core Graphics to
//  bridge to.
//
//  Created by Wade Tregaskis
//  License: MIT
