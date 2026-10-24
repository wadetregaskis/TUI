import SwiftUI
import AppKit

struct VisRows: View {
    let tag: String
    @Binding var pos: ScrollPosition
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { i in
                    Color.blue.frame(height: 50)
                        .onScrollVisibilityChange(threshold: 0.5) { v in print(tag, "row", i, "visible", v) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($pos)
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ids in print(tag, "targets", ids) }
    }
}
struct VisProbe: View {
    @State var pos = ScrollPosition(idType: Int.self)
    var body: some View {
        VisRows(tag: "vis", pos: $pos)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { print("-- scrollTo(y:30)"); pos.scrollTo(y: 30) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { print("-- scrollTo(y:500)"); pos.scrollTo(y: 500) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { print("-- read viewID", pos.viewID as Any) }
            }
    }
}
struct Wheel: View {
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(0..<40, id: \.self) { _ in Color.green.frame(height: 50) } } }
            .onScrollPhaseChange { o, n, c in print(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)), "wheel phase", o, "->", n, "vel", c.velocity as Any, "y", c.geometry.contentOffset.y) }
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 300, height: 300)
            _ = host(VisProbe(), size: sz); spin(1.2)
            _ = host(Color.red.frame(width: 50, height: 50).onScrollVisibilityChange { v in print("outside scroll view visible", v) }, size: sz); spin(0.5)
            let h = host(Wheel(), size: sz); spin(0.5)
            let svs = findScrollViews(h)
            print("scroll views found", svs.count)
            if let sv = svs.first, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0), let ev = NSEvent(cgEvent: cg) {
                print(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)), "-- send wheel line -3")
                sv.scrollWheel(with: ev)
                spin(1.5)
                print(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)), "-- send 3 wheel ticks 50ms apart")
                for _ in 0..<3 { sv.scrollWheel(with: ev); spin(0.05) }
                spin(1.5)
            }
        }
    }
}
