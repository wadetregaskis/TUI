import AppKit
import SwiftUI

// Measures how a List row's badge draws under each BadgeProminence on this
// machine's SwiftUI (macOS 15.8). Renders offscreen and reports, for the badge
// region at the trailing edge of each row, the distinct colours found.

struct Rows: View {
    let prominence: BadgeProminence
    var body: some View {
        List {
            Text("Inbox").badge(12)
            Text("Drafts").badge(3)
        }
        .badgeProminence(prominence)
        .frame(width: 300, height: 120)
    }
}

@MainActor
func dump(_ name: String, _ view: some View) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    // Scan the right 60 pt of the first row band (y 0..40), count colours.
    var counts: [String: Int] = [:]
    for y in stride(from: 0, to: min(rep.pixelsHigh, 2 * 40), by: 1) {
        for x in stride(from: rep.pixelsWide - 2 * 70, to: rep.pixelsWide, by: 1) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let key = String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            counts[key, default: 0] += 1
        }
    }
    let top = counts.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key)×\($0.value)" }
    print(name, top.joined(separator: " "))
    // Also find the view classes involved.
    func walk(_ v: NSView, _ depth: Int) {
        let cls = String(describing: type(of: v))
        if cls.contains("Badge") || cls.contains("Cell") && depth < 14 { print(String(repeating: " ", count: depth), cls, v.frame) }
        for s in v.subviews { walk(s, depth + 1) }
    }
    walk(host, 0)
    rep.representation(using: .png, properties: [:]).map {
        try? $0.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "badge-\(name).png"))
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    dump("standard", Rows(prominence: .standard))
    dump("decreased", Rows(prominence: .decreased))
    dump("increased", Rows(prominence: .increased))
}
