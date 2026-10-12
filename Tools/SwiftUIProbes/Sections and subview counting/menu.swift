import SwiftUI
import AppKit

@MainActor func findButtons(_ v: NSView) -> [NSView] {
    var out: [NSView] = []
    if v is NSPopUpButton || v is NSButton || String(describing: type(of: v)).contains("Menu") { out.append(v) }
    for s in v.subviews { out += findButtons(s) }
    return out
}

@MainActor func dump(_ menu: NSMenu, indent: String = "") {
    for item in menu.items {
        var flags: [String] = []
        if item.isSeparatorItem { flags.append("separator") }
        if #available(macOS 14.0, *), item.isSectionHeader { flags.append("sectionHeader") }
        if !item.isEnabled { flags.append("disabled") }
        if item.attributedTitle != nil { flags.append("attributed") }
        print("\(indent)- '\(item.title)' \(flags.joined(separator: ","))")
        if let sub = item.submenu { dump(sub, indent: indent + "    ") }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let views: [(String, AnyView)] = [
                ("sections", AnyView(Menu("M") {
                    Button("Loose") {}
                    Section("First") { Button("A") {}; Button("B") {} }
                    Section("Second") { Button("C") {} }
                    Section { Button("D") {} }
                })),
                ("sections-first", AnyView(Menu("M") {
                    Section("First") { Button("A") {} }
                    Section("Second") { Button("C") {} }
                    Button("Tail") {}
                })),
                ("foreach-sections", AnyView(Menu("M") {
                    ForEach(0..<2, id: \.self) { i in Section("S\(i)") { Button("x\(i)") {} } }
                })),
            ]
            for (name, v) in views {
                let h = host(v, size: CGSize(width: 200, height: 50))
                spin(0.3)
                print("== \(name)")
                for b in findButtons(h) {
                    if let p = b as? NSPopUpButton, let m = p.menu {
                        m.delegate?.menuNeedsUpdate?(m)
                        m.delegate?.menuWillOpen?(m)
                        m.update()
                        print(" popup: delegate=\(String(describing: m.delegate)) items=\(m.items.count)"); dump(m)
                        m.delegate?.menuDidClose?(m)
                    }
                    else if let m = b.menu { print(" \(type(of: b)) menu:"); dump(m) }
                }
            }
        }
    }
}
