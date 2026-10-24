// Probe: what SwiftUI (macOS 15.8) shows of content that is not what its
// container sorts its members by — the semantic audit's root cause 5 (owner
// ruling RC5): an alert's actions that are not buttons, and a picker's
// content with no tag, or a tag of another type than the selection.
//
//   xcrun swiftc -parse-as-library -O -D CASE_pickers dropped.swift -o "$TMPDIR/dropped-pickers" && "$TMPDIR/dropped-pickers"
//   xcrun swiftc -parse-as-library -O -D CASE_alert dropped.swift -o "$TMPDIR/dropped-alert" && "$TMPDIR/dropped-alert"
//
// The alert case presents the alert from two windows, so prints it twice;
// alert.out is the first. Read back from the alert panel's AppKit views: a
// button, an editable text field, a label. The 128-point image is the app's
// icon, which every NSAlert shows.
import AppKit
import SwiftUI

func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        if item.isSeparatorItem { print(indent + "----"); continue }
        var line = indent + "\"" + item.title + "\""
        if item.state == .on { line += " (on)" }
        if !item.isEnabled { line += " (disabled)" }
        if item.isHidden { line += " (hidden)" }
        if item.view != nil { line += " (customView \(type(of: item.view!)))" }
        if item.submenu != nil { line += " ▸" }
        print(line)
        if let sub = item.submenu, indent.count < 12 { dump(sub, indent: indent + "    ") }
    }
}

func dumpViews(_ view: NSView, indent: String = "") {
    switch view {
    case let button as NSButton:
        print(indent + "NSButton \"\(button.title)\" type=\(type(of: button))")
    case let field as NSTextField where field.isEditable:
        print(indent + "editable \(type(of: field)) placeholder=\(field.placeholderString ?? "nil")")
    case let field as NSTextField:
        print(indent + "label \"\(field.stringValue)\"")
    case let image as NSImageView:
        print(indent + "NSImageView \(image.image.map { "\($0.size)" } ?? "nil")")
    default:
        break
    }
    for sub in view.subviews { dumpViews(sub, indent: indent) }
}

final class Keep: @unchecked Sendable { static var window: NSWindow? }

/// A view of the app's own around a button, and around a text field.
struct OwnButton: View {
    var body: some View { Button("OwnButton") {} }
}

struct OwnField: View {
    @Binding var text: String
    var body: some View { TextField("OwnFieldPlaceholder", text: $text) }
}

struct AlertView: View {
    @State var shown = false
    @State var name = ""
    @State var flag = true
    var body: some View {
        Text("probe")
            .frame(width: 300, height: 200)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shown = true } }
            .alert("Title", isPresented: $shown) {
                TextField("FieldPlaceholder", text: $name)
                SecureField("SecurePlaceholder", text: $name)
                Text("LooseText")
                Toggle("LooseToggle", isOn: $flag)
                Image(systemName: "star")
                OwnButton()
                OwnField(text: $name)
                Button("OK") {}
            } message: {
                Text("Message")
            }
    }
}

enum Fruit: Hashable { case apple, pear }

struct PickerMenus: Commands {
    var body: some Commands {
        CommandMenu("Pickers") {
            Picker("Untagged", selection: .constant(1)) {
                Text("T1").tag(1)
                Text("Loose")
                Text("T2").tag(2)
            }
            Picker("WrongType", selection: .constant(1)) {
                Text("W1").tag(1)
                Text("WString").tag("two")
                Text("WFruit").tag(Fruit.pear)
            }
            Picker("Optional", selection: .constant(Optional(1))) {
                Text("O1").tag(1)
                Text("ONone").tag(Int?.none)
            }
            Picker("NonText", selection: .constant(1)) {
                Text("N1").tag(1)
                Toggle("NToggle", isOn: .constant(true))
                Button("NButton") {}
            }
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
            #if CASE_pickers
            if let main = NSApp.mainMenu {
                for item in main.items where item.title == "Pickers" {
                    print("MENU \(item.title)")
                    if let sub = item.submenu { dump(sub, indent: "    ") }
                }
            }
            #else
            for window in NSApp.windows where window.className.contains("Alert") {
                print("window \(window.className)")
                if let content = window.contentView { dumpViews(content, indent: "  ") }
            }
            #endif
            exit(0)
        }
    }
}
