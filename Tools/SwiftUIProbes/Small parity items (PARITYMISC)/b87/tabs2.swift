import SwiftUI
import AppKit

@MainActor func render<V: View>(_ view: V) -> Data {
    let host = NSHostingView(rootView: view.frame(width: 360, height: 120))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.tiffRepresentation!
}

func digest(_ d: Data) -> String {
    var h: UInt64 = 1469598103934665603
    for b in d { h = (h ^ UInt64(b)) &* 1099511628211 }
    return String(h, radix: 16)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let a = render(TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") } })
    let b = render(TabView { Tab { Text("A") } label: { Label { Text(verbatim: "**Bold** tab") } icon: { Image(systemName: "star") } } })
    let c = render(TabView { Tab { Text("A") } label: { Label { Text("**Bold** tab") } icon: { Image(systemName: "star") } } })
    let d = render(TabView { Tab("Bold tab", systemImage: "star") { Text("A") } })
    print("A key      ", digest(a), a.count)
    print("B verbatim ", digest(b))
    print("C Text md  ", digest(c))
    print("D plain    ", digest(d))
    try? a.write(to: URL(fileURLWithPath: "tabA.tiff")); try? c.write(to: URL(fileURLWithPath: "tabC.tiff")); try? d.write(to: URL(fileURLWithPath: "tabD.tiff")); try? b.write(to: URL(fileURLWithPath: "tabB.tiff"))
}
