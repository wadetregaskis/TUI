//  🖥️ TUI — A Terminal UI framework for Swift
//  ConfigurationFolderTests.swift
//
//  Where an app's settings and the person's settings for all programs are
//  kept on each system, and that `TUI_CONFIG_DIR` moves both off the home
//  folder (the owner's USET-PLACE, 2026-11-10). Every system's rule is asked
//  on this machine, with a made-up home: nothing here touches a real one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings

@Suite("Configuration folders")
struct ConfigurationFolderTests {
    private let home = URL(fileURLWithPath: "/home/someone", isDirectory: true)

    private func file(_ system: ConfigurationFolder.System, _ environment: [String: String] = [:]) -> String {
        AllProgramsSettingsLocation.file(on: system, environment: environment, home: home).path
    }

    @Test("The settings for all programs are in TUI's folder on each system")
    func eachSystem() {
        #expect(file(.macOS) == "/home/someone/Library/Application Support/TUI/defaults.json")
        #expect(file(.other) == "/home/someone/.config/tui/defaults.json")
        #expect(file(.other, ["XDG_CONFIG_HOME": "/xdg"]) == "/xdg/tui/defaults.json")
        #expect(file(.windows, ["APPDATA": "/appdata"]) == "/appdata/TUI/defaults.json")
        #expect(file(.windows) == "/home/someone/AppData/Roaming/TUI/defaults.json")
    }

    @Test("TUI_CONFIG_DIR moves the settings for all programs and an app's own alike, on every system")
    func configDirectoryMovesBoth() {
        let environment = ["TUI_CONFIG_DIR": "/tmp/try", "XDG_CONFIG_HOME": "/xdg", "APPDATA": "/appdata"]
        for system: ConfigurationFolder.System in [.macOS, .windows, .other] {
            let all = file(system, environment)
            #expect(all.hasPrefix("/tmp/try/"), "\(system): \(all)")
            #expect(!all.hasPrefix(home.path), "\(system): \(all)")
            let app = ConfigurationFolder.folder(named: "myapp", for: system, environment: environment, home: home)
            #expect(app.path == "/tmp/try/myapp", "\(system): \(app.path)")
        }
        #expect(file(.macOS, environment) == "/tmp/try/TUI/defaults.json")
    }

    @Test("An empty TUI_CONFIG_DIR is no setting")
    func emptyConfigDirectory() {
        #expect(file(.other, ["TUI_CONFIG_DIR": ""]) == "/home/someone/.config/tui/defaults.json")
    }

    @Test("An app's own folder is beside TUI's, in Foundation's Application Support on macOS")
    func appFolder() {
        let support = URL(fileURLWithPath: "/sandbox/Application Support", isDirectory: true)
        let mac = ConfigurationFolder.folder(
            named: "myapp", for: .macOS, environment: [:], home: home, applicationSupport: support)
        #expect(mac.path == "/sandbox/Application Support/myapp")
        let linux = ConfigurationFolder.folder(named: "myapp", for: .other, environment: [:], home: home)
        #expect(linux.path == "/home/someone/.config/myapp")
    }
}
