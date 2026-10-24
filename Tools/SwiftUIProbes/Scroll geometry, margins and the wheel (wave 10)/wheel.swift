import SwiftUI
import AppKit

func stamp() -> String { String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)) }
struct Wheel: View {
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(0..<40, id: \.self) { _ in Color.green.frame(height: 50) } } }
            .onScrollPhaseChange { o, n, c in print(stamp(), "phase", o, "->", n, "vel", c.velocity as Any, "y", c.geometry.contentOffset.y) }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in print(stamp(), "y", y) }
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let sz = CGSize(width: 300, height: 300)
            let h = host(Wheel(), size: sz); spin(0.5)
            guard let win = h.window, let sv = findScrollViews(h).first else { print("no window/sv"); return }
            let centre = win.convertPoint(toScreen: NSPoint(x: 150, y: 150))
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            func send(_ units: CGScrollEventUnit, _ d: Int32) {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1, wheel1: d, wheel2: 0, wheel3: 0) else { return }
                cg.location = CGPoint(x: centre.x, y: primaryHeight - centre.y)
                guard let ev = NSEvent(cgEvent: cg) else { return }
                print(stamp(), "-- send", units == .line ? "line" : "pixel", d, "phase", ev.phase.rawValue, "momentum", ev.momentumPhase.rawValue, "precise", ev.hasPreciseScrollingDeltas)
                win.sendEvent(ev); _ = sv
            }
            send(.line, -3); spin(1.5)
            for _ in 0..<3 { send(.line, -3); spin(0.05) }
            spin(1.5)
            send(.pixel, -40); spin(1.5)
        }
    }
}
