// Probe: SwiftUI spring loading on macOS 15.8 (SDK 26.2).
// Build: swiftc -parse-as-library spring.swift -o spring && ./spring
import AppKit
import SwiftUI

final class Log: @unchecked Sendable {
    static let shared = Log()
    var lines: [String] = []
    func add(_ s: String) { lines.append(s); print(s) }
}

struct EnvReader: View {
    let tag: String
    @Environment(\.springLoadingBehavior) var behavior
    var body: some View {
        let _ = Log.shared.add("env[\(tag)] springLoadingBehavior = \(behavior == .automatic ? "automatic" : behavior == .enabled ? "enabled" : "disabled")")
        Text(tag)
    }
}

func describe(_ b: SpringLoadingBehavior) -> String {
    b == .automatic ? "automatic" : b == .enabled ? "enabled" : "disabled"
}

func walk(_ view: NSView, depth: Int = 0, into out: inout [NSView]) {
    out.append(view)
    for sub in view.subviews { walk(sub, depth: depth + 1, into: &out) }
}

@MainActor
func host<V: View>(_ name: String, _ content: V, size: CGSize = CGSize(width: 400, height: 300)) -> (NSWindow, NSHostingView<V>) {
    let hosting = NSHostingView(rootView: content)
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -3000, y: -3000), size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    hosting.layoutSubtreeIfNeeded()
    return (window, hosting)
}

@MainActor
func report<V: View>(_ name: String, _ content: V) {
    let (window, hosting) = host(name, content)
    var all: [NSView] = []
    walk(hosting, into: &all)
    var found = false
    for v in all {
        if let b = v as? NSButton {
            found = true
            Log.shared.add("[\(name)] NSButton '\(b.title)' class=\(type(of: b)) isSpringLoaded=\(b.isSpringLoaded) bezel=\(b.bezelStyle.rawValue)")
        }
        if let s = v as? NSSegmentedControl {
            found = true
            Log.shared.add("[\(name)] NSSegmentedControl segments=\(s.segmentCount) isSpringLoaded=\(s.isSpringLoaded)")
        }
        if let t = v as? NSTabView {
            found = true
            Log.shared.add("[\(name)] NSTabView items=\(t.numberOfTabViewItems)")
        }
    }
    if !found {
        Log.shared.add("[\(name)] no AppKit control; classes: \(Set(all.map { String(describing: type(of: $0)) }).sorted().joined(separator: ", "))")
    }
    let sel = NSSelectorFromString("springLoadingEntered:")
    Log.shared.add("[\(name)] hosting responds to springLoadingEntered: \(hosting.responds(to: sel)); conforms NSSpringLoadingDestination: \(hosting.conforms(to: NSSpringLoadingDestination.self))")
    _ = window
}

@main
struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Log.shared.add("springing.delay default = \(UserDefaults.standard.object(forKey: "com.apple.springing.delay") ?? "unset")")
        Log.shared.add("springing.enabled default = \(UserDefaults.standard.object(forKey: "com.apple.springing.enabled") ?? "unset")")

        report("env-root", EnvReader(tag: "root"))
        report("env-enabled", EnvReader(tag: "set enabled").springLoadingBehavior(.enabled))
        report("env-nested", VStack { EnvReader(tag: "inner enabled").springLoadingBehavior(.enabled) }.springLoadingBehavior(.disabled))
        report("env-nested2", VStack { EnvReader(tag: "inner inherits") }.springLoadingBehavior(.disabled))

        for (styleName, behavior) in [("automatic", SpringLoadingBehavior.automatic), ("enabled", .enabled), ("disabled", .disabled)] {
            report("button-default-\(styleName)", Button("Go") {}.springLoadingBehavior(behavior))
            report("button-bordered-\(styleName)", Button("Go") {}.buttonStyle(.bordered).springLoadingBehavior(behavior))
            report("button-borderless-\(styleName)", Button("Go") {}.buttonStyle(.borderless).springLoadingBehavior(behavior))
            report("button-plain-\(styleName)", Button("Go") {}.buttonStyle(.plain).springLoadingBehavior(behavior))
            report("button-link-\(styleName)", Button("Go") {}.buttonStyle(.link).springLoadingBehavior(behavior))
            report("toggle-\(styleName)", Toggle("T", isOn: .constant(true)).springLoadingBehavior(behavior))
            report("segmented-\(styleName)", Picker("P", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented).springLoadingBehavior(behavior))
            report("tabview-\(styleName)", TabView { Text("one").tabItem { Text("One") }; Text("two").tabItem { Text("Two") } }.springLoadingBehavior(behavior))
            report("disclosure-\(styleName)", DisclosureGroup("D") { Text("x") }.springLoadingBehavior(behavior))
            report("menu-\(styleName)", Menu("M") { Button("a") {} }.springLoadingBehavior(behavior))
        }
    }
}
