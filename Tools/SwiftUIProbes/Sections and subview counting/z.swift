import SwiftUI
import AppKit

struct ZContent: View {
    var body: some View {
        Color.red.frame(width: 30, height: 10).zIndex(1)
        Color.blue.frame(width: 30, height: 10)
    }
}

@MainActor func pixel(_ title: String, _ v: some View) {
    let h = host(v.frame(width: 50, height: 20, alignment: .topLeading), size: CGSize(width: 50, height: 20))
    spin(0.3)
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return }
    h.cacheDisplay(in: h.bounds, to: rep)
    let c = rep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)
    print(title, String(format: "(%.2f,%.2f,%.2f)", c?.redComponent ?? -1, c?.greenComponent ?? -1, c?.blueComponent ?? -1))
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            pixel("direct", ZStack(alignment: .topLeading) { ZContent() })
            pixel("proxied", ZStack(alignment: .topLeading) { ForEach(subviews: ZContent()) { $0 } })
            pixel("proxied padded", ZStack(alignment: .topLeading) { ForEach(subviews: ZContent()) { $0.padding(0) } })
            pixel("no zindex", ZStack(alignment: .topLeading) { Color.red.frame(width: 30, height: 10); Color.blue.frame(width: 30, height: 10) })
        }
    }
}
