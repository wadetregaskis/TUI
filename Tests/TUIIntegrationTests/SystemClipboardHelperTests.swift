//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemClipboardHelperTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp

@Suite("Clipboard: this machine's helpers")
struct SystemClipboardHelperTests {
    #if os(macOS)
        @Test("macOS copies with pbcopy and pastes with pbpaste")
        func macOS() {
            let helpers = SystemClipboard.helpers(environment: [:], exists: { _ in true })
            #expect(helpers.map(\.copyTool) == ["/usr/bin/pbcopy"])
            #expect(helpers.map(\.pasteTool) == ["/usr/bin/pbpaste"])
        }
    #else
        @Test("Wayland first, then X11, and only with a display to talk to")
        func linux() {
            let all: (String) -> Bool = { _ in true }
            let both = SystemClipboard.helpers(
                environment: ["WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0"], exists: all)
            #expect(both.map(\.copyTool) == ["/usr/bin/wl-copy", "/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(both.first?.pasteTool == "/usr/bin/wl-paste")
            let x11 = SystemClipboard.helpers(environment: ["DISPLAY": ":0"], exists: all)
            #expect(x11.map(\.copyTool) == ["/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(SystemClipboard.helpers(environment: [:], exists: all).isEmpty)
        }
    #endif
}
