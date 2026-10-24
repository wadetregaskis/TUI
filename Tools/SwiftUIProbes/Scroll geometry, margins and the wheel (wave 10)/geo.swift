import SwiftUI
import AppKit

struct Rows: View {
    var body: some View {
        VStack(spacing: 0) { ForEach(0..<20, id: \.self) { i in Color.blue.frame(height: 50).id(i) } }
    }
}
struct GeoProbe<M: View>: View {
    let name: String
    let modify: (AnyView) -> M
    @State var pos = ScrollPosition(idType: Int.self)
    var body: some View {
        modify(AnyView(ScrollView { Rows() }.scrollPosition($pos)))
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { old, new in print(name, "geo", g(new)) }
            .onScrollPhaseChange { old, new, ctx in print(name, "phase", old, "->", new, "vel", ctx.velocity as Any) }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { print(name, "-- scrollTo(y:100)"); pos.scrollTo(y: 100) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { print(name, "-- read pos point=", pos.point as Any, "viewID=", pos.viewID as Any, "edge=", pos.edge as Any, "user=", pos.isPositionedByUser) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { print(name, "-- withAnimation scrollTo(id: 10)"); withAnimation { pos.scrollTo(id: 10) } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { print(name, "-- read pos point=", pos.point as Any, "viewID=", pos.viewID as Any, "user=", pos.isPositionedByUser) }
            }
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 200, height: 300)
            _ = host(GeoProbe(name: "plain", modify: { $0 }), size: sz); spin(2)
            _ = host(GeoProbe(name: "margins20", modify: { $0.contentMargins(20) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "marginsV20content", modify: { $0.contentMargins(.vertical, 20, for: .scrollContent) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "margins20indicators", modify: { $0.contentMargins(20, for: .scrollIndicators) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "safeArea15", modify: { $0.safeAreaPadding(15) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "safe15+margins20", modify: { $0.contentMargins(20).safeAreaPadding(15) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "margins20+margins5outer", modify: { $0.contentMargins(20).contentMargins(5) }), size: sz); spin(2)
            _ = host(GeoProbe(name: "padding-then-safe", modify: { $0.padding(16).safeAreaPadding(10) }), size: sz); spin(2)
        }
    }
}
