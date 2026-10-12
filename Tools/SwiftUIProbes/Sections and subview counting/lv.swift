import SwiftUI
import AppKit

struct Rank: LayoutValueKey { static let defaultValue: Int = -1 }

struct Reader: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        print("ranks:", subviews.map { $0[Rank.self] }, "lead guides:", subviews.map { $0.dimensions(in: .unspecified)[.leading] })
        return CGSize(width: 10, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}

struct C: View {
    var body: some View {
        Text("a").layoutValue(key: Rank.self, value: 5)
        Text("b").alignmentGuide(.leading) { _ in -7 }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            print("direct"); _ = host(Reader { C() }, size: CGSize(width: 50, height: 50)); spin(0.2)
            print("proxied"); _ = host(Reader { ForEach(subviews: C()) { $0 } }, size: CGSize(width: 50, height: 50)); spin(0.2)
            print("proxied padded"); _ = host(Reader { ForEach(subviews: C()) { $0.padding(0) } }, size: CGSize(width: 50, height: 50)); spin(0.2)
        }
    }
}
