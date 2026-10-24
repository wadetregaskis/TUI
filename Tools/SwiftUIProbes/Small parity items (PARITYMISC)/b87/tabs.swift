import SwiftUI
import AppKit

func dump(_ v: NSView, _ depth: Int = 0) {
    let pad = String(repeating: "  ", count: depth)
    var extra = ""
    if let t = v as? NSTextField { extra = " text=\(t.attributedStringValue)" }
    if let b = v as? NSButton { extra = " button=\(b.attributedTitle)" }
    if let s = v as? NSSegmentedControl { extra = " segs=\((0..<s.segmentCount).map { s.label(forSegment: $0) ?? "?" })" }
    print(pad + String(describing: type(of: v)) + extra)
    for c in v.subviews { dump(c, depth + 1) }
}

func axDump(_ e: Any, _ depth: Int = 0) {
    guard depth < 12 else { return }
    let pad = String(repeating: "  ", count: depth)
    if let o = e as? NSAccessibilityElementProtocol & NSObject {
        let label = (o as? NSAccessibilityProtocol)?.accessibilityLabel() ?? ""
        let title = (o as? NSAccessibilityProtocol)?.accessibilityTitle() ?? ""
        let value = (o as? NSAccessibilityProtocol)?.accessibilityValue().map { "\($0)" } ?? ""
        let role = (o as? NSAccessibilityProtocol)?.accessibilityRole()?.rawValue ?? ""
        if !(label.isEmpty && title.isEmpty && value.isEmpty) { print(pad + "\(role) label=\(label) title=\(title) value=\(value)") }
        for c in ((o as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []) { axDump(c, depth + 1) }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let view = TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") }; Tab("Plain", systemImage: "star") { Text("B") } }
    let host = NSHostingView(rootView: view.frame(width: 400, height: 300))
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    dump(host)
    axDump(host)
}
