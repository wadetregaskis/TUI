import SwiftUI
import AppKit

@MainActor func firstInk(_ v: some View, _ sz: CGSize) -> (Int, Int) {
    let h = host(v, size: sz); spin(0.4)
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return (-1, -1) }
    h.cacheDisplay(in: h.bounds, to: rep)
    var top = -1, left = Int.max
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.3, c.alphaComponent > 0.5 {
                if top < 0 { top = y }
                left = min(left, x)
            }
        }
    }
    let scale = rep.pixelsWide / Int(sz.width)
    return (top / scale, left / scale)
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 300, height: 200)
            let text = Binding.constant("MMMM\nMMMM")
            print("TextEditor plain (top,left)", firstInk(TextEditor(text: text).font(.system(size: 30)).environment(\.colorScheme, .light), sz))
            print("TextEditor margins top40", firstInk(TextEditor(text: text).font(.system(size: 30)).contentMargins(.top, 40).environment(\.colorScheme, .light), sz))
            print("TextEditor margins leading40 scrollContent", firstInk(TextEditor(text: text).font(.system(size: 30)).contentMargins(.leading, 40, for: .scrollContent).environment(\.colorScheme, .light), sz))
            print("TextEditor safeArea top40", firstInk(TextEditor(text: text).font(.system(size: 30)).safeAreaPadding(.top, 40).environment(\.colorScheme, .light), sz))
        }
    }
}
