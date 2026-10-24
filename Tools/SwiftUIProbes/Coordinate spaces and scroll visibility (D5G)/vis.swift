import SwiftUI
import AppKit

@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}

@MainActor final class Model: ObservableObject {
    @Published var showRow7 = true
}

struct Rows: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<60, id: \.self) { i in
                    if i != 7 || model.showRow7 {
                        Color.gray.frame(height: 10)
                            .onScrollVisibilityChange { v in print("row", i, "visible", v) }
                    }
                }
            }
        }
        .frame(width: 100, height: 95)
    }
}

struct Outside: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 90)
            Color.blue.frame(height: 20)
                .onScrollVisibilityChange { v in print("outside (half in window)", v) }
            Color.green.frame(height: 20)
                .onScrollVisibilityChange(threshold: 0.0) { v in print("outside below window thr0", v) }
        }
        .frame(width: 100, height: 130, alignment: .top)
    }
}

@MainActor func pump(_ h: NSView) {
    h.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    h.layoutSubtreeIfNeeded()
}

@MainActor func run() {
    let model = Model()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: Rows(model: model))
    h.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    window.contentView = h
    window.orderFrontRegardless()
    print("== initial")
    pump(h)
    guard let s = findScroll(h) else { print("no scroll"); return }
    for y in [5.0, 10.0, 40.0, 300.0, 0.0] {
        print("== scroll to", y)
        s.contentView.scroll(to: NSPoint(x: 0, y: y))
        s.reflectScrolledClipView(s.contentView)
        pump(h)
    }
    print("== remove row 7")
    model.showRow7 = false
    pump(h)

    print("== outside any scroll view (window 100 tall)")
    let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    let h2 = NSHostingView(rootView: Outside())
    h2.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    w2.contentView = h2
    w2.orderFrontRegardless()
    pump(h2)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
