// Probe 2: drive SwiftUI's own spring-loading entry points with a fake
// NSDraggingInfo, on macOS 15.8 (SDK 26.2). Where is spring loading offered,
// with which options, and what does activating do?
// Build: swiftc -parse-as-library spring2.swift -o spring2 && ./spring2
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

@MainActor
final class Model {
    var tab = 1 { didSet { say("  -> tab selection set to \(tab)") } }
    var expanded = false { didSet { say("  -> disclosure isExpanded set to \(expanded)") } }
}

@main
struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let model = Model()
        let tabBinding = Binding(get: { model.tab }, set: { model.tab = $0 })
        let discBinding = Binding(get: { model.expanded }, set: { model.expanded = $0 })

        for (bName, b) in [("automatic", SpringLoadingBehavior.automatic), ("enabled", .enabled), ("disabled", .disabled)] {
            say("=== behavior \(bName)")
            let (w1, h1, p1) = scan("plain button \(bName)", Button("Go plain") { say("  -> plain button action") }.buttonStyle(.plain).springLoadingBehavior(b))
            if let p = p1.first { activate("plain button \(bName)", window: w1, hosting: h1, at: p) }

            let (w2, h2, p2) = scan("bordered button \(bName)", Button("Go bordered") { say("  -> bordered button action") }.springLoadingBehavior(b))
            if let p = p2.first { activate("bordered button \(bName)", window: w2, hosting: h2, at: p) }

            let tabs = TabView(selection: tabBinding) {
                Text("one").tabItem { Text("One") }.tag(1)
                Text("two").tabItem { Text("Two") }.tag(2)
                Text("three").tabItem { Text("Three") }.tag(3)
            }.springLoadingBehavior(b)
            let (w3, h3, p3) = scan("tabview \(bName)", tabs)
            if let p = p3.last { activate("tabview \(bName)", window: w3, hosting: h3, at: p) }

            let disc = DisclosureGroup("Disclose", isExpanded: discBinding) { Text("x") }.springLoadingBehavior(b)
            let (w4, h4, p4) = scan("disclosure \(bName)", disc)
            if let p = p4.first { activate("disclosure \(bName)", window: w4, hosting: h4, at: p) }

            let (w5, h5, p5) = scan("text \(bName)", Text("just text").springLoadingBehavior(b))
            if let p = p5.first { activate("text \(bName)", window: w5, hosting: h5, at: p) }

            let link = NavigationLink("Link") { Text("dest") }.springLoadingBehavior(b)
            let (w6, h6, p6) = scan("navlink \(bName)", NavigationStack { link })
            if let p = p6.first { activate("navlink \(bName)", window: w6, hosting: h6, at: p) }
        }
        // The AppKit-backed button itself.
        let (_, hb) = host(Button("Direct") { say("  -> direct NSButton action") }.springLoadingBehavior(.enabled))
        func find(_ v: NSView) -> NSButton? { if let b = v as? NSButton { return b }; for s in v.subviews { if let b = find(s) { return b } }; return nil }
        if let button = find(hb) {
            say("NSButton responds springLoadingEntered: \(button.responds(to: NSSelectorFromString("springLoadingEntered:"))), springLoadingActivated: \(button.responds(to: NSSelectorFromString("springLoadingActivated:draggingInfo:")))")
            let info = FakeDrag(window: hb.window, location: .zero)
            if let o = entered(button, info) { say("NSButton entered -> \(o)") }
            activated(button, true, info)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }
}
