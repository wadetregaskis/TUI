import AppKit
import SwiftUI

// Shared by traits.swift: a borderless window off screen that can become key,
// a run-loop spin, the AppKit views SwiftUI made, and the wrappers each case
// puts round the view that carries the trait.

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor var keep: [NSWindow] = []

@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = KeyableWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func subviews<T: NSView>(of v: NSView, _: T.Type) -> [T] {
    var out: [T] = []
    if let t = v as? T { out.append(t) }
    for c in v.subviews { out += subviews(of: c, T.self) }
    return out
}

/// The wrapper written after the trait, innermost trait first: `view.trait.<wrapper>`.
enum Wrap: String, CaseIterable {
    case none = "(no wrapper)"
    case padding0 = ".padding(0)"
    case overlay = ".overlay { }"
    case background = ".background { }"
    case contextMenu = ".contextMenu { }"
    case clipped = ".clipped()"
    case clipShape = ".clipShape(Rectangle())"
    case mask = ".mask { }"
}

extension View {
    @ViewBuilder func wrapped(_ w: Wrap) -> some View {
        switch w {
        case .none: self
        case .padding0: padding(0)
        case .overlay: overlay(alignment: .topLeading) { Text("·") }
        case .background: background { Color.clear }
        case .contextMenu: contextMenu { Button("Menu item") {} }
        case .clipped: clipped()
        case .clipShape: clipShape(Rectangle())
        case .mask: mask { Rectangle() }
        }
    }
}

@MainActor func label(_ s: String, _ width: Int = 34) -> String {
    s.padding(toLength: width, withPad: " ", startingAt: 0)
}
