import SwiftUI
import AppKit

// B-D5G-8: does each of SwiftUI's default scroll transition configurations
// behave as the threshold `stmirror.swift` reads from it? Rows 20 points tall
// in a 100-point ScrollView, scrolled to `y`, a point further and back; each
// row's closure records the last phase it was called with during that move.
// SwiftUI calls the closure for the phases it interpolates between, not only
// the one drawn, so the rows listed are not the phases on screen; what the
// probe shows is that each default lists exactly what one explicit threshold
// lists, and not what the other does. Top-level code, built alone.

@MainActor var keep: [NSWindow] = []
@MainActor var phases: [Int: String] = [:]
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 100, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? {
    if let s = v as? T { return s }
    for c in v.subviews { if let s = find(c, t) { return s } }
    return nil
}
@MainActor func scrollClip(_ h: NSView, to y: CGFloat) {
    guard let sv = find(h, NSScrollView.self) else { print("no scroll view"); return }
    sv.contentView.scroll(to: NSPoint(x: 0, y: y))
    sv.reflectScrolledClipView(sv.contentView)
}
func name(_ p: ScrollTransitionPhase) -> String {
    switch p { case .topLeading: "T"; case .identity: "I"; case .bottomTrailing: "B"; @unknown default: "?" }
}

struct Rows: View {
    let configuration: ScrollTransitionConfiguration
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { i in
                    Color.red.frame(height: 20)
                        .scrollTransition(configuration) { content, phase in
                            MainActor.assumeIsolated { phases[i] = name(phase) }
                            return content.opacity(phase.isIdentity ? 1 : 0)
                        }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run(_ tag: String, _ c: ScrollTransitionConfiguration, y: CGFloat) {
        phases = [:]
        let h = host(Rows(configuration: c)); spin()
        scrollClip(h, to: y); spin()
        phases = [:]
        scrollClip(h, to: y + 1); spin()
        scrollClip(h, to: y); spin()
        let rows = phases.keys.sorted().map { "\($0):\(phases[$0]!)" }.joined(separator: " ")
        print(tag.padding(toLength: 38, withPad: " ", startingAt: 0), "y \(Int(y))", rows)
    }
    for y: CGFloat in [10, 5, 15, 30] {
        run("animated", .animated, y: y)
        run("animated.threshold(.visible)", .animated.threshold(.visible), y: y)
        run("animated.threshold(.visible(0.5))", .animated.threshold(.visible(0.5)), y: y)
        run("interactive", .interactive, y: y)
        run("interactive.threshold(.visible)", .interactive.threshold(.visible), y: y)
        run("interactive.threshold(.visible(0.5))", .interactive.threshold(.visible(0.5)), y: y)
    }
}
