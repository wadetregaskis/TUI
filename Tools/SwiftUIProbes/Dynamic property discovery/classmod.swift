// classmod.swift: does SwiftUI run update() on a class that is both a DynamicProperty and a
// ViewModifier, held in a view's field (decisions DYNVFIX, B-DYNVFIX-4)? And how often per body,
// where the view's body applies that same object (`.modifier(mod)`), or never applies it? Its
// @Environment is read in its body(content:) and in the holding view's body. Output: classmod.out.
// Build: swiftc -sdk <Xcode SDK> -target arm64-apple-macos15.0 classmod.swift -o classmod

import SwiftUI
import AppKit

setvbuf(stdout, nil, _IONBF, 0)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Log {
    static var lines: [String] = []
    static var bumps: [String: () -> Void] = [:]
}

/// Both a DynamicProperty and a ViewModifier.
final class ClassMod: ViewModifier, DynamicProperty {
    let tag: String
    var updates = 0
    @Environment(\.lineLimit) var limit
    init(tag: String) { self.tag = tag }
    func update() { updates += 1 }
    func body(content: Content) -> some View {
        MainActor.assumeIsolated { Log.lines.append("  \(tag) modifier body: updates=\(updates) limit=\(String(describing: limit))") }
        return content
    }
}

/// Holds the object and applies it.
struct Applied: View {
    let mod: ClassMod
    @State var tick = 0
    var body: some View {
        MainActor.assumeIsolated {
            Log.lines.append("  applied view body tick=\(tick): updates=\(mod.updates) limit=\(String(describing: mod.limit))")
            Log.bumps["applied"] = { [self] in tick += 1 }
        }
        return Text("x").modifier(mod)
    }
}

/// Holds the object and never applies it.
struct Stored: View {
    let mod: ClassMod
    @State var tick = 0
    var body: some View {
        MainActor.assumeIsolated {
            Log.lines.append("  stored view body tick=\(tick): updates=\(mod.updates) limit=\(String(describing: mod.limit))")
            Log.bumps["stored"] = { [self] in tick += 1 }
        }
        return Text("x")
    }
}

/// Applies an object made in its body, held nowhere else.
struct Fresh: View {
    @State var tick = 0
    static var last: ClassMod?
    var body: some View {
        let mod = ClassMod(tag: "fresh")
        MainActor.assumeIsolated {
            Fresh.last = mod
            Log.lines.append("  fresh view body tick=\(tick)")
            Log.bumps["fresh"] = { [self] in tick += 1 }
        }
        return Text("x").modifier(mod)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let applied = ClassMod(tag: "applied")
    let stored = ClassMod(tag: "stored")
    // The case to run is the first argument: "applied" and "fresh" stop the process (SwiftUI traps:
    // "view modifiers must be value types"), so each runs on its own.
    let which = CommandLine.arguments.dropFirst().first ?? "stored"
    let cases: [(String, AnyView, () -> ClassMod?)] = [
        ("applied", AnyView(Applied(mod: applied).lineLimit(3)), { applied }),
        ("stored", AnyView(Stored(mod: stored).lineLimit(3)), { stored }),
        ("fresh", AnyView(Fresh().lineLimit(3)), { Fresh.last }),
    ].filter { $0.0 == which }
    for (name, view, object) in cases {
        print("== \(name)")
        Log.lines = []
        let h = host(view)
        spin()
        h.layoutSubtreeIfNeeded()
        for line in Log.lines { print(line) }
        print("  after first frame: object updates=\(object()?.updates ?? -1)")
        Log.lines = []
        Log.bumps[name]?()
        spin()
        h.layoutSubtreeIfNeeded()
        spin(0.1)
        for line in Log.lines { print(line) }
        print("  after the view's state changed: object updates=\(object()?.updates ?? -1)")
    }
}
