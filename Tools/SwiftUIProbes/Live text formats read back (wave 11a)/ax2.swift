import SwiftUI
import AppKit

@MainActor func dump(_ e: NSAccessibilityElementProtocol, _ depth: Int = 0) {
    let o = e as AnyObject
    let p = o as? NSAccessibilityProtocol
    let role = p?.accessibilityRole()?.rawValue ?? "?"
    let label = p?.accessibilityLabel() ?? ""
    let value = p?.accessibilityValue() as? String ?? ""
    print(String(repeating: "  ", count: depth), role, label.debugDescription, value.debugDescription)
    for k in p?.accessibilityChildren() ?? [] {
        if let kk = k as? NSAccessibilityElementProtocol { dump(kk, depth + 1) }
    }
}

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        let now = Date()
        let h = NSHostingView(rootView: VStack { Text(now, style: .time); Text("hello") }.fixedSize())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled],
            backing: .buffered, defer: false)
        w.contentView = h
        w.orderFrontRegardless()
        h.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        dump(h)
    }
}
