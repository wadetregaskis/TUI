import SwiftUI
import AppKit

func dump(_ v: NSView, _ depth: Int = 0) {
    let pad = String(repeating: "  ", count: depth)
    var extra = ""
    if let t = v as? NSTextField { extra = " text=\(t.attributedStringValue)" }
    if let b = v as? NSButton { extra = " button=\(b.attributedTitle)" }
    if let s = v as? NSSegmentedControl { extra = " segs=\((0..<s.segmentCount).map { s.label(forSegment: $0) ?? "?" })" }
    if let t = v as? NSTabView { extra = " items=\(t.tabViewItems.map(\.label))" }
    print(pad + String(describing: type(of: v)).prefix(80) + extra)
    for c in v.subviews { dump(c, depth + 1) }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let mode = CommandLine.arguments.dropFirst().first ?? "tab"
        let host: NSView
        switch mode {
        case "item":
            host = NSHostingView(rootView: TabView { Text("A").tabItem { Text("**Bold** tab") }; Text("B").tabItem { Text("Plain") } }.frame(width: 400, height: 300))
        case "bar":
            host = NSHostingView(rootView: TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") }; Tab("Plain", systemImage: "star") { Text("B") } }.tabViewStyle(.tabBarOnly).frame(width: 400, height: 300))
        case "side":
            host = NSHostingView(rootView: TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") }; Tab("Plain", systemImage: "star") { Text("B") } }.tabViewStyle(.sidebarAdaptable).frame(width: 400, height: 300))
        default:
            host = NSHostingView(rootView: TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") }; Tab("Plain", systemImage: "star") { Text("B") } }.frame(width: 400, height: 300))
        }
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dump(self.window.contentView!)
            func ax(_ e: Any, _ depth: Int) {
                guard depth < 15, let o = e as? NSObject else { return }
                let pad = String(repeating: "  ", count: depth)
                let role = o.value(forKey: "accessibilityRole") as? String ?? "?"
                let label = o.value(forKey: "accessibilityLabel") as? String ?? ""
                let title = o.value(forKey: "accessibilityTitle") as? String ?? ""
                let value = o.value(forKey: "accessibilityValue").map { "\($0)" } ?? ""
                print(pad + "\(type(of: o)) role=\(role) label=\(label) title=\(title) value=\(value)")
                for c in (o.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { ax(c, depth + 1) }
            }
            ax(self.window.contentView!, 0)
            NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let d = Delegate()
app.delegate = d
app.run()
