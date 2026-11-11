//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemNotifierTests.swift
//
//  A toast posted to the desktop through this machine itself: `osascript` or
//  `notify-send`, with the message as an argument of its own, and only where
//  the person is here. Every test injects the launch: none posts a real
//  notification.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

@testable import TUIApp

/// What a notifier under test launched.
private final class Launches: Sendable {
    let value = Mutex<[(executable: String, arguments: [String])]>([])
    var all: [(executable: String, arguments: [String])] { value.withLock { $0 } }
}

@Suite("System notifications")
struct SystemNotifierTests {
    /// A notifier that runs its work at once and records what it launches.
    private func notifier(
        _ setting: SystemNotifier.Setting, helper: SystemNotifier.Helper? = .osascript("/usr/bin/osascript"),
        isLocal: Bool, launches: Launches
    ) -> SystemNotifier {
        SystemNotifier(
            setting: setting, helper: helper, title: "Demo", isLocal: { isLocal },
            launch: { executable, arguments in launches.value.withLock { $0.append((executable, arguments)) } },
            perform: { $0() })
    }

    @Test("osascript gets the message as an argument after --, never inside the script")
    func osascriptArguments() throws {
        let message = "Say \"hi\" & \\ end tell -x"
        let arguments = SystemNotifier.Helper.osascript("/usr/bin/osascript").arguments(title: "Demo", message: message)
        let separator = try #require(arguments.firstIndex(of: "--"))
        #expect(Array(arguments[(separator + 1)...]) == ["Demo", message])
        // The script, the -e arguments, names argv and holds neither string.
        let script = arguments[..<separator].enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        #expect(script.joined(separator: "\n").contains("argv"))
        #expect(!script.contains { $0.contains("hi") || $0.contains("Demo") })
    }

    @Test("notify-send gets the title and the body after --, the body's markup escaped")
    func notifySendArguments() {
        let arguments = SystemNotifier.Helper.notifySend("/usr/bin/notify-send")
            .arguments(title: "Demo", message: "-a <b>bold</b> & more")
        #expect(arguments == ["--app-name=Demo", "--", "Demo", "-a &lt;b&gt;bold&lt;/b&gt; &amp; more"])
    }

    @Test(
        "TUI_SYSTEM_NOTIFICATIONS: 0 is off, 1 is always, anything else asks whether the person is here",
        arguments: [
            ([String: String](), SystemNotifier.Setting.whenLocal), (["TUI_SYSTEM_NOTIFICATIONS": "0"], .off),
            (["TUI_SYSTEM_NOTIFICATIONS": "1"], .always), (["TUI_SYSTEM_NOTIFICATIONS": "yes"], .whenLocal),
        ])
    func setting(environment: [String: String], expected: SystemNotifier.Setting) {
        #expect(SystemNotifier.Setting(environment: environment) == expected)
    }

    // The owner's ruling NOTIF (2026-11-10): `TUI_NOTIFICATIONS=0` means none at all, so the
    // system route is off whatever `TUI_SYSTEM_NOTIFICATIONS` says; any other value of the first
    // leaves the second to pick the route.
    @Test(
        "TUI_NOTIFICATIONS=0 turns this machine's notifications off too, whatever TUI_SYSTEM_NOTIFICATIONS says",
        arguments: [
            (["TUI_NOTIFICATIONS": "0"], SystemNotifier.Setting.off),
            (["TUI_NOTIFICATIONS": "0", "TUI_SYSTEM_NOTIFICATIONS": "1"], .off),
            (["TUI_NOTIFICATIONS": "1"], .whenLocal),
            (["TUI_NOTIFICATIONS": "1", "TUI_SYSTEM_NOTIFICATIONS": "1"], .always),
            (["TUI_NOTIFICATIONS": "1", "TUI_SYSTEM_NOTIFICATIONS": "0"], .off),
        ])
    func notificationsOffMeansNone(environment: [String: String], expected: SystemNotifier.Setting) {
        #expect(SystemNotifier.Setting(environment: environment) == expected)
    }

    @Test("The helper is what is installed: osascript, else notify-send where there is a bus and a display")
    func findsTheHelper() {
        let desktop = ["DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus", "DISPLAY": ":0", "PATH": "/bin:/usr/bin"]
        let linux: (String) -> Bool = { $0 == "/usr/bin/notify-send" }
        #expect(
            SystemNotifier.Helper.find(environment: [:], isExecutable: { $0 == "/usr/bin/osascript" }, exists: { _ in false })
                == .osascript("/usr/bin/osascript"))
        #expect(
            SystemNotifier.Helper.find(environment: desktop, isExecutable: linux, exists: { _ in false })
                == .notifySend("/usr/bin/notify-send"))
        // The bus's socket under XDG_RUNTIME_DIR will do, and Wayland's display.
        let wayland = ["XDG_RUNTIME_DIR": "/run/user/1000", "WAYLAND_DISPLAY": "wayland-0", "PATH": "/usr/bin"]
        #expect(
            SystemNotifier.Helper.find(environment: wayland, isExecutable: linux, exists: { $0 == "/run/user/1000/bus" })
                == .notifySend("/usr/bin/notify-send"))
        // No display (a console, an ssh session), or no bus: nothing to show it.
        var console = desktop
        console["DISPLAY"] = nil
        #expect(SystemNotifier.Helper.find(environment: console, isExecutable: linux, exists: { _ in true }) == nil)
        var busless = desktop
        busless["DBUS_SESSION_BUS_ADDRESS"] = nil
        #expect(SystemNotifier.Helper.find(environment: busless, isExecutable: linux, exists: { _ in false }) == nil)
    }

    @Test("Posted where the person is here, and not where they are not")
    func onlyWhereLocal() {
        let here = Launches()
        notifier(.whenLocal, isLocal: true, launches: here).post("Build finished")
        #expect(here.all.map(\.executable) == ["/usr/bin/osascript"])
        #expect(here.all.first?.arguments.suffix(2) == ["Demo", "Build finished"])
        let away = Launches()
        notifier(.whenLocal, isLocal: false, launches: away).post("Build finished")
        #expect(away.all.isEmpty)
    }

    @Test("0 posts nothing even here; 1 posts even where TUI cannot tell; no helper, nothing")
    func overrides() {
        let off = Launches()
        notifier(.off, isLocal: true, launches: off).post("Build finished")
        #expect(off.all.isEmpty)
        let always = Launches()
        notifier(.always, isLocal: false, launches: always).post("Build finished")
        #expect(always.all.count == 1)
        let none = Launches()
        notifier(.always, helper: nil, isLocal: true, launches: none).post("Build finished")
        #expect(none.all.isEmpty)
    }

    @Test("Script Editor's notifications, which osascript posts, are read from the settings' allow bit")
    func scriptEditorPermission() {
        let id = SystemNotifier.scriptEditorBundleID
        // As the settings held them on the owner's Mac, 2026-11-10: Script
        // Editor's off, Ghostty's allowed.
        let off: [String: Any] = ["bundle-id": "com.apple.ScriptEditor2", "flags": 0x200E]
        let on: [String: Any] = ["bundle-id": "com.apple.scripteditor2", "flags": 0x1280_200E]
        let other: [String: Any] = ["bundle-id": "com.mitchellh.ghostty", "flags": 0x1280_200E]
        let flagless: [String: Any] = ["bundle-id": "com.apple.ScriptEditor2"]
        #expect(SystemNotifier.permission(of: id, in: [other, off]) == .denied)
        #expect(SystemNotifier.permission(of: id, in: [on]) == .allowed)
        #expect(SystemNotifier.permission(of: id, in: [other]) == .unknown)
        #expect(SystemNotifier.permission(of: id, in: [flagless]) == .unknown)
        #expect(SystemNotifier.permission(of: id, in: nil) == .unknown)
    }

    @Test(
        "Through osascript, with Script Editor's notifications off, it says so and posts all the same",
        arguments: [SystemNotifier.Permission.denied, .allowed, .unknown])
    func saysWhenScriptEditorIsOff(permission: SystemNotifier.Permission) {
        let launches = Launches()
        let warnings = Mutex<[String]>([])
        let notifier = SystemNotifier(
            setting: .always, helper: .osascript("/usr/bin/osascript"), title: "Demo", isLocal: { true },
            launch: { executable, arguments in launches.value.withLock { $0.append((executable, arguments)) } },
            perform: { $0() }, scriptEditorPermission: { permission },
            warn: { message in warnings.withLock { $0.append(message) } })
        notifier.post("Build finished")
        #expect(launches.all.count == 1)
        let said = warnings.withLock { $0 }
        if permission == .denied {
            #expect(said == [SystemNotifier.scriptEditorDeniedMessage])
            #expect(said.first?.contains("System Settings ▸ Notifications ▸ Script Editor") == true)
        } else {
            #expect(said.isEmpty)
        }
    }

    @Test("notify-send never asks about Script Editor")
    func notifySendNeverAsks() {
        let asked = Mutex(false)
        let notifier = SystemNotifier(
            setting: .always, helper: .notifySend("/usr/bin/notify-send"), title: "Demo", isLocal: { true },
            launch: { _, _ in }, perform: { $0() },
            scriptEditorPermission: {
                asked.withLock { $0 = true }
                return .denied
            })
        notifier.post("Build finished")
        #expect(!asked.withLock { $0 })
    }

    @Test("Control characters are dropped, a line break is a space, and a blank message posts nothing")
    func sanitised() {
        let launches = Launches()
        let notifier = notifier(.always, isLocal: true, launches: launches)
        notifier.post("Two\nlines\u{1B}[31m\u{07}")
        notifier.post(" \n\t ")
        #expect(launches.all.count == 1)
        #expect(launches.all.first?.arguments.last == "Two lines[31m")
    }
}
