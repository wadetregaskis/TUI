import SwiftUI
import AppKit

@MainActor func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        var flags: [String] = []
        if item.isSeparatorItem { flags.append("separator") }
        if #available(macOS 14.0, *), item.isSectionHeader { flags.append("sectionHeader") }
        if !item.isEnabled { flags.append("disabled") }
        if let a = item.attributedTitle { flags.append("attributed:\(a)") }
        if item.view != nil { flags.append("customView") }
        print("\(indent)- '\(item.title)' \(flags.joined(separator: ","))")
        if let sub = item.submenu, indent.count < 8 { dump(sub, indent: indent + "    ") }
    }
}

@main struct ProbeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("probe")
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if let main = NSApp.mainMenu {
                            for top in main.items where top.title.hasPrefix("Probe") {
                                print("== \(top.title)")
                                if let sub = top.submenu { dump(sub) }
                            }
                        }
                        exit(0)
                    }
                }
        }
        .commands {
            CommandMenu("Probe1") {
                Button("Loose") {}
                Section("First") { Button("A") {}; Button("B") {} }
                Section("Second") { Button("C") {} }
                Section { Button("D") {} }
                Menu("Sub") {
                    Section("Inner") { Button("E") {} }
                    Button("F") {}
                }
            }
            CommandMenu("Probe2") {
                Section("First") { Button("A") {} }
                Section("Second") { Button("C") {} }
                Button("Tail") {}
            }
            CommandMenu("Probe3") {
                ForEach(0..<2, id: \.self) { i in Section("S\(i)") { Button("x\(i)") {} } }
            }
        }
    }
}
