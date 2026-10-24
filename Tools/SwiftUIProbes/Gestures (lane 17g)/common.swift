import SwiftUI
import AppKit

@MainActor var keep: [NSWindow] = []
@MainActor var t0 = ProcessInfo.processInfo.systemUptime
@MainActor func log(_ s: String) { print(String(format: "%7.3f ", ProcessInfo.processInfo.systemUptime - t0) + s) }

/// One scripted mouse event: `at` seconds after the script starts.
struct Step {
    var at: Double
    var type: NSEvent.EventType
    var x: CGFloat
    var y: CGFloat
    var mods: NSEvent.ModifierFlags = []
    var clickCount: Int = 1
}

@MainActor final class Probe {
    let window: NSWindow
    let size: CGSize
    init<V: View>(_ v: V, size: CGSize = CGSize(width: 200, height: 200)) {
        self.size = size
        let h = NSHostingView(rootView: AnyView(v))
        h.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = h
        w.orderFrontRegardless()
        keep.append(w)
        h.layoutSubtreeIfNeeded()
        window = w
        spin(0.3)
    }
    func make(_ s: Step) -> NSEvent {
        let p = NSPoint(x: s.x, y: size.height - s.y)
        return NSEvent.mouseEvent(with: s.type, location: p, modifierFlags: s.mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: s.clickCount, pressure: s.type == .leftMouseUp ? 0 : 1)!
    }
    /// Posts every step on a timer (so a tracking loop inside sendEvent still
    /// receives the later ones), and pumps the queue until `tail` seconds
    /// after the last.
    func play(_ steps: [Step], tail: Double = 0.6) {
        let start = Date()
        for s in steps {
            let timer = Timer(fire: start.addingTimeInterval(s.at), interval: 0, repeats: false) { [self] _ in
                MainActor.assumeIsolated {
                    let name: String
                    switch s.type {
                    case .leftMouseDown: name = "down"
                    case .leftMouseUp: name = "up"
                    case .leftMouseDragged: name = "drag"
                    default: name = "\(s.type.rawValue)"
                    }
                    log("-- \(name) \(s.x),\(s.y)" + (s.clickCount != 1 ? " cc\(s.clickCount)" : "") + (s.mods.isEmpty ? "" : " mods\(s.mods.rawValue)"))
                    NSApp.postEvent(make(s), atStart: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        let end = start.addingTimeInterval((steps.map(\.at).max() ?? 0) + tail)
        pump(until: end)
    }
    func click(_ x: CGFloat, _ y: CGFloat, at: Double = 0, clickCount: Int = 1, mods: NSEvent.ModifierFlags = []) -> [Step] {
        [Step(at: at, type: .leftMouseDown, x: x, y: y, mods: mods, clickCount: clickCount),
         Step(at: at + 0.03, type: .leftMouseUp, x: x, y: y, mods: mods, clickCount: clickCount)]
    }
}
@MainActor func pump(until end: Date) {
    while Date() < end {
        if let e = NSApp.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.01)), inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    }
}
@MainActor func spin(_ s: Double = 0.3) { pump(until: Date().addingTimeInterval(s)) }
@MainActor func section(_ s: String) { print("\n=== " + s) }
@MainActor func setup() { setvbuf(stdout, nil, _IOLBF, 0); _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching(); t0 = ProcessInfo.processInfo.systemUptime; log("setup done") }

func D(_ at: Double, _ x: CGFloat, _ y: CGFloat, mods: NSEvent.ModifierFlags = [], cc: Int = 1) -> Step { Step(at: at, type: .leftMouseDown, x: x, y: y, mods: mods, clickCount: cc) }
func M(_ at: Double, _ x: CGFloat, _ y: CGFloat, mods: NSEvent.ModifierFlags = []) -> Step { Step(at: at, type: .leftMouseDragged, x: x, y: y, mods: mods) }
func U(_ at: Double, _ x: CGFloat, _ y: CGFloat, mods: NSEvent.ModifierFlags = [], cc: Int = 1) -> Step { Step(at: at, type: .leftMouseUp, x: x, y: y, mods: mods, clickCount: cc) }
