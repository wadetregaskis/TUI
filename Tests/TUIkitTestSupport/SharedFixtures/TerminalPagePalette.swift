//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalPagePalette.swift
//
//  Cut from ReplayedRunFieldTests.swift: suites of several test targets render on the terminal's page.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import TUIkit

/// The terminal's own page: every field the palette names for the page — the
/// page itself, a tab's surface, a chip's label, the wash a dim or a backdrop
/// flattens everything to — is `Color.default`, spelled `ESC[49m`, and nothing
/// has an RGB to blend with.
@MainActor
let terminalPagePalette = ThemeProbePalette(background: .default, overlayBackground: .default)

#endif
