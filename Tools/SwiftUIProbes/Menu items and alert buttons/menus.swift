// Probe: what SwiftUI (macOS 15.8) builds for menus holding pickers and nested
// menus, read back from the main menu's NSMenu items; and which modifiers
// written on an alert's buttons the NSAlert it presents keeps.
//
// Built once per case (the case is a compile-time flag), and the alert case run
// once per button set:
//   xcrun swiftc -parse-as-library -O -D CASE_pickers menus.swift -o "$TMPDIR/pickers" && "$TMPDIR/pickers" pickers
//   xcrun swiftc -parse-as-library -O -D CASE_alert menus.swift -o "$TMPDIR/alert"
//   for set in a b c d e f; do echo "## set $set"; "$TMPDIR/alert" alert $set | sed -n '/_NSAlertPanel title/,$p'; done
// `-D CASE_dialog` presents a confirmationDialog instead, run for sets a b c d f
// (dialog.out).
import SwiftUI
import AppKit

let probeCase = CommandLine.arguments.dropFirst().first ?? "pickers"

func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        if item.isSeparatorItem { print(indent + "----"); continue }
        var line = indent + "\"" + item.title + "\""
        if !item.keyEquivalent.isEmpty {
            var mods = ""
            let m = item.keyEquivalentModifierMask
            if m.contains(.control) { mods += "⌃" }
            if m.contains(.option) { mods += "⌥" }
            if m.contains(.shift) { mods += "⇧" }
            if m.contains(.command) { mods += "⌘" }
            line += "  [\(mods)\(item.keyEquivalent)]"
        }
        switch item.state {
        case .on: line += " (on)"
        case .mixed: line += " (mixed)"
        default: break
        }
        if !item.isEnabled { line += " (disabled)" }
        if item.isHidden { line += " (hidden)" }
        if #available(macOS 14.0, *), item.isSectionHeader { line += " (sectionHeader)" }
        if item.indentationLevel > 0 { line += " (indent \(item.indentationLevel))" }
        if item.view != nil { line += " (customView \(type(of: item.view!)))" }
        if item.submenu != nil { line += " ▸" }
        if let tip = item.toolTip { line += " (tooltip \(tip))" }
        print(line)
        if let sub = item.submenu, indent.count < 12 { dump(sub, indent: indent + "    ") }
    }
}

func dumpButtons(_ view: NSView, indent: String = "") {
    if let button = view as? NSButton {
        var mods = ""
        let m = button.keyEquivalentModifierMask
        if m.contains(.control) { mods += "⌃" }
        if m.contains(.option) { mods += "⌥" }
        if m.contains(.shift) { mods += "⇧" }
        if m.contains(.command) { mods += "⌘" }
        let key = button.keyEquivalent.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined()
        print(
            indent + "NSButton \"\(button.title)\" enabled=\(button.isEnabled) key=[\(mods)\(key)]"
                + " tooltip=\(button.toolTip ?? "nil") bezelColor=\(String(describing: button.bezelColor))"
                + " hasDestructiveAction=\(button.hasDestructiveAction)")
    }
    for sub in view.subviews { dumpButtons(sub, indent: indent) }
}

final class Keep: @unchecked Sendable { static var window: NSWindow? }

struct AlertView: View {
    @State var shown = false
    var body: some View {
        Text("probe")
            .frame(width: 300, height: 200)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shown = true } }
            #if CASE_dialog
            .confirmationDialog("Title", isPresented: $shown) {
                buttons
            }
            #else
            .alert("Title", isPresented: $shown) {
                buttons
            } message: {
                Text("Message")
            }
            #endif
    }

    @ViewBuilder var buttons: some View {
        switch CommandLine.arguments.dropFirst(2).first ?? "a" {
        case "a":
            Button("Dis") {}.disabled(true)
            Button("Key") {}.keyboardShortcut("k")
            Button("Def") {}.keyboardShortcut(.defaultAction)
        case "b":
            Button("Help") {}.help("tip")
            Button("Tint") {}.tint(.red)
            Button("Can", role: .cancel) {}
        case "c":
            Button("Plain") {}
            Button("Def") {}.keyboardShortcut(.defaultAction)
            Button("Can", role: .cancel) {}
        case "d":
            Button("Del", role: .destructive) {}
            Button("Can2") {}.keyboardShortcut(.cancelAction)
            Button("Fg") {}.foregroundStyle(.red)
        case "e":
            Button("One") {}
            Button("Two") {}
            Button("Three") {}
            Button("Four") {}
        default:
            Button("Plain") {}
            Button("DisDef") {}.keyboardShortcut(.defaultAction).disabled(true)
        }
    }
}

struct PickerMenus: Commands {
    var body: some Commands {
        CommandMenu("Pickers") {
            Picker("Default", selection: .constant(1)) { Text("D1").tag(1); Text("D2").tag(2) }
            Picker("Inline", selection: .constant(1)) { Text("I1").tag(1); Text("I2").tag(2) }
                .pickerStyle(.inline)
            Picker("MenuStyle", selection: .constant(2)) { Text("M1").tag(1); Text("M2").tag(2) }
                .pickerStyle(.menu)
            Picker("Segmented", selection: .constant(1)) { Text("G1").tag(1); Text("G2").tag(2) }
                .pickerStyle(.segmented)
            Picker("Palette", selection: .constant(1)) { Text("A1").tag(1); Text("A2").tag(2) }
                .pickerStyle(.palette)
            Picker("Radio", selection: .constant(1)) { Text("R1").tag(1); Text("R2").tag(2) }
                .pickerStyle(.radioGroup)
            Picker("Sectioned", selection: .constant(3)) {
                Text("S1").tag(1)
                Section("Group") { Text("S2").tag(2); Text("S3").tag(3) }
            }
            Picker("Disabled", selection: .constant(1)) { Text("X1").tag(1) }.disabled(true)
            Picker(selection: .constant(1)) { Text("L1").tag(1) } label: { Label("Labelled", systemImage: "star") }
            Picker("", selection: .constant(1)) { Text("E1").tag(1); Text("E2").tag(2) }
            Picker("Nothing", selection: .constant(9)) { Text("N1").tag(1); Text("N2").tag(2) }
            Picker("WithDivider", selection: .constant(1)) { Text("V1").tag(1); Divider(); Text("V2").tag(2) }
        }
        CommandMenu("Menus") {
            Menu("Outer") {
                Button("O1") {}
                Menu("Inner") { Button("In1") {}.keyboardShortcut("j") }
            }
            Menu("Empty") {}
            Menu("DisabledSub") { Button("DS1") {} }.disabled(true)
            Menu("ButtonStyle") { Button("B1") {} }.menuStyle(.button)
            Menu("WithPrimary") { Button("P1") {} } primaryAction: {}
            Menu("AllDisabled") { Button("AD1") {}.disabled(true) }
            Menu { Button("Lb1") {} } label: { Label("LabelMenu", systemImage: "star") }
            Menu("Key") { Button("K1") {} }.keyboardShortcut("u")
            Menu("Help") { Button("H1") {} }.help("menu tip")
        }
    }
}

@main
struct ProbeApp: App {
    var body: some Scene {
        #if CASE_pickers
        WindowGroup { Text("probe").frame(width: 200, height: 100) }.commands { PickerMenus() }
        #else
        WindowGroup { AlertView() }
        #endif
    }
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        #if !CASE_pickers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let made = NSWindow(contentViewController: NSHostingController(rootView: AlertView()))
            made.makeKeyAndOrderFront(nil)
            Keep.window = made
        }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            print("== case \(probeCase)")
            #if CASE_pickers
            if let main = NSApp.mainMenu {
                for item in main.items where ["Pickers", "Menus"].contains(item.title) {
                    print("MENU \(item.title)")
                    if let sub = item.submenu { dump(sub, indent: "    ") }
                }
            }
            #else
            for window in NSApp.windows {
                print("window \(window.className) title=\(window.title) visible=\(window.isVisible)"
                    + " default=\(window.defaultButtonCell?.title ?? "nil")"
                    + " sheet=\(window.attachedSheet.map { $0.className } ?? "nil")")
                if let content = window.contentView { dumpButtons(content, indent: "  ") }
                if let sheet = window.attachedSheet, let content = sheet.contentView {
                    print("  sheet:")
                    dumpButtons(content, indent: "    ")
                }
            }
            #endif
            exit(0)
        }
    }
}
