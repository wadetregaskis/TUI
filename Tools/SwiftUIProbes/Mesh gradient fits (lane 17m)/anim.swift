// Probe: does a MeshGradient animate inside withAnimation? macOS 15.8.
// Build: xcrun swiftc -parse-as-library anim.swift -o anim && ./anim
import AppKit
import SwiftUI

@MainActor
final class Model: ObservableObject {
    @Published var moved = false
    @Published var red = false
}

struct MeshView: View {
    @ObservedObject var model: Model
    var body: some View {
        let x: Float = model.moved ? 0.9 : 0.1
        let corner: Color = model.red ? Color(.sRGB, red: 1, green: 0, blue: 0) : Color(.sRGB, red: 0, green: 0, blue: 1)
        return VStack(spacing: 0) {
            // A 3x2 mesh whose middle column moves: colours black | white | black.
            MeshGradient(
                width: 3, height: 2,
                points: [[0, 0], [x, 0], [1, 0], [0, 1], [x, 1], [1, 1]],
                colors: [.black, .white, .black, .black, .white, .black], smoothsColors: false
            )
            .frame(width: 200, height: 20)
            // A 2x2 mesh whose colours change.
            MeshGradient(
                width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: [corner, corner, corner, corner], smoothsColors: false
            )
            .frame(width: 200, height: 20)
            // A linear gradient whose stop changes, for comparison.
            LinearGradient(colors: [corner, corner], startPoint: .leading, endPoint: .trailing)
                .frame(width: 200, height: 20)
        }
    }
}

@MainActor
func snapshot(_ view: NSView) -> NSBitmapImageRep {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

@MainActor
func brightestColumn(_ rep: NSBitmapImageRep, row: Int) -> Int {
    var best = 0
    var bestValue = -1.0
    for x in 0..<rep.pixelsWide {
        let c = rep.colorAt(x: x, y: row)!.usingColorSpace(.sRGB)!
        let v = c.redComponent + c.greenComponent + c.blueComponent
        if v > bestValue { bestValue = v; best = x }
    }
    return best
}

@MainActor
func colourAt(_ rep: NSBitmapImageRep, x: Int, y: Int) -> String {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    return String(format: "(%.0f, %.0f, %.0f)", c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
}

@main
struct Probe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = Model()
        let hosting = NSHostingView(rootView: MeshView(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 200, height: 60), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        var rep = snapshot(hosting)
        let scale = rep.pixelsWide / 200
        print("scale", scale, "before: brightest column", brightestColumn(rep, row: 10 * scale) / scale,
              "colour", colourAt(rep, x: 100 * scale, y: 30 * scale), "linear", colourAt(rep, x: 100 * scale, y: 50 * scale))
        withAnimation(.linear(duration: 2)) {
            model.moved = true
            model.red = true
        }
        for step in 1...5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            rep = snapshot(hosting)
            print("t≈\(Double(step) * 0.4)s brightest column", brightestColumn(rep, row: 10 * scale) / scale,
                  "colour", colourAt(rep, x: 100 * scale, y: 30 * scale), "linear", colourAt(rep, x: 100 * scale, y: 50 * scale))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        rep = snapshot(hosting)
        print("after: brightest column", brightestColumn(rep, row: 10 * scale) / scale,
              "colour", colourAt(rep, x: 100 * scale, y: 30 * scale), "linear", colourAt(rep, x: 100 * scale, y: 50 * scale))
    }
}
