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
    #elseif !canImport(WASILibc) && !os(Windows)  // wasip1 and Windows run no helper, so look for none
        @Test("Wayland first, then X11, and only with a display to talk to")
        func linux() {
            let all: (String) -> Bool = { _ in true }
            let both = SystemClipboard.helpers(
                environment: ["WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0", "PATH": "/usr/bin"], exists: all)
            #expect(both.map(\.copyTool) == ["/usr/bin/wl-copy", "/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(both.first?.pasteTool == "/usr/bin/wl-paste")
            let x11 = SystemClipboard.helpers(environment: ["DISPLAY": ":0", "PATH": "/usr/bin"], exists: all)
            #expect(x11.map(\.copyTool) == ["/usr/bin/xclip", "/usr/bin/xsel"])
            #expect(SystemClipboard.helpers(environment: [:], exists: all).isEmpty)
        }
    #endif

    #if !canImport(WASILibc) && !os(Windows)
        @Test("The Linux helpers are found on PATH, wherever it puts them")
        func linuxHelpersOnPath() {
            let installed: Set = [
                "/nix/profile/bin/wl-copy", "/nix/profile/bin/wl-paste", "/home/u/.local/bin/xclip", "/usr/bin/xsel",
            ]
            let environment = [
                "WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0", "PATH": "/home/u/.local/bin:/nix/profile/bin:/usr/bin",
            ]
            let helpers = SystemClipboard.linuxHelpers(environment: environment, exists: installed.contains)
            #expect(helpers.map(\.copyTool) == ["/nix/profile/bin/wl-copy", "/home/u/.local/bin/xclip", "/usr/bin/xsel"])
            #expect(helpers.first?.pasteTool == "/nix/profile/bin/wl-paste")
            let noPath = ["DISPLAY": ":0"]
            #expect(SystemClipboard.linuxHelpers(environment: noPath, exists: { _ in true }).isEmpty, "no PATH")
        }
    #endif
}
