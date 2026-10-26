//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarAboutTests.swift
//
//  The app menu's About: the name, version, credits and copyright the scene
//  states (`Scene.aboutPanel`), its Info.plist has, or the process's name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICommands
@testable import TUIFoundation
import TUIPresentation

// MARK: - Fixtures

/// An app that states everything About shows.
private struct StatedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("PAGE") {} }
            .commands { CommandMenu("Note") {} }
            .aboutPanel(
                applicationName: "Notes", applicationVersion: "1.2", version: "42", copyright: "© 2026 Somebody",
                credits: "Made by hand")
    }
}

// MARK: - Where the Values Come From

@Suite("What About says")
struct AboutPanelResolutionTests {
    private let plist: [String: Any] = [
        "CFBundleDisplayName": "Shown", "CFBundleName": "Bundled", "CFBundleShortVersionString": "3.0",
        "CFBundleVersion": "300", "NSHumanReadableCopyright": "© Plist",
    ]

    @Test("With nothing stated, the Info.plist's values, the display name before the bundle name")
    func fromThePlist() {
        let about = AboutPanelInfo().resolved(bundle: plist, processName: "proc")
        #expect(about.name == "Shown")
        #expect(about.versionText == "3.0 (300)")
        #expect(about.copyright == "© Plist")
        #expect(AboutPanelInfo().resolved(bundle: ["CFBundleName": "Bundled"], processName: "proc").name == "Bundled")
    }

    @Test("With no Info.plist, the process's name and nothing else")
    func fromTheProcess() {
        let about = AboutPanelInfo().resolved(bundle: nil, processName: "proc")
        #expect(about == ResolvedAboutPanel(name: "proc", applicationVersion: nil, version: nil, copyright: nil, credits: nil))
        #expect(about.aboutMessage == "proc")
    }

    @Test("What the scene states wins over the Info.plist, value by value")
    func statedWins() {
        let about = AboutPanelInfo(applicationName: "Notes", copyright: "© Me").resolved(bundle: plist, processName: "p")
        #expect(about.name == "Notes")
        #expect(about.copyright == "© Me")
        #expect(about.versionText == "3.0 (300)", "the version the scene left unstated is the plist's")
    }

    @Test("The build shows beside the version only where they differ, and alone where there is no version")
    func versionWording() {
        func text(_ short: String?, _ build: String?) -> String? {
            AboutPanelInfo(applicationVersion: short, version: build).resolved(bundle: nil, processName: "p").versionText
        }
        #expect(text("1.2", "42") == "1.2 (42)")
        #expect(text("1.2", "1.2") == "1.2")
        #expect(text("1.2", nil) == "1.2")
        #expect(text(nil, "42") == "(42)")
        #expect(text(nil, nil) == nil)
    }

    @Test("The message: name, version, credits and copyright, a line each")
    func message() {
        let about = AboutPanelInfo(
            applicationName: "Notes", applicationVersion: "1.2", copyright: "© Me", credits: "Thanks"
        ).resolved(bundle: nil, processName: "p")
        #expect(about.aboutMessage == "Notes\nVersion 1.2\nThanks\n© Me")
    }
}

// MARK: - In the Bar

@MainActor
@Suite("About, stated by the scene", .serialized)
struct MenuBarAboutTests {
    @Test("The stated name titles the app's menu, and About shows the name, version, credits and copyright")
    func statedAbout() {
        let app = HeadlessApp(StatedApp(), width: 60, height: 16)
        var now: Int64 = 0
        func frame() {
            now += 20_000_000
            app.frame(atNanos: now)
        }
        frame()
        let rows = { app.screen.map(\.stripped) }
        #expect(rows()[0].hasPrefix(" Notes  Edit  Note"), "\(rows()[0])")
        app.send(KeyEvent(key: .f10))
        frame()
        #expect(rows().contains { $0.contains("About Notes") }, "\(rows())")
        #expect(rows().contains { $0.contains("Quit Notes") }, "\(rows())")
        app.send(KeyEvent(key: .enter))
        frame()
        frame()
        for line in ["Version 1.2 (42)", "Made by hand", "© 2026 Somebody"] {
            #expect(rows().contains { $0.contains(line) }, "\(line): \(rows())")
        }
    }
}
