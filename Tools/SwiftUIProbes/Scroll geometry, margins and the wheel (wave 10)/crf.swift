import SwiftUI
import AppKit

struct Item: View {
    let tag: String
    var body: some View {
        Color.red.containerRelativeFrame([.horizontal, .vertical])
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { print(tag, "item frame", $0) }
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 200, height: 300)
            _ = host(ScrollView(.horizontal) { HStack(spacing: 0) { Item(tag: "plain"); Item(tag: "plain2") } }, size: sz); spin(0.4)
            _ = host(ScrollView(.horizontal) { HStack(spacing: 0) { Item(tag: "margins20"); Item(tag: "margins20-2") } }.contentMargins(20), size: sz); spin(0.4)
            _ = host(ScrollView(.horizontal) { HStack(spacing: 0) { Item(tag: "safe20"); Item(tag: "safe20-2") } }.safeAreaPadding(20), size: sz); spin(0.4)
            _ = host(ScrollView(.horizontal) { HStack(spacing: 0) { Item(tag: "margins20 scrollIndicators") } }.contentMargins(20, for: .scrollIndicators), size: sz); spin(0.4)
        }
    }
}
