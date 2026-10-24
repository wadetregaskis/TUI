import SwiftUI
import AppKit

struct Probe<M: View>: View {
    let name: String
    let modify: (AnyView) -> M
    var body: some View {
        modify(AnyView(ScrollView { VStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.blue.frame(height: 50) } } }))
            .onScrollGeometryChange(for: String.self, of: { "insets=(t\($0.contentInsets.top) l\($0.contentInsets.leading) b\($0.contentInsets.bottom) tr\($0.contentInsets.trailing)) size=\($0.contentSize) container=\($0.containerSize)" }) { _, new in print(name, new) }
    }
}
struct Nested: View {
    var body: some View {
        ScrollView {
            ScrollView(.horizontal) {
                HStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.red.frame(width: 50, height: 50) } }
            }
            .onScrollGeometryChange(for: String.self, of: { "inner insets=(t\($0.contentInsets.top) l\($0.contentInsets.leading) b\($0.contentInsets.bottom) tr\($0.contentInsets.trailing))" }) { _, new in print("nested", new) }
            Color.blue.frame(height: 800)
        }
        .contentMargins(20)
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 200, height: 300)
            _ = host(Probe(name: "top20 inner, horiz10 outer", modify: { $0.contentMargins(.top, 20).contentMargins(.horizontal, 10) }), size: sz); spin(0.5)
            _ = host(Probe(name: "scrollContent20 inner, automatic5 outer", modify: { $0.contentMargins(20, for: .scrollContent).contentMargins(5) }), size: sz); spin(0.5)
            _ = host(Probe(name: "automatic5 inner, scrollContent20 outer", modify: { $0.contentMargins(5).contentMargins(20, for: .scrollContent) }), size: sz); spin(0.5)
            _ = host(Probe(name: "nil length", modify: { $0.contentMargins(.all, nil) }), size: sz); spin(0.5)
            _ = host(Probe(name: "edges+insets: .top of (t7 l3 b9 tr4)", modify: { $0.contentMargins(.top, EdgeInsets(top: 7, leading: 3, bottom: 9, trailing: 4)) }), size: sz); spin(0.5)
            _ = host(Probe(name: "safeArea nil length", modify: { $0.safeAreaPadding(.all, nil) }), size: sz); spin(0.5)
            _ = host(Probe(name: "safeArea 10 then safeArea 5 outer", modify: { $0.safeAreaPadding(10).safeAreaPadding(5) }), size: sz); spin(0.5)
            _ = host(Probe(name: "horizontal SV margins20", modify: { _ in ScrollView(.horizontal) { HStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.red.frame(width: 50, height: 50) } } }.contentMargins(20) }), size: sz); spin(0.5)
            _ = host(Nested(), size: sz); spin(0.5)
        }
    }
}
