// Probe: where SwiftUI (macOS 15.8) puts the separators of an .inline Picker in a
// menu at the top, at the bottom, beside an app's Divider, beside a Section, and
// beside another inline picker — read back from the main menu's NSMenu items of
// a CommandMenu (inline.out). The items, not what is drawn: shown.swift measures
// which separators AppKit draws.
//   xcrun swiftc -parse-as-library -O inline.swift -o "$TMPDIR/inline" && "$TMPDIR/inline"
import SwiftUI
import AppKit

func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        if item.isSeparatorItem { print(indent + "----" + (item.isHidden ? " (hidden)" : "")); continue }
        var line = indent + "\"" + item.title + "\""
        if item.state == .on { line += " (on)" }
        if !item.isEnabled { line += " (disabled)" }
        if item.isHidden { line += " (hidden)" }
        if #available(macOS 14.0, *), item.isSectionHeader { line += " (sectionHeader)" }
        if item.submenu != nil { line += " ▸" }
        print(line)
        if let sub = item.submenu, indent.count < 12 { dump(sub, indent: indent + "    ") }
    }
}

struct InlineMenus: Commands {
    var body: some Commands {
        CommandMenu("Top") {
            Picker("Sort", selection: .constant(1)) { Text("T1").tag(1); Text("T2").tag(2) }.pickerStyle(.inline)
            Button("Close") {}
        }
        CommandMenu("Bottom") {
            Button("Open") {}
            Picker("Sort", selection: .constant(1)) { Text("B1").tag(1); Text("B2").tag(2) }.pickerStyle(.inline)
        }
        CommandMenu("Only") {
            Picker("Sort", selection: .constant(1)) { Text("O1").tag(1); Text("O2").tag(2) }.pickerStyle(.inline)
        }
        CommandMenu("Divider") {
            Button("Open") {}
            Divider()
            Picker("Sort", selection: .constant(1)) { Text("D1").tag(1); Text("D2").tag(2) }.pickerStyle(.inline)
            Divider()
            Button("Close") {}
        }
        CommandMenu("Section") {
            Section("Head") { Button("S0") {} }
            Picker("Sort", selection: .constant(1)) { Text("S1").tag(1); Text("S2").tag(2) }.pickerStyle(.inline)
            Section { Button("S3") {} }
        }
        CommandMenu("Two") {
            Picker("A", selection: .constant(1)) { Text("A1").tag(1) }.pickerStyle(.inline)
            Picker("B", selection: .constant(1)) { Text("B1").tag(1) }.pickerStyle(.inline)
        }
        CommandMenu("Radio") {
            Picker("R", selection: .constant(1)) { Text("R1").tag(1) }.pickerStyle(.radioGroup)
            Button("After") {}
        }
        CommandMenu("Unlabelled") {
            Button("Open") {}
            Picker("", selection: .constant(1)) { Text("U1").tag(1) }.pickerStyle(.inline)
            Button("Close") {}
        }
    }
}

@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup { Text("probe").frame(width: 200, height: 100) }.commands { InlineMenus() }
    }
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if let main = NSApp.mainMenu {
                for item in main.items
                where ["Top", "Bottom", "Only", "Divider", "Section", "Two", "Radio", "Unlabelled"].contains(item.title) {
                    print("MENU \(item.title)")
                    if let sub = item.submenu { dump(sub, indent: "    ") }
                }
            }
            exit(0)
        }
    }
}
