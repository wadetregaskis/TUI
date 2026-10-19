// Which bodies of an app's own view a stack takes apart (decisions B-D1S-6):
// a body that is an if/else of several views, a modifier on a Group of
// several, an AnyView of several, and a modifier on such a view from outside;
// and how often an effect on a body of several fires.
//
// Built alone, not with common.swift, whose `Box` and `probe(_:)` it
// defines its own way. Build and run (from this folder):
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 composite-bodies.swift -o "$TMPDIR/composite-bodies"
//   "$TMPDIR/composite-bodies" | diff composite-bodies.out -

import AppKit
import SwiftUI

@MainActor var keep: [NSWindow] = []

@MainActor func host<V: View>(_ view: V, size: CGSize) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    keep.append(window)
    hosting.layoutSubtreeIfNeeded()
}

@MainActor func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor final class Frames { static var all: [String: CGRect] = [:]; static var fired = 0 }

extension View {
    func probe(_ name: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { Frames.all[name] = $0 }
    }
}

/// Prints each tagged leaf's origin, sorted by name.
@MainActor func measure(_ title: String, _ view: some View) {
    Frames.all = [:]
    Frames.fired = 0
    let size = CGSize(width: 400, height: 200)
    host(view.coordinateSpace(.named("root")).frame(width: size.width, height: size.height, alignment: .topLeading), size: size)
    spin()
    let line = Frames.all.sorted { $0.key < $1.key }
        .map { "\($0.key)@(\(Int($0.value.minX.rounded())),\(Int($0.value.minY.rounded())))" }
        .joined(separator: " ")
    print("== \(title): \(line) fired=\(Frames.fired)")
}

struct Box: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View { Color.red.frame(width: 20, height: 10).probe(name) }
}

struct IfElseBody: View {
    let flag: Bool
    var body: some View {
        if flag { Box("a"); Box("b") } else { Box("c") }
    }
}

struct ModifiedGroupBody: View {
    var body: some View { Group { Box("a"); Box("b") }.padding(.leading, 5) }
}

struct AnyViewBody: View {
    var body: some View { AnyView(Group { Box("a"); Box("b") }) }
}

struct Rows: View {
    var body: some View { Box("a"); Box("b") }
}

struct EffectBody: View {
    var body: some View { Group { Box("a"); Box("b") }.onAppear { Frames.fired += 1 } }
}

struct OpacityGroupBody: View {
    var body: some View { Group { Box("a"); Box("b") }.opacity(0.5) }
}

struct Tree: View {
    let depth: Int
    var body: some View {
        if depth == 0 { Box("leaf") } else { Tree(depth: depth - 1).padding(.leading, 1) }
    }
}

@main struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        measure("if/else body, true", HStack(spacing: 0) { IfElseBody(flag: true) })
        measure("if/else body, false", HStack(spacing: 0) { IfElseBody(flag: false); Box("d") })
        measure("Group.padding body", HStack(spacing: 0) { ModifiedGroupBody() })
        measure("AnyView body", HStack(spacing: 0) { AnyViewBody() })
        measure("Rows().padding", HStack(spacing: 0) { Rows().padding(.leading, 5) })
        measure("Rows().opacity", HStack(spacing: 0) { Rows().opacity(0.5) })
        measure("Group.opacity body", HStack(spacing: 0) { OpacityGroupBody() })
        measure("Group.onAppear body", HStack(spacing: 0) { EffectBody() })
        measure("Rows().onAppear", HStack(spacing: 0) { Rows().onAppear { Frames.fired += 1 } })
        measure("Tree(3)", HStack(spacing: 0) { Tree(depth: 3) })
    }
}
