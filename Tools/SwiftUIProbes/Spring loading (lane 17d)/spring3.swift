// Probe 3: TabView spring loading on macOS 15.8, with the window on screen.
import AppKit
import SwiftUI

nonisolated(unsafe) var log: [String] = []
func say(_ s: String) { log.append(s); print(s) }

func walk(_ v: NSView, _ d: Int = 0) {
    let extra: String
    if let s = v as? NSSegmentedControl { extra = " segments=\(s.segmentCount) springLoaded=\(s.isSpringLoaded) selected=\(s.selectedSegment)" }
    else if let t = v as? NSTabView { extra = " tabs=\(t.numberOfTabViewItems)" }
    else if let b = v as? NSButton { extra = " springLoaded=\(b.isSpringLoaded) title=\(b.title)" }
    else { extra = "" }
    say(String(repeating: "  ", count: d) + String(describing: type(of: v)).prefix(80) + " frame=\(v.frame)" + extra)
    for s in v.subviews { walk(s, d + 1) }
}

@MainActor
final class Model {
    var tab = 1 { didSet { say("  -> tab selection set to \(tab)") } }
}

@main
struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = Model()
        let binding = Binding(get: { model.tab }, set: { model.tab = $0 })
        for (name, b) in [("automatic", SpringLoadingBehavior.automatic), ("enabled", .enabled), ("disabled", .disabled)] {
            say("=== tabItem TabView, \(name)")
            let view = TabView(selection: binding) {
                Text("one").tabItem { Text("One") }.tag(1)
                Text("two").tabItem { Text("Two") }.tag(2)
            }.springLoadingBehavior(b)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
            let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            walk(hosting)
            window.orderOut(nil)
        }
        if #available(macOS 15.0, *) {
            for (name, b) in [("automatic", SpringLoadingBehavior.automatic), ("enabled", .enabled), ("disabled", .disabled)] {
                say("=== Tab-API TabView, tab .springLoadingBehavior(\(name))")
                let view = TabView(selection: binding) {
                    Tab("One", systemImage: "star", value: 1) { Text("one") }
                    Tab("Two", systemImage: "star", value: 2) { Text("two") }.springLoadingBehavior(b)
                }
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
                let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = hosting
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                walk(hosting)
                window.orderOut(nil)
            }
        }
    }
}
