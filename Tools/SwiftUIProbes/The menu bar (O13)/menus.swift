// Probe: what SwiftUI puts in the main menu for a few .commands shapes.
// Usage: ./menus <case>   (cases: base, two, removed, removedInner, replaced, order, keys,
//        toolbarId, toolbarIdStd)
import SwiftUI
import AppKit

let probeCase = CommandLine.arguments.dropFirst().first ?? "base"

func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        if item.isSeparatorItem { print(indent + "----"); continue }
        var line = indent + item.title
        if !item.keyEquivalent.isEmpty {
            var mods = ""
            let m = item.keyEquivalentModifierMask
            if m.contains(.control) { mods += "⌃" }
            if m.contains(.option) { mods += "⌥" }
            if m.contains(.shift) { mods += "⇧" }
            if m.contains(.command) { mods += "⌘" }
            line += "  [\(mods)\(item.keyEquivalent)]"
        }
        if !item.isEnabled { line += " (disabled)" }
        if item.isHidden { line += " (hidden)" }
        print(line)
        if let sub = item.submenu, indent.count < 8 { dump(sub, indent: indent + "    ") }
    }
}

final class Log: @unchecked Sendable { static var fired: [String] = [] }
final class Keep: @unchecked Sendable { static var window: NSWindow? }

struct ContentView: View {
    var body: some View {
        VStack {
            Text("probe")
            if probeCase == "keys" || probeCase == "keysPageOnly" {
                Button("Page K") { Log.fired.append("page") }.keyboardShortcut("k")
            }
        }.frame(width: 200, height: 100)
    }
}

/// A page with a customizable toolbar (`toolbar(id:)`), for `toolbarId` and
/// `toolbarIdStd`: whether the View menu offers Customize Toolbar… without
/// `ToolbarCommands`.
struct CustomizableContentView: View {
    var body: some View {
        ContentView().toolbar(id: "probe") {
            ToolbarItem(id: "one") { Button("One") {} }
            ToolbarItem(id: "two") { Button("Two") {} }
        }
    }
}

struct MenusA: Commands { var body: some Commands { CommandMenu("Alpha") { Button("A1") {} } } }
struct MenusB: Commands { var body: some Commands { CommandMenu("Beta") { Button("B1") {} } } }

@main
struct ProbeApp: App {
    var body: some Scene {
        #if CASE_two
        WindowGroup { ContentView() }.commands { MenusA() }.commands { MenusB() }
        #elseif CASE_removed
        WindowGroup { ContentView() }.commands { MenusA() }.commandsRemoved()
        #elseif CASE_removedInner
        WindowGroup { ContentView() }.commandsRemoved().commands { MenusA() }
        #elseif CASE_replaced
        WindowGroup { ContentView() }.commands { MenusA() }.commandsReplaced { MenusB() }
        #elseif CASE_order
        WindowGroup { ContentView() }.commands {
            CommandMenu("Zeta") { Button("Z1") {} }
            Group {
            CommandGroup(after: .newItem) { Button("AfterNew") {} }
            CommandGroup(before: .undoRedo) { Button("BeforeUndo") {} }
            CommandGroup(replacing: .pasteboard) { Button("MyPaste") {} }
            CommandGroup(after: .help) { Button("AfterHelp") {} }
            CommandGroup(replacing: .appInfo) { Button("MyAbout") {} }
            CommandGroup(after: .sidebar) { Button("AfterSidebar") {} }
            CommandGroup(after: .textFormatting) { Button("AfterFormatting") {} }
            CommandGroup(after: .windowList) { Button("AfterWindowList") {} }
            CommandGroup(after: .importExport) { Button("AfterImportExport") {} }
            }
            CommandMenu("Alpha2") { Button("A2") {} }
        }
        #elseif CASE_replaceTwice
        WindowGroup { ContentView() }.commands {
            CommandGroup(replacing: .newItem) { Button("R1") {} }
            CommandGroup(replacing: .newItem) { Button("R2") {} }
            CommandGroup(after: .newItem) { Button("After1") {} }
            CommandGroup(after: .newItem) { Button("After2") {} }
            CommandGroup(before: .newItem) { Button("Before1") {} }
            CommandGroup(before: .newItem) { Button("Before2") {} }
        }
        #elseif CASE_std
        WindowGroup { ContentView() }.commands {
            SidebarCommands(); ToolbarCommands(); TextEditingCommands(); TextFormattingCommands(); InspectorCommands()
        }
        #elseif CASE_toolbarId
        WindowGroup { CustomizableContentView() }
        #elseif CASE_toolbarIdStd
        WindowGroup { CustomizableContentView() }.commands { ToolbarCommands() }
        #elseif CASE_keys
        WindowGroup { ContentView() }.commands {
            CommandMenu("Keys") { Button("Command K") { Log.fired.append("command") }.keyboardShortcut("k") }
        }
        #elseif CASE_keysPageOnly
        WindowGroup { ContentView() }
        #elseif CASE_emptymenu
        WindowGroup { ContentView() }.commands {
            CommandMenu("Empty") { }
            CommandMenu("Alpha") { Button("A1") {} }
            CommandMenu("Alpha") { Button("A1bis") {} }
        }
        #elseif CASE_sections
        WindowGroup { ContentView() }.commands {
            CommandMenu("Secs") {
                Button("One") {}
                Section("Head") { Button("Two") {} }
                Divider()
                Button("Three") {}.disabled(true)
                Toggle("Flag", isOn: .constant(true))
                Picker("Pick", selection: .constant(1)) { Text("P1").tag(1); Text("P2").tag(2) }
                Menu("Sub") { Button("S1") {} }
            }
        }
        #else
        WindowGroup { ContentView() }
        #endif
    }
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if probeCase.hasPrefix("toolbarId") {
            // The window group's own window is not made where the probe runs
            // (no session to activate in), so host the page in a window of
            // the probe's own, bridging its toolbar to the window's.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let host = NSHostingController(rootView: CustomizableContentView())
                host.sceneBridgingOptions = [.toolbars, .title]
                let made = NSWindow(contentViewController: host)
                made.makeKeyAndOrderFront(nil)
                Keep.window = made
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            print("== case \(probeCase)")
            if let main = NSApp.mainMenu {
                // Let AppKit update the menus as it does before showing one,
                // in case it adds the toolbar's items only then.
                for item in main.items { item.submenu?.update() }
                dump(main)
            }
            print("windows:", NSApp.windows.map { "\($0.className) visible=\($0.isVisible) toolbar=\($0.toolbar != nil)" })
            for window in NSApp.windows where window.toolbar != nil {
                let toolbar = window.toolbar!
                print("toolbar:", toolbar.identifier, "customizable:", toolbar.allowsUserCustomization,
                      "items:", toolbar.items.map(\.itemIdentifier.rawValue))
            }
            if probeCase == "keys" || probeCase == "keysPageOnly" {
                print("windows:", NSApp.windows.map { "\($0.className) visible=\($0.isVisible) canKey=\($0.canBecomeKey)" })
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                let made = NSWindow(contentViewController: NSHostingController(rootView: ContentView()))
                made.makeKeyAndOrderFront(nil)
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
                if #available(macOS 14.0, *) { NSApp.activate() }
                made.makeKey()
                Keep.window = made
                let window: NSWindow? = made
                print("key window:", window?.isKeyWindow as Any, "keyWindow:", NSApp.keyWindow as Any)
                let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                    windowNumber: window?.windowNumber ?? 0, context: nil, characters: "k",
                    charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("later key window:", NSApp.keyWindow as Any)
                let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                    windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil, characters: "k",
                    charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
                NSApp.sendEvent(ev)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    print("fired:", Log.fired)
                    exit(0)
                }
            } else {
                exit(0)
            }
        }
    }
}

