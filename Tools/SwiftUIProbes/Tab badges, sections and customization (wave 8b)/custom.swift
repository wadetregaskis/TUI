import AppKit
import SwiftUI

// TabView customization on this machine (macOS 15.8): defaultVisibility(_:for:)
// for each placement under each style, and a TabViewCustomization that hides a
// tab from the sidebar. Writes PNGs.

struct Tabs<S: TabViewStyle>: View {
    let style: S
    let placement: AdaptableTabBarPlacement?
    let hideBySidebarVisibility: Bool
    @State var selection = 0
    @State var customization = TabViewCustomization()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Inbox", systemImage: "tray", value: 0) { Text("inbox body") }
                .customizationID("inbox")
            if let placement {
                Tab("Hidden", systemImage: "eye.slash", value: 1) { Text("hidden body") }
                    .customizationID("hiddenTab")
                    .defaultVisibility(.hidden, for: placement)
            } else {
                Tab("Hidden", systemImage: "eye.slash", value: 1) { Text("hidden body") }
                    .customizationID("hiddenTab")
            }
            TabSection("Folders") {
                Tab("Work", systemImage: "folder", value: 2) { Text("work body") }
                    .customizationID("work")
                Tab("Home", systemImage: "folder", value: 3) { Text("home body") }
                    .customizationID("home")
            }
            .customizationID("folders")
        }
        .tabViewStyle(style)
        .tabViewCustomization($customization)
        .frame(width: 520, height: 260)
        .onAppear {
            if hideBySidebarVisibility {
                customization[tab: "hiddenTab"].sidebarVisibility = .hidden
            }
            print("tab order (folders):", customization[section: "folders"].tabOrder as Any)
            print("visibility of hiddenTab:", customization[tab: "hiddenTab"].sidebarVisibility)
            print("visibility of inbox:", customization[tab: "inbox"].sidebarVisibility)
            if let data = try? JSONEncoder().encode(customization) {
                print("encoded:", String(decoding: data, as: UTF8.self))
            }
        }
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
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    rep.representation(using: .png, properties: [:]).map {
        try? $0.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "custom-\(name).png"))
    }
    print("== \(name)")
    func walk(_ v: NSView) {
        if let seg = v as? NSSegmentedControl {
            print("  segments:", (0..<seg.segmentCount).map { seg.label(forSegment: $0) ?? "?" })
        }
        for s in v.subviews { walk(s) }
    }
    if let frame = window.contentView?.superview { walk(frame) }
    print("  toolbar items:", window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? [])
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    dump("tabBarOnly-hidden-tabBar", Tabs(style: .tabBarOnly, placement: .tabBar, hideBySidebarVisibility: false))
    dump("tabBarOnly-hidden-automatic", Tabs(style: .tabBarOnly, placement: .automatic, hideBySidebarVisibility: false))
    dump("sidebar-hidden-tabBar", Tabs(style: .sidebarAdaptable, placement: .tabBar, hideBySidebarVisibility: false))
    dump("sidebar-hidden-automatic", Tabs(style: .sidebarAdaptable, placement: .automatic, hideBySidebarVisibility: false))
    dump("sidebar-customization-hidden", Tabs(style: .sidebarAdaptable, placement: nil, hideBySidebarVisibility: true))
    dump("tabBarOnly-customization-hidden", Tabs(style: .tabBarOnly, placement: nil, hideBySidebarVisibility: true))
}
