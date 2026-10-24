// Probe 7: does a SwiftUI ColorPicker's colour well spring-load, on macOS
// 15.8 (SDK 26.2)? Owner ruling B82: TUIkit's well follows what macOS's does.
// Scans the hosting view with a fake NSDraggingInfo, as spring2.swift does,
// under each behavior; activates the first spring-loadable point; reports
// whether the colour panel opened, and what the AppKit well itself answers.
// Build: swiftc -parse-as-library spring7.swift -o spring7 && ./spring7
import AppKit
import SwiftUI

nonisolated(unsafe) var log: [String] = []
func say(_ s: String) { log.append(s); print(s) }

final class FakeDrag: NSObject, NSDraggingInfo {
    var window: NSWindow?
    var location: NSPoint
    init(window: NSWindow?, location: NSPoint) { self.window = window; self.location = location }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { NSPasteboard(name: .drag) }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 42 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor
func host<V: View>(_ content: V, size: CGSize = CGSize(width: 300, height: 200)) -> (NSWindow, NSHostingView<V>) {
    let hosting = NSHostingView(rootView: content)
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    hosting.layoutSubtreeIfNeeded()
    return (window, hosting)
}

typealias EnteredFn = @convention(c) (AnyObject, Selector, AnyObject) -> UInt
typealias ActivatedFn = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
typealias ObjFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void

@MainActor
func entered(_ target: NSObject, _ info: FakeDrag) -> UInt? {
    let sel = NSSelectorFromString("springLoadingEntered:")
    guard target.responds(to: sel), let imp = target.method(for: sel) else { return nil }
    return unsafeBitCast(imp, to: EnteredFn.self)(target, sel, info)
}

@MainActor
func updated(_ target: NSObject, _ info: FakeDrag) -> UInt? {
    let sel = NSSelectorFromString("springLoadingUpdated:")
    guard target.responds(to: sel), let imp = target.method(for: sel) else { return nil }
    return unsafeBitCast(imp, to: EnteredFn.self)(target, sel, info)
}

@MainActor
func activated(_ target: NSObject, _ on: Bool, _ info: FakeDrag) {
    let sel = NSSelectorFromString("springLoadingActivated:draggingInfo:")
    guard target.responds(to: sel), let imp = target.method(for: sel) else { say("  (no springLoadingActivated)"); return }
    unsafeBitCast(imp, to: ActivatedFn.self)(target, sel, on, info)
}

@MainActor
func call(_ target: NSObject, _ name: String, _ info: FakeDrag) {
    let sel = NSSelectorFromString(name)
    guard target.responds(to: sel), let imp = target.method(for: sel) else { say("  (no \(name))"); return }
    unsafeBitCast(imp, to: ObjFn.self)(target, sel, info)
}

/// Scan a grid of points and report where spring loading is offered.
@MainActor
func scan<V: View>(_ name: String, _ content: V, size: CGSize = CGSize(width: 300, height: 200)) -> (NSWindow, NSHostingView<V>, [NSPoint]) {
    let (window, hosting) = host(content, size: size)
    var hits: [NSPoint] = []
    var opts = Set<UInt>()
    var y = 2.0
    while y < size.height {
        var x = 2.0
        while x < size.width {
            let info = FakeDrag(window: window, location: NSPoint(x: x, y: y))
            if let o = entered(hosting, info), o != 0 { hits.append(info.location); opts.insert(o) }
            if hosting.responds(to: NSSelectorFromString("springLoadingExited:")) { call(hosting, "springLoadingExited:", info) }
            x += 6
        }
        y += 4
    }
    if hits.isEmpty {
        say("[\(name)] no spring-loadable point")
    } else {
        let xs = hits.map(\.x), ys = hits.map(\.y)
        say("[\(name)] \(hits.count) spring-loadable points, x \(xs.min()!)…\(xs.max()!), y \(ys.min()!)…\(ys.max()!) (window coords, origin bottom-left), options \(opts.sorted())")
    }
    return (window, hosting, hits)
}

@MainActor
func activate<V: View>(_ name: String, window: NSWindow, hosting: NSHostingView<V>, at point: NSPoint) {
    let info = FakeDrag(window: window, location: point)
    let o = entered(hosting, info)
    say("[\(name)] entered at \(point) -> \(o.map(String.init) ?? "nil")")
    if let u = updated(hosting, info) { say("[\(name)] updated -> \(u)") }
    say("[\(name)] activated(true)…")
    activated(hosting, true, info)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    hosting.layoutSubtreeIfNeeded()
    say("[\(name)] activated(false)…")
    activated(hosting, false, info)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    say("[\(name)] activated(true) again…")
    activated(hosting, true, info)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    call(hosting, "springLoadingExited:", info)
}

@main
struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var colour = Color.red
        let binding = Binding(get: { colour }, set: { colour = $0; say("  -> colour set") })
        for (bName, b) in [("automatic", SpringLoadingBehavior.automatic), ("enabled", .enabled), ("disabled", .disabled)] {
            say("=== behavior \(bName)")
            NSColorPanel.shared.orderOut(nil)
            let (w, h, points) = scan("colorpicker \(bName)", ColorPicker("Tint", selection: binding).springLoadingBehavior(b))
            if let p = points.first {
                activate("colorpicker \(bName)", window: w, hosting: h, at: p)
                say("  colour panel visible after activation: \(NSColorPanel.shared.isVisible)")
            }
            func find(_ v: NSView) -> NSColorWell? {
                if let well = v as? NSColorWell { return well }
                for s in v.subviews { if let well = find(s) { return well } }
                return nil
            }
            if let well = find(h) {
                let entered = NSSelectorFromString("springLoadingEntered:")
                say("  NSColorWell \(type(of: well)) responds springLoadingEntered: \(well.responds(to: entered)), conforms NSSpringLoadingDestination: \(well.conforms(to: NSSpringLoadingDestination.self))")
            } else {
                say("  no NSColorWell in the hierarchy")
            }
        }
    }
}
