import SwiftUI
import AppKit

func scrollers(_ v: NSView) -> [NSScrollView] {
    var out: [NSScrollView] = []
    if let s = v as? NSScrollView { out.append(s) }
    for c in v.subviews { out += scrollers(c) }
    return out
}

@MainActor func probe<V: View>(_ name: String, _ view: V) {
    let host = NSHostingView(rootView: view.frame(width: 200, height: 100))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    let s = scrollers(host)
    for sv in s {
        print(name, "hasV:", sv.hasVerticalScroller, "hasH:", sv.hasHorizontalScroller,
              "vHidden:", sv.verticalScroller?.isHidden as Any, "autohides:", sv.autohidesScrollers, "style:", sv.scrollerStyle.rawValue)
    }
    if s.isEmpty { print(name, "no NSScrollView") }
}

struct Rows: View {
    var body: some View { VStack { ForEach(0..<50) { Text("Row \($0)") } } }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    probe("plain", ScrollView { Rows() })
    var hidden = ScrollView { Rows() }
    hidden.showsIndicators = false
    probe("showsIndicators=false", hidden)
    probe("modifier .hidden", ScrollView { Rows() }.scrollIndicators(.hidden))
    probe("modifier .never", ScrollView { Rows() }.scrollIndicators(.never))
    probe("false + .visible", hidden.scrollIndicators(.visible))
    probe("false + .automatic", hidden.scrollIndicators(.automatic))
    var shown = ScrollView { Rows() }
    shown.showsIndicators = true
    probe("true + .hidden", shown.scrollIndicators(.hidden))
    probe("false + .never", hidden.scrollIndicators(.never))
    probe("false, .visible outer of VStack", VStack { hidden }.scrollIndicators(.visible))
    var outer = ScrollView { VStack { ScrollView { Rows() }.frame(height: 50); Rows() } }
    outer.showsIndicators = false
    probe("nested: outer false, inner default", outer)
}
