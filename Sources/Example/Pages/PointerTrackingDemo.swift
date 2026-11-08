//  🖥️ TUI — A Terminal UI framework for Swift
//  PointerTrackingDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Following the pointer (`.onContinuousHover`, where `.onHover` says only in
/// or out), to a fraction of a cell where the terminal can report one, and the modifier keys held (`.onModifierKeysChanged`
/// — which a terminal reports on its own only under the kitty keyboard
/// protocol; elsewhere they are seen when a key or a click carries them).
struct PointerTrackingDemo: View {
    @State private var position = "—"
    @State private var modifiers = "—"

    var body: some View {
        DemoSection("page.mouse.tracking") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.mouse.trackingExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("page.mouse.trackingArea")
                    .foregroundStyle(.palette.foregroundTertiary)
                    .frame(width: 40, height: 5)
                    .border(.palette.border)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): position = Self.spelling(of: point)
                        case .ended: position = "—"
                        }
                    }
                HStack(spacing: 3) {
                    ValueDisplayRow("page.mouse.trackingPointer", position)
                    ValueDisplayRow("page.mouse.trackingModifiers", modifiers)
                }
            }
        }
        .onModifierKeysChanged { _, held in
            modifiers = Self.describe(held)
        }
    }

    /// A location in cells: whole, as most terminals report it, or to two places.
    private static func spelling(of point: CGPoint) -> String {
        guard point.x != point.x.rounded() || point.y != point.y.rounded() else {
            let cell = CellPoint(point)
            return "(\(cell.x), \(cell.y))"
        }
        let places = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return "(\(Double(point.x).formatted(places)), \(Double(point.y).formatted(places)))"
    }

    /// The modifiers held, as a menu writes them — `⌃⌥⇧⌘` — or a dash.
    private static func describe(_ held: EventModifiers) -> String {
        var symbols = ""
        if held.contains(.control) { symbols += "⌃" }
        if held.contains(.option) { symbols += "⌥" }
        if held.contains(.shift) { symbols += "⇧" }
        if held.contains(.command) { symbols += "⌘" }
        return symbols.isEmpty ? "—" : symbols
    }
}
