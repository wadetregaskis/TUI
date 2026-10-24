import SwiftUI
import AppKit

/// FB16: does SwiftUI move a view's siblings when the view is inserted with a
/// transition that does not move it (opacity, scale)? Each column inserts its
/// middle row with one transition under an 8 s linear animation, on a loop:
/// shown 10 s, hidden 10 s. Screenshots mid-animation show where "Below" is.
struct Column: View {
    let title: String
    let transition: AnyTransition
    let shown: Bool
    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline)
            Text("Above").frame(width: 120, height: 30).background(Color.blue.opacity(0.3))
            if shown {
                Text("Inserted").frame(width: 120, height: 60).background(Color.red.opacity(0.5))
                    .transition(transition)
            }
            Text("Below").frame(width: 120, height: 30).background(Color.green.opacity(0.5))
            Spacer()
        }
        .frame(width: 140, height: 220, alignment: .top)
        .border(Color.gray)
    }
}

struct ProbeView: View {
    @State var shown = false
    @State var started = Date()
    var body: some View {
        VStack {
            Text(shown ? "SHOWN (animating in over 8 s)" : "HIDDEN (animating out over 8 s)")
            HStack(alignment: .top) {
                Column(title: "opacity", transition: .opacity, shown: shown)
                Column(title: "scale", transition: .scale, shown: shown)
                Column(title: "move top", transition: .move(edge: .top), shown: shown)
                Column(title: "identity", transition: .identity, shown: shown)
                Column(title: "push", transition: .push(from: .top), shown: shown)
            }
        }
        .padding()
        .task {
            // Two insertions and two removals, sampled every 0.5 s, then quit.
            for cycle in 0..<4 {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.linear(duration: 8)) { shown.toggle() }
                for step in 0...20 {
                    Sampler.sample(label: "\(cycle % 2 == 0 ? "insert" : "remove") t=\(Double(step) * 0.5)")
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

@main
struct FB16Probe: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

/// Walks this app's layer tree and prints every layer with a background
/// colour (the coloured boxes) at its PRESENTATION frame — where it is drawn
/// at this instant of the animation, not where the model says it ends.
enum Sampler {
    @MainActor static func sample(label: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let root = window.contentView?.layer else {
            print("\(label): no layer"); return
        }
        var found: [String] = []
        func walk(_ layer: CALayer, depth: Int) {
            let shown = layer.presentation() ?? layer
            if let colour = shown.backgroundColor, let rgb = NSColor(cgColor: colour)?.usingColorSpace(.sRGB) {
                let frame = shown.convert(shown.bounds, to: root.presentation() ?? root)
                let name = rgb.redComponent > 0.6 && rgb.greenComponent < 0.5 ? "RED" : rgb.greenComponent > 0.4 && rgb.redComponent < 0.3 ? "GREEN" : rgb.blueComponent > 0.6 ? "BLUE" : "other"
                if name != "other" {
                    found.append("\(name)@x\(Int(frame.minX)) y\(Int(frame.minY)) h\(Int(frame.height)) a\(String(format: "%.2f", shown.opacity))")
                }
            }
            for sub in layer.sublayers ?? [] { walk(sub, depth: depth + 1) }
        }
        walk(root, depth: 0)
        print("\(label): " + found.joined(separator: "  "))
        fflush(stdout)
    }
}
