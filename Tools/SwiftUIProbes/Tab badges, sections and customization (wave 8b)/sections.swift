import AppKit
import SwiftUI

// Section(isExpanded:) in a List, per list style, expanded and collapsed, on
// this machine (macOS 15.8). Writes PNGs; prints the table view's style.

struct Sections<S: ListStyle>: View {
    let style: S
    let expanded: Bool
    var body: some View {
        List {
            Text("Loose row")
            Section("Fruit", isExpanded: .constant(expanded)) {
                Text("Apple")
                Text("Pear")
            }
            Section("Veg") {
                Text("Leek")
            }
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
    window.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    rep.representation(using: .png, properties: [:]).map {
        try? $0.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "sections-\(name).png"))
    }
    func walk(_ v: NSView) {
        if let table = v as? NSTableView {
            print(name, "table style", table.style.rawValue, "rows", table.numberOfRows,
                  "alternating", table.usesAlternatingRowBackgroundColors,
                  "gridStyle", table.gridStyleMask.rawValue)
        }
        if let scroll = v as? NSScrollView { print(name, "scroll border", scroll.borderType.rawValue) }
        for s in v.subviews { walk(s) }
    }
    walk(host)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    dump("automatic-open", Sections(style: .automatic, expanded: true))
    dump("automatic-closed", Sections(style: .automatic, expanded: false))
    dump("sidebar-open", Sections(style: .sidebar, expanded: true))
    dump("sidebar-closed", Sections(style: .sidebar, expanded: false))
    dump("inset-closed", Sections(style: .inset, expanded: false))
    dump("plain-closed", Sections(style: .plain, expanded: false))
    dump("bordered-closed", Sections(style: .bordered, expanded: false))
}
