import AppKit
import SwiftUI

// What a SwiftUI TabView draws on this machine (macOS 15.8) in each style,
// with a section, a badge and a search-role tab. Writes PNGs and the view
// class tree.

struct Tabs<S: TabViewStyle>: View {
    let style: S
    @State var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            Tab("Inbox", systemImage: "tray", value: 0) { Text("inbox body") }
                .badge(3)
            Tab("Sent", systemImage: "paperplane", value: 1) { Text("sent body") }
            TabSection("Folders") {
                Tab("Work", systemImage: "folder", value: 2) { Text("work body") }
                Tab("Home", systemImage: "folder", value: 3) { Text("home body") }
            }
            Tab(value: 9, role: .search) { Text("search body") }
        }
        .tabViewStyle(style)
        .frame(width: 520, height: 260)
    }
}

@MainActor
func dump(_ name: String, _ view: some View) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    rep.representation(using: .png, properties: [:]).map {
        try? $0.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "tabs-\(name).png"))
    }
    print("== \(name)")
    func walk(_ v: NSView, _ depth: Int) {
        let cls = String(describing: type(of: v))
        if depth < 9 { print(String(repeating: " ", count: depth), cls, v.frame) }
        for s in v.subviews { walk(s, depth + 1) }
    }
    walk(host, 0)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    dump("automatic", Tabs(style: .automatic))
    dump("tabBarOnly", Tabs(style: .tabBarOnly))
    dump("grouped", Tabs(style: .grouped))
    dump("sidebarAdaptable", Tabs(style: .sidebarAdaptable))
}
