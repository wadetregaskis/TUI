// Probe (H-67): what a blend mode multiplies against when what is behind it is not one
// opaque view. (1) `Color.yellow.blendMode(.multiply)` over `Color.blue.opacity(0.5)` over a
// white page: the backdrop is the blue at one half over the page, or the blue alone?
// (2) blended text over its own `.background`: do the letters multiply into the fill, and
// does the fill itself blend with what is behind the view?
// Build: xcrun swiftc -parse-as-library -O blendbackdrops.swift -o blendbackdrops && ./blendbackdrops
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

/// The pixel at the middle of `view` drawn 40 × 20.
@MainActor
func centre<V: View>(_ view: V) -> [Int] {
    let b = render(view, width: 40, height: 20)
    let i = (10 * 40 + 20) * 4
    return b[i..<i + 4].map(Int.init)
}

/// The pixels of `view` drawn 120 × 60, most common first, with their counts: for text, the
/// fill is the commonest and the ink at full coverage the next.
@MainActor
func commonest<V: View>(_ view: V, _ count: Int) -> [([Int], Int)] {
    let b = render(view, width: 120, height: 60)
    var tally: [[Int]: Int] = [:]
    for i in stride(from: 0, to: b.count, by: 4) { tally[b[i..<i + 4].map(Int.init), default: 0] += 1 }
    return tally.sorted { $0.value > $1.value }.prefix(count).map { ($0.key, $0.value) }
}

func multiply(_ a: [Int], _ b: [Int]) -> [Int] {
    zip(a.prefix(3), b.prefix(3)).map { (x: Int, y: Int) -> Int in
        let product: Double = Double(x) * Double(y) / 255
        return Int(product.rounded())
    }
}

func mix(_ a: [Int], over b: [Int], at alpha: Double) -> [Int] {
    zip(a.prefix(3), b.prefix(3)).map { (x: Int, y: Int) -> Int in
        let mixed: Double = Double(x) * alpha + Double(y) * (1 - alpha)
        return Int(mixed.rounded())
    }
}

@main
struct Probe {
    @MainActor
    static func main() {
        print("pixels r,g,b,a in sRGB; named colours as ImageRenderer resolves them (light)")
        let named: [(String, Color)] = [("white", .white), ("blue", .blue), ("yellow", .yellow), ("cyan", .cyan)]
        var resolved: [String: [Int]] = [:]
        for (name, color) in named {
            resolved[name] = centre(color)
            print("\(name): \(resolved[name]!)")
        }
        let (white, blue, yellow, cyan) = (resolved["white"]!, resolved["blue"]!, resolved["yellow"]!, resolved["cyan"]!)

        print("\n(1) ZStack { page; Color.blue.opacity(0.5); Color.yellow.blendMode(.multiply) }")
        let halfBlue = centre(ZStack { Color.white; Color.blue.opacity(0.5) })
        print("blue at ½ over the white page: \(halfBlue)  (mix: \(mix(blue, over: white, at: 0.5)))")
        let overPage = centre(ZStack {
            Color.white
            Color.blue.opacity(0.5)
            Color.yellow.blendMode(.multiply)
        })
        print("over the white page: \(overPage)")
        print("  multiply(yellow, blue at ½ over page) = \(multiply(yellow, halfBlue))")
        print("  multiply(yellow, opaque blue)         = \(multiply(yellow, blue))")
        let overNothing = centre(ZStack {
            Color.blue.opacity(0.5)
            Color.yellow.blendMode(.multiply)
        })
        print("over nothing (no page): \(overNothing)")
        let overBlack = centre(ZStack {
            Color.black
            Color.blue.opacity(0.5)
            Color.yellow.blendMode(.multiply)
        })
        print("over a black page: \(overBlack)  (multiply(yellow, blue at ½ over black) = "
            + "\(multiply(yellow, mix(blue, over: [0, 0, 0], at: 0.5))))")

        print("\n(2) blended content over its own .background(Color.yellow)")
        let text = Text("Hi").font(.system(size: 48, weight: .black)).foregroundStyle(.cyan)
        let alone = commonest(ZStack { Color.white; text.background(Color.yellow) }, 3)
        print("text unblended over its fill (commonest): \(alone)")
        let blended = commonest(ZStack { Color.white; text.blendMode(.multiply).background(Color.yellow) }, 3)
        print("text .blendMode(.multiply).background(yellow) over the page (commonest): \(blended)")
        print("  multiply(cyan, yellow) = \(multiply(cyan, yellow))")
        let overBlue = commonest(ZStack { Color.blue; text.blendMode(.multiply).background(Color.yellow) }, 3)
        print("the same over an opaque blue (commonest): \(overBlue)")
        print("  multiply(yellow, blue) = \(multiply(yellow, blue))")
        let fill = centre(ZStack {
            Color.white
            Color.cyan.frame(width: 20).blendMode(.multiply).frame(width: 40).background(Color.yellow)
        })
        print("Color.cyan (20 wide) .blendMode(.multiply) .frame(40) .background(yellow), its middle: \(fill)")
        let beside = render(ZStack {
            Color.blue
            Color.cyan.frame(width: 20).blendMode(.multiply).frame(width: 40).background(Color.yellow)
        }, width: 40, height: 20)
        func at(_ x: Int) -> [Int] { let i = (10 * 40 + x) * 4; return beside[i..<i + 4].map(Int.init) }
        print("the same over an opaque blue: under the cyan \(at(20)), the fill beside it \(at(5))")
    }
}
