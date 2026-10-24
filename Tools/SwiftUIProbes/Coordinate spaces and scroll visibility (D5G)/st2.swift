import SwiftUI
import AppKit

struct Rows: View {
    let configuration: ScrollTransitionConfiguration?
    let offset: CGFloat
    @State var pos: ScrollPosition
    init(configuration: ScrollTransitionConfiguration?, offset: CGFloat) {
        self.configuration = configuration
        self.offset = offset
        _pos = State(initialValue: ScrollPosition(y: offset))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { i in
                    if let configuration {
                        Color.red.frame(height: 20)
                            .scrollTransition(configuration) { content, phase in content.opacity(phase.isIdentity ? 1 : 0) }
                    } else {
                        Color.red.frame(height: 20)
                            .scrollTransition { content, phase in content.opacity(phase.isIdentity ? 1 : 0) }
                    }
                }
            }
        }
        .scrollPosition($pos)
        .scrollIndicators(.never)
        .frame(width: 100, height: 100)
        .background(Color.white)
    }
}

@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}

@MainActor func run(_ tag: String, _ c: ScrollTransitionConfiguration?, offset: CGFloat) {
    let h = NSHostingView(rootView: AnyView(Rows(configuration: c, offset: offset)))
    h.frame = NSRect(origin: .zero, size: CGSize(width: 100, height: 100))
    h.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    h.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    if let sv = findScroll(h) { print("clip origin", sv.contentView.bounds.origin, "flipped", h.isFlipped) }
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { print("no rep"); return }
    print("rep", rep.pixelsWide, rep.pixelsHigh)
    h.cacheDisplay(in: h.bounds, to: rep)
    var line = "== \(tag) offset \(offset):"
    // sample each 5pt band down the view (rep is in pixels; flipped? sample by row index from top)
    let scale = CGFloat(rep.pixelsHigh) / 100
    for y in stride(from: 1, to: 100, by: 2) {
        let py = Int(CGFloat(y) * scale)
        let c = rep.colorAt(x: Int(50 * scale), y: py)?.usingColorSpace(.sRGB)
        let alpha = 1 - (c?.greenComponent ?? -1)
        line += String(format: " y%d=%.2f", y, alpha)
    }
    print(line)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            run("warmup", nil, offset: 55)
            run("default", nil, offset: 55)
            run("interactive", .interactive, offset: 55)
            run("interactive-linear", .interactive(timingCurve: .linear), offset: 55)
            run("animated", .animated, offset: 55)
            run("default", nil, offset: 50)
        }
    }
}
