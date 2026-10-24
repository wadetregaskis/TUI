import AppKit
import SwiftUI

// What a tab's content reads for \.tabBarPlacement and \.isTabBarShowingSections
// under each style, on this machine (macOS 15.8).

struct Reader: View {
    let style: String
    @Environment(\.tabBarPlacement) var placement
    @Environment(\.isTabBarShowingSections) var showingSections
    var body: some View {
        Text("x").onAppear {
            print(style, "placement:", placement.map { "\($0)" } ?? "nil", "showingSections:", showingSections)
        }
    }
}

struct Tabs<S: TabViewStyle>: View {
    let name: String
    let style: S
    var body: some View {
        TabView {
            Tab("A", systemImage: "a.circle") { Reader(style: name) }
            TabSection("S") {
                Tab("B", systemImage: "b.circle") { Text("b") }
            }
        }
        .tabViewStyle(style)
        .frame(width: 400, height: 200)
    }
}

@MainActor
func host(_ view: some View) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    host(Tabs(name: "automatic", style: .automatic))
    host(Tabs(name: "tabBarOnly", style: .tabBarOnly))
    host(Tabs(name: "grouped", style: .grouped))
    host(Tabs(name: "sidebarAdaptable", style: .sidebarAdaptable))
}
