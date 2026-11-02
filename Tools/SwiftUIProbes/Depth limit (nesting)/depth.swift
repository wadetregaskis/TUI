import SwiftUI
import AppKit

// What SwiftUI does with a view nested too deeply to draw, for TUI's depth
// limit. Offscreen NSHostingView (after ../Layout priority/priority.swift).
//
//   swiftc -parse-as-library depth.swift -o /tmp/depth
//   ./depth plain 2000; echo $?
//
// Run per shape and depth, one process each: the question is whether the
// process lives. Prints the size laid out, what the leaf saw (whether its body
// ran), and exits 0.

@MainActor final class Seen { static var leaf = false }

struct Leaf: View {
    @State var n = 0
    var body: some View {
        let _ = MainActor.assumeIsolated { Seen.leaf = true }
        Text("leaf \(n)")
    }
}
struct Plain: View {
    let level: Int; let depth: Int
    var body: some View {
        if level >= depth { Leaf() } else { VStack { Plain(level: level + 1, depth: depth) } }
    }
}
struct Erased: View {
    let level: Int; let depth: Int
    var body: some View {
        if level >= depth { AnyView(Leaf()) } else { AnyView(VStack { Erased(level: level + 1, depth: depth) }) }
    }
}
struct Forever: View { var body: some View { VStack { Forever() } } }

@main struct Probe {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let shape = args[1]
        let depth = args.count > 2 ? Int(args[2])! : 0
        _ = NSApplication.shared
        let size = CGSize(width: 400, height: 300)
        func host<V: View>(_ v: V) -> NSView {
            let h = NSHostingView(rootView: v)
            h.frame = NSRect(origin: .zero, size: size)
            let w = NSWindow(
                contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
                backing: .buffered, defer: false)
            w.contentView = h
            w.orderFrontRegardless()
            h.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            return h
        }
        let start = Date()
        let view: NSView
        switch shape {
        case "plain": view = host(Plain(level: 0, depth: depth))
        case "any": view = host(Erased(level: 0, depth: depth))
        case "forever": view = host(Forever())
        default: fatalError()
        }
        print("\(shape) \(depth): alive after \(Int(Date().timeIntervalSince(start) * 1000)) ms; "
            + "fitting \(view.fittingSize); leaf body ran: \(Seen.leaf)")
    }
}
