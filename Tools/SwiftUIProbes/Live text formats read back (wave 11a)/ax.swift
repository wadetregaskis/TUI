import SwiftUI
import AppKit

// Reads what SwiftUI draws for a Text by walking the hosting view's
// accessibility tree.
@MainActor func strings(of element: Any, depth: Int = 0) -> [String] {
    var out: [String] = []
    if let e = element as? NSAccessibilityElementProtocol as? NSObject {
        let role = e.value(forKey: "accessibilityRole") as? String
        let label = (e.value(forKey: "accessibilityLabel") as? String) ?? ""
        let value = (e.value(forKey: "accessibilityValue") as? String) ?? ""
        if role == NSAccessibility.Role.staticText.rawValue || !label.isEmpty || !value.isEmpty {
            out.append("[\(role ?? "?")] label=\(label.debugDescription) value=\(value.debugDescription)")
        }
        if let kids = e.value(forKey: "accessibilityChildren") as? [Any] {
            for k in kids { out += strings(of: k, depth: depth + 1) }
        }
    }
    return out
}

@MainActor func show<V: View>(_ name: String, _ v: V) {
    let h = NSHostingView(rootView: v.fixedSize())
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    h.frame = NSRect(origin: .zero, size: h.fittingSize)
    h.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let s = strings(of: h)
    print(name, "→", s.joined(separator: " | "), "size", h.fittingSize)
}

MainActor.assumeIsolated {
    let now = Date()
    show("time", Text(now, style: .time))
    show("date", Text(now, style: .date))
    show("relative-125", Text(now.addingTimeInterval(-125), style: .relative))
}
