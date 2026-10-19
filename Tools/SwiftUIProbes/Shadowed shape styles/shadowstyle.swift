// Probe: SwiftUI ShapeStyle.shadow(_:) on macOS 15.8 (SDK 26.2), read back as pixels.
// Build: xcrun swiftc -parse-as-library -O shadowstyle.swift -o shadowstyle && ./shadowstyle
import AppKit
import SwiftUI

@MainActor
func render<V: View>(_ view: V, width: Int, height: Int) -> [UInt8] {
    let renderer = ImageRenderer(content: view.frame(width: CGFloat(width), height: CGFloat(height)))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.cgImage else { fatalError("no image") }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let ctx = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

@MainActor
func px<V: View>(_ name: String, _ view: V, w: Int = 100, h: Int = 100, at points: [(Int, Int)]) {
    let b = render(view, width: w, height: h)
    var out = "\(name):"
    for (x, y) in points {
        let i = (y * w + x) * 4
        out += " (\(x),\(y))=\(b[i]),\(b[i+1]),\(b[i+2]),\(b[i+3])"
    }
    print(out)
}

@main
struct Probe {
    @MainActor
    static func main() {
        let pts = [(30, 30), (55, 55), (65, 65), (75, 75), (60, 30), (30, 60), (21, 21), (39, 39)]
        // Q1: static .shadow in .background: implicit = foreground or background style?
        px("Q1 background(.shadow(drop))", ZStack {
            Color.clear.frame(width: 40, height: 40)
                .background(.shadow(.drop(color: .black, radius: 0, x: 30, y: 30)))
        }.foregroundStyle(.red).backgroundStyle(.blue), at: pts)
        // Q2: backgroundStyle(.shadow(inner)) + .background()
        px("Q2 backgroundStyle(.shadow(inner))+background()", ZStack {
            Color.clear.frame(width: 40, height: 40).background()
        }.backgroundStyle(.shadow(.inner(color: .black, radius: 0, x: 5, y: 5))).foregroundStyle(.red), at: pts)
        px("Q2b backgroundStyle(.green) then inner", ZStack {
            Color.clear.frame(width: 40, height: 40).background()
                .backgroundStyle(.shadow(.inner(color: .black, radius: 0, x: 5, y: 5)))
        }.backgroundStyle(.green).foregroundStyle(.red), at: pts)
        // Q4: .secondary under shadowed foreground
        px("Q4 fill(.secondary) under shadowed fg", ZStack {
            Rectangle().fill(.secondary).frame(width: 40, height: 40)
        }.foregroundStyle(.red.shadow(.drop(color: .black, radius: 0, x: 30, y: 30))), at: pts)
        px("Q4b fill(.foreground) under shadowed fg", ZStack {
            Rectangle().fill(.foreground).frame(width: 40, height: 40)
        }.foregroundStyle(.red.shadow(.drop(color: .black, radius: 0, x: 30, y: 30))), at: pts)
        // Q5: opacity after shadow
        px("Q5 red.shadow.opacity(0.5)", ZStack {
            Rectangle().fill(.red.shadow(.drop(color: .black, radius: 0, x: 30, y: 30)).opacity(0.5)).frame(width: 40, height: 40)
        }, at: pts)
        px("Q5b red.opacity(0.5).shadow", ZStack {
            Rectangle().fill(.red.opacity(0.5).shadow(.drop(color: .black, radius: 0, x: 30, y: 30))).frame(width: 40, height: 40)
        }, at: pts)
        // Q6: shadow of a shadow
        px("Q6 shadow(A x30).shadow(B y30)", ZStack {
            Rectangle().fill(.red.shadow(.drop(color: .black, radius: 0, x: 30, y: 0)).shadow(.drop(color: .blue, radius: 0, x: 0, y: 30))).frame(width: 40, height: 40)
        }, at: [(30, 30), (60, 30), (30, 60), (60, 60), (75, 75)])
        // Q9: inner shadow in background: over or under the content?
        px("Q9 background(blue.inner) with white content TL", ZStack(alignment: .topLeading) {
            Color.white.frame(width: 10, height: 10)
        }.frame(width: 40, height: 40, alignment: .topLeading)
            .background(.blue.shadow(.inner(color: .black, radius: 0, x: 5, y: 5))), w: 40, h: 40,
           at: [(1, 1), (5, 5), (12, 12), (2, 20), (20, 2), (38, 38)])
        // Q10: Text casting from foregroundStyle shadow: compare with fill under text
        px("Q10 text fg shadow", Text("██").font(.system(size: 30)).foregroundStyle(.red.shadow(.drop(color: .black, radius: 0, x: 0, y: 20))), w: 100, h: 100, at: [(50, 50), (50, 75), (50, 90)])
        // Q11: stroke with shadowed style
        px("Q11 stroke shadow", Circle().stroke(.red.shadow(.drop(color: .black, radius: 0, x: 0, y: 10)), lineWidth: 4).frame(width: 60, height: 60), at: [(50, 22), (50, 32), (50, 50), (50, 82), (50, 90)])
        // Q12: background(style) drop shadow under content
        px("Q12 Text background shadow", Text("hi").frame(width: 40, height: 40).background(.blue.shadow(.drop(color: .black, radius: 0, x: 30, y: 30))), at: pts)
        // Q13: border with shadow
        px("Q13 border shadow", Color.clear.frame(width: 40, height: 40).border(.red.shadow(.drop(color: .black, radius: 0, x: 0, y: 5)), width: 2), at: [(50, 31), (50, 32), (50, 36), (50, 68), (50, 70), (50, 74)])
    }
}
