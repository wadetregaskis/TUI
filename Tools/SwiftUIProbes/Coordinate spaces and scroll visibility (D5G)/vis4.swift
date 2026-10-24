import SwiftUI
import AppKit

@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}

@MainActor final class Model: ObservableObject {
    @Published var showRow7 = true
    @Published var pos = ScrollPosition(y: 0)
}

struct Rows: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<60, id: \.self) { i in
                    if i != 7 || model.showRow7 {
                        Color.gray.frame(height: 10)
                            .onScrollVisibilityChange { v in print("row", i, "visible", v) }
                    }
                }
            }
        }
        .scrollPosition($model.pos)
        .frame(width: 100, height: 95)
    }
}

struct Outside: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.red.frame(width: 100, height: 100)
            Color.blue.frame(width: 20, height: 20).offset(y: 400)
                .onScrollVisibilityChange(threshold: 1.0) { v in print("outside blue far below, thr1.0", v) }
            Color.orange.frame(width: 20, height: 20).offset(x: 500, y: 0)
                .onScrollVisibilityChange { v in print("outside orange far right, thr0.5", v) }
            Color.green.frame(width: 20, height: 20).offset(y: 300)
                .onScrollVisibilityChange(threshold: 0.0) { v in print("outside green far below window thr0", v) }
            Color.yellow.frame(width: 20, height: 20).offset(x: 40, y: 85)
                .onScrollVisibilityChange(threshold: 0.9) { v in print("outside yellow 75% in, thr0.9", v) }
        }
        .frame(width: 100, height: 100, alignment: .topLeading)
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
    for y in [5.0, 10.0, 40.0, 300.0, 0.0] {
        print("== scroll to", y)
        model.pos.scrollTo(y: y)
        pump(h)
        if let s = findScroll(h) { print("   clip", s.contentView.bounds.origin.y) }
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
