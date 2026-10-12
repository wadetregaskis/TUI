import AppKit
import SwiftUI

// Which macOS List styles float (pin) their section headers: NSTableView.floatsGroupRows
// per style, plus the separator style the table view uses (gridStyleMask / style).
struct Sections<S: ListStyle>: View {
    let style: S
    var body: some View {
        List {
            Section("Fruit") { ForEach(0..<30) { Text("Fruit \($0)") } }
            Section("Veg") { ForEach(0..<30) { Text("Veg \($0)") } }
        }
        .listStyle(style)
        .frame(width: 260, height: 200)
    }
}

@MainActor
func dump(_ name: String, _ view: some View) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 260, height: 200)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    func walk(_ v: NSView) {
        if let table = v as? NSTableView {
            print(name, "style", table.style.rawValue, "floatsGroupRows", table.floatsGroupRows,
                  "gridStyleMask", table.gridStyleMask.rawValue, "intercell", table.intercellSpacing)
        }
        for s in v.subviews { walk(s) }
    }
    walk(host)
}

@main
struct Probe {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            dump("automatic", Sections(style: .automatic))
            dump("plain", Sections(style: .plain))
            dump("inset", Sections(style: .inset))
            dump("bordered", Sections(style: .bordered))
            dump("sidebar", Sections(style: .sidebar))
        }
    }
}
