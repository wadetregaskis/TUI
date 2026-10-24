import SwiftUI
import AppKit

func cells(_ v: NSView) -> [NSView] {
    var out: [NSView] = []
    if String(describing: type(of: v)).hasPrefix("ListTableCellView") { out.append(v) }
    for c in v.subviews { out += cells(c) }
    return out
}
func digest(_ d: Data) -> String {
    var h: UInt64 = 1469598103934665603
    for b in d { h = (h ^ UInt64(b)) &* 1099511628211 }
    return String(h, radix: 16)
}

final class Delegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func make<V: View>(_ v: V) -> NSWindow {
        let host = NSHostingView(rootView: v.tabViewStyle(.sidebarAdaptable).frame(width: 400, height: 300))
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        w.orderFrontRegardless()
        return w
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        windows = [
            make(TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") } }),
            make(TabView { Tab { Text("A") } label: { Label { Text(verbatim: "**Bold** tab") } icon: { Image(systemName: "star") } } }),
            make(TabView { Tab { Text("A") } label: { Label { Text("**Bold** tab") } icon: { Image(systemName: "star") } } }),
            make(TabView { Tab("Bold tab", systemImage: "star") { Text("A") } }),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for (name, w) in zip(["A key", "B verbatim", "C Text md", "D plain"], self.windows) {
                guard let cell = cells(w.contentView!).first else { print(name, "no cell"); continue }
                let rep = cell.bitmapImageRepForCachingDisplay(in: cell.bounds)!
                cell.cacheDisplay(in: cell.bounds, to: rep)
                var dark = 0
                for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh { if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5, c.brightnessComponent < 0.5 { dark += 1 } } }
                print(name, digest(rep.tiffRepresentation!), "dark px:", dark)
            }
            NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let d = Delegate()
app.delegate = d
app.run()
