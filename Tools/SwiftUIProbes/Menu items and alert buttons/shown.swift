// Probe: how tall macOS 15.8 DRAWS a menu whose items differ only in leading,
// trailing and doubled separators — pops each up and reads the menu window's
// bounds (CGWindowList, no screen capture needed) while it tracks (shown.out).
// `size` is NSMenu.size once the menu is up. Needs a logged-in session: the
// probe opens a window and pops each menu up over it.
//   xcrun swiftc -O shown.swift -o "$TMPDIR/shown" && "$TMPDIR/shown"
import AppKit

func menu(_ spec: [String]) -> NSMenu {
    let m = NSMenu()
    for s in spec {
        if s == "-" { m.addItem(.separator()) }
        else if s.hasPrefix("#") { m.addItem(.sectionHeader(title: String(s.dropFirst()))) }
        else { m.addItem(withTitle: s, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "") }
    }
    return m
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let cases: [(String, [String])] = [
    ("A B", ["A", "B"]),
    ("- A B", ["-", "A", "B"]),
    ("A B -", ["A", "B", "-"]),
    ("A - B", ["A", "-", "B"]),
    ("A - - B", ["A", "-", "-", "B"]),
    ("- #H A -", ["-", "#H", "A", "-"]),
    ("#H A", ["#H", "A"]),
]
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

func shownHeight() -> [String] {
    let pid = ProcessInfo.processInfo.processIdentifier
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info in
        guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
            let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        return "layer \(layer) h \(bounds["Height"] ?? "?") w \(bounds["Width"] ?? "?")"
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    for (name, spec) in cases {
        let m = menu(spec)
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
            print(name.padding(toLength: 14, withPad: " ", startingAt: 0), "size", m.size, "shown", shownHeight().filter { !$0.hasPrefix("layer 0 ") })
            m.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        m.popUp(positioning: nil, at: NSPoint(x: 20, y: 250), in: window.contentView)
    }
    exit(0)
}
app.run()
